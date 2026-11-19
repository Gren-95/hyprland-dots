import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0
    // Set from the bar so the launcher flyout hangs under the launcher icon.
    property var anchorBar: null
    signal navigateNext()
    signal navigatePrev()

    // Shell command palette: wired from shell.qml ({name, glyph, accent,
    // keywords, isToggle, state()?, run()}). Toggles flip in place with
    // live state; everything else runs/opens and the launcher closes
    // (flyout-openers close it via the single-open policy anyway).
    property var shellActions: []

    // ===== Hiding apps =====
    // Ctrl+D drops the highlighted app from the list (Ctrl+H is already the
    // flyout ring's vim-left). The list stays open — hiding a run of entries
    // should not mean reopening the launcher between each one. Showing one
    // again is the settings app's job (Launcher > Hidden apps), as is picking
    // default apps (Default apps).
    // The Games view: Steam games and Game-category apps only (GamesService).
    property bool gamesView: false
    function toggleGamesView() {
        gamesView = !gamesView;
        if (gamesView) games.refresh();
        selectedIndex = 0;
    }
    function openHiddenApps() {
        Cmd.run([Paths.home + "/.local/bin/settings", "-p", "launcher"]);
        root.close();
    }
    function toggleHidden(i) {
        const item = root.shownApps[i - root.appOffset];
        if (!item || !item.id) return;
        settingsStore.setAppHidden(item.id, !settingsStore.isAppHidden(item.id));
        // The row under the cursor just left the list; keep the index in range.
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.totalRows - 1));
    }

    readonly property var matchedActions: {
        const q = root.query.trim().toLowerCase();
        if (!q || !settingsStore.spotlightActions) return [];
        return shellActions.filter(a =>
            a.name.toLowerCase().includes(q)
            || (a.keywords && a.keywords.indexOf(q) >= 0)
        ).slice(0, 6);
    }

    readonly property string calcExpr: {
        if (!settingsStore.spotlightCalc) return "";
        const q = root.query.trim();
        if (q.startsWith("=")) return q.slice(1).trim();
        // auto-detect: has at least one digit and one operator
        if (/[+\-*/%]/.test(q) && /\d/.test(q) && /^[\d+\-*/.()\s%]+$/.test(q)) return q;
        return "";
    }
    readonly property string calcResult: {
        if (!root.calcExpr) return "";
        try {
            const r = new Function("return (" + root.calcExpr + ")")();
            if (typeof r === "number" && isFinite(r)) {
                return Number.isInteger(r) ? String(r) : String(parseFloat(r.toFixed(10)));
            }
        } catch (e) {}
        return "";
    }
    readonly property bool hasCalc: root.calcResult !== ""

    readonly property var filtered: {
        if (!DesktopEntries.applications) return [];
        const apps = DesktopEntries.applications.values || [];
        const all = root.gamesView ? games.list(apps) : apps;
        const q = root.query.toLowerCase();
        return all
            .filter(a => !a.noDisplay)
            .filter(a => !settingsStore.isAppHidden(a.id))
            .filter(a => {
                if (!q) return true;
                const name = (a.name || "").toLowerCase();
                const gen = (a.genericName || "").toLowerCase();
                const cmt = (a.comment || "").toLowerCase();
                return name.includes(q) || gen.includes(q) || cmt.includes(q);
            })
            .sort((a, b) => {
                if (q) {
                    const an = (a.name || "").toLowerCase();
                    const bn = (b.name || "").toLowerCase();
                    const aStarts = an.startsWith(q) ? 0 : 1;
                    const bStarts = bn.startsWith(q) ? 0 : 1;
                    if (aStarts !== bStarts) return aStarts - bStarts;
                }
                return (a.name || "").localeCompare(b.name || "");
            });
    }

    // Rows only exist for the apps shown, so the indices below count those,
    // not everything that matched.
    readonly property var shownApps: filtered.slice(0, settingsStore.spotlightCap)

    // Row order: calculator result, apps, then shell actions.
    readonly property int calcOffset: hasCalc ? 1 : 0
    readonly property int appOffset: calcOffset
    readonly property int actionOffset: appOffset + shownApps.length
    readonly property int totalRows: actionOffset + matchedActions.length

    // Opening through the shortcut always starts on all apps.
    function toggle() {
        if (open) { close(); return; }
        gamesView = false;
        open = true;
        query = ""; selectedIndex = 0;
    }
    function openAt(idx) {
        if (!open) { gamesView = false; open = true; query = ""; }
        selectedIndex = idx < 0 ? Math.max(0, root.totalRows - 1)
                                : Math.min(idx, Math.max(0, root.totalRows - 1));
    }
    function close() { open = false; gamesView = false; }
    // The highlighted shell-toggle action, if any (drives Space-to-toggle).
    function highlightedToggle() {
        const ai = selectedIndex - actionOffset;
        const a = ai >= 0 && ai < matchedActions.length ? matchedActions[ai] : null;
        return a && a.isToggle ? a : null;
    }
    function activate(i) {
        if (hasCalc && i === 0) {
            copyProc.command = ["wl-copy", root.calcResult];
            copyProc.startDetached();
            close();
            return;
        }
        const ai = i - actionOffset;
        if (ai >= 0 && ai < matchedActions.length) {
            const a = matchedActions[ai];
            a.run();
            if (!a.isToggle) close();
            return;
        }
        const item = shownApps[i - appOffset];
        if (item) item.execute();
        close();
    }

    Process { id: copyProc; command: [] }

    // Popup height follows the list (up to what the screen allows), so there
    // is no dead space under the last row; the footer stays pinned below it.
    readonly property real fitHeight: Math.max(340, Math.min(
        anchorBar && anchorBar.screen ? Math.min(anchorBar.screen.height - 160, 680) : 600,
        contentCol.implicitHeight))

    readonly property string emptyTitle: "No results"
    readonly property string emptySubtitle: root.query !== "" ? "Nothing matches \u201c" + root.query + "\u201d" : ""

    BarFlyout {
        parentBar: root.anchorBar
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("spotlight", "w", 560)
        cardHeight: settingsStore.flyoutSize("spotlight", "h", root.fitHeight)
        onDismissed: root.close()
        onKeyPressed: (e) => {
            const n = root.totalRows;
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (!ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                root.toggleGamesView(); e.accepted = true;
            } else if (ctrl && e.key === Qt.Key_D) {
                root.toggleHidden(root.selectedIndex); e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                root.navigateNext(); e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                root.navigatePrev(); e.accepted = true;
            } else if (e.key === Qt.Key_Down) {
                if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up) {
                root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.activate(root.selectedIndex); e.accepted = true;
            } else if (e.key === Qt.Key_Space && root.highlightedToggle()) {
                // Space flips the highlighted toggle (repeatedly — the row
                // stays put with its live pill); for anything else Space
                // falls through and types into the query.
                root.activate(root.selectedIndex); e.accepted = true;
            } else if (e.key === Qt.Key_Backspace) {
                root.query = root.query.slice(0, -1);
                root.selectedIndex = 0;
                e.accepted = true;
            } else if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32) {
                root.query += e.text;
                root.selectedIndex = 0;
                e.accepted = true;
            }
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                Text {
                    Layout.fillWidth: true
                    text: "Launcher"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    elide: Text.ElideRight
                }
                LauncherChipButton {
                    glyph: "󰊖"
                    text: "Games"
                    active: root.gamesView
                    onClicked: root.toggleGamesView()
                }
                // Hidden apps are shown again in the settings app.
                LauncherChipButton {
                    visible: settingsStore.hiddenAppCount > 0
                    glyph: "󰈉"
                    text: "Hidden \u00b7 " + settingsStore.hiddenAppCount
                    onClicked: root.openHiddenApps()
                }
            }

            LauncherSearchBar {
                Layout.fillWidth: true
                text: root.query
                glyph: "󰍉"
                placeholder: "Search apps, actions, or type = to calculate"
                countText: root.totalRows > 0 ? String(root.totalRows) : ""
                onCleared: { root.query = ""; root.selectedIndex = 0; }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: listBox.height + 2
                radius: 10 * Theme.radiusScale
                color: Theme.bg
                border.color: Theme.border
                border.width: 1
                clip: true

                Flickable {
                    id: results
                    anchors.fill: parent
                    anchors.margins: 1
                    contentWidth: width
                    contentHeight: listBox.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    ScrollBar.vertical: ThinScrollBar {}

                    NumberAnimation {
                        id: scrollAnim
                        target: results
                        property: "contentY"
                        duration: Theme.duration.normal
                        easing.type: Theme.easing.standard
                    }

                    Item {
                        id: listBox
                        readonly property int pad: Theme.spacing.md
                        width: results.width
                        height: root.totalRows === 0 ? 230 : resultsCol.implicitHeight + pad * 2

                        LauncherSelection {
                            id: selection
                            inset: listBox.pad
                            offsetY: listBox.pad
                        }

                        ColumnLayout {
                            id: resultsCol
                            x: listBox.pad
                            y: listBox.pad
                            width: parent.width - listBox.pad * 2
                            spacing: 2
                            onImplicitHeightChanged: Qt.callLater(contentCol.syncSelection)

                            SpotlightCalcRow {
                                id: calcRow
                                visible: root.hasCalc
                                expr: root.calcExpr
                                result: root.calcResult
                                highlighted: root.selectedIndex === 0
                                Layout.fillWidth: true
                                onPicked: root.activate(0)
                                onHovered: root.selectedIndex = 0
                            }

                            LauncherSectionHeader {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacing.md
                                Layout.rightMargin: Theme.spacing.md
                                Layout.topMargin: Theme.spacing.xs
                                visible: root.filtered.length > 0
                                title: root.gamesView ? "GAMES" : "APPLICATIONS"
                                count: root.filtered.length
                            }
                            Repeater {
                                id: appsRepeater
                                model: root.shownApps
                                onItemAdded: Qt.callLater(contentCol.syncSelection)
                                delegate: SpotlightAppRow {
                                    required property var modelData
                                    required property int index
                                    entry: modelData
                                    highlighted: root.selectedIndex === (index + root.appOffset)
                                    Layout.fillWidth: true
                                    onPicked: root.activate(index + root.appOffset)
                                    onHovered: root.selectedIndex = index + root.appOffset
                                }
                            }

                            LauncherSectionHeader {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacing.md
                                Layout.rightMargin: Theme.spacing.md
                                Layout.topMargin: Theme.spacing.xs
                                visible: root.matchedActions.length > 0
                                title: "SHELL"
                                count: root.matchedActions.length
                            }
                            Repeater {
                                id: actionsRepeater
                                model: root.matchedActions
                                onItemAdded: Qt.callLater(contentCol.syncSelection)
                                delegate: SpotlightActionRow {
                                    required property var modelData
                                    required property int index
                                    action: modelData
                                    highlighted: root.selectedIndex === (index + root.actionOffset)
                                    Layout.fillWidth: true
                                    onPicked: root.activate(index + root.actionOffset)
                                    onHovered: root.selectedIndex = index + root.actionOffset
                                }
                            }
                        }

                        LauncherEmptyState {
                            anchors.centerIn: parent
                            visible: root.totalRows === 0
                            glyph: "󰍉"
                            title: root.emptyTitle
                            subtitle: root.emptySubtitle
                        }
                    }
                }
            }

            LauncherFooter {
                Layout.fillWidth: true
                hints: [{ key: "\u2191\u2193", label: "navigate" }, { key: "\u21b5", label: "launch" },
                        { key: "Ctrl+D", label: "hide" }, { key: "\u2190\u2192", label: "games" }, { key: "Esc", label: "close" }]
            }

            Connections {
                target: root
                function onSelectedIndexChanged() { Qt.callLater(contentCol.syncSelection) }
            }

            // Point the selection plate at the highlighted row and keep that
            // row inside the viewport.
            function syncSelection() {
                const idx = root.selectedIndex;
                const ai = idx - root.actionOffset;
                let item = null;
                if (root.hasCalc && idx === 0) item = calcRow;
                else if (ai >= 0 && ai < root.matchedActions.length) item = actionsRepeater.itemAt(ai);
                else item = appsRepeater.itemAt(idx - root.appOffset);
                selection.target = item;
                if (!item) return;
                const top = item.y + listBox.pad;
                const bot = top + item.height;
                const pad = 8;
                const viewTop = results.contentY;
                const viewBot = viewTop + results.height;
                const maxY = Math.max(0, results.contentHeight - results.height);
                let to = viewTop;
                if (root.hasCalc && idx === 0) to = 0;
                else if (top < viewTop + pad) to = Math.max(0, top - pad - (idx === root.actionOffset || idx === root.appOffset ? 32 : 0));
                else if (bot > viewBot - pad) to = Math.min(maxY, bot - results.height + pad);
                if (to === viewTop) return;
                scrollAnim.stop();
                scrollAnim.to = to;
                scrollAnim.start();
            }
        }
    }
}
