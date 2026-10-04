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
    property var anchorItem: null
    signal navigateNext()
    signal navigatePrev()

    // Shell command palette: wired from shell.qml ({name, glyph, accent,
    // keywords, isToggle, state()?, run()}). Toggles flip in place with
    // live state; everything else runs/opens and the launcher closes
    // (flyout-openers close it via the single-open policy anyway).
    property var shellActions: []

    // ===== Default-app picking =====
    // A second mode for the same list: instead of launching the highlighted
    // app, assign it to a role. Roles the desktop has no standard for
    // (terminal, editor) are why default-app.sh exists at all — see it for
    // where each choice is written.
    property string pickRole: ""
    readonly property var pickRoles: ({
        browser:     { label: "browser",      category: "WebBrowser" },
        terminal:    { label: "terminal",     category: "TerminalEmulator" },
        editor:      { label: "editor",       category: "TextEditor" },
        filemanager: { label: "file manager", category: "FileManager" }
    })
    readonly property string pickLabel: pickRole !== "" ? pickRoles[pickRole].label : ""
    function startPick(role) {
        root.pickRole = role;
        root.query = "";
        root.selectedIndex = 0;
        root.open = true;
    }
    function cancelPick() {
        root.pickRole = "";
        root.query = "";
        root.selectedIndex = 0;
    }

    // ===== Hiding apps =====
    // Ctrl+D drops the highlighted app from the list (Ctrl+H is already the
    // flyout ring's vim-left); "Hidden apps" in the
    // palette opens the same list showing only what is hidden, where Enter
    // puts one back. The list stays open either way — hiding a run of
    // entries should not mean reopening the launcher between each one.
    property bool manageHidden: false
    // Left/Right flip between the two lists. The query survives the flip, so
    // it reads as one list with a filter on it rather than two places to be.
    function toggleHiddenView() {
        if (root.pickRole !== "") return;      // the default-app picker owns its list
        root.manageHidden = !root.manageHidden;
        root.selectedIndex = 0;
    }
    function manageHiddenApps() {
        root.manageHidden = true;
        root.pickRole = "";
        root.query = "";
        root.selectedIndex = 0;
        root.open = true;
    }
    function toggleHidden(i) {
        const item = root.filtered[i - root.appOffset];
        if (!item || !item.id) return;
        settingsStore.setAppHidden(item.id, !settingsStore.isAppHidden(item.id));
        // The row under the cursor just left the list; keep the index in range.
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.totalRows - 1));
    }
    Process { id: setDefaultProc; command: [] }

    readonly property var matchedActions: {
        const q = root.query.trim().toLowerCase();
        // Picking a default, or editing what is hidden, is a list of apps
        // and nothing else.
        if (root.pickRole !== "" || root.manageHidden || !q) return [];
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
    readonly property bool hasCalc: root.pickRole === "" && !root.manageHidden
        && root.calcResult !== ""

    readonly property var filtered: {
        if (!DesktopEntries.applications) return [];
        const all = DesktopEntries.applications.values || [];
        const q = root.query.toLowerCase();
        const cat = root.pickRole !== "" ? root.pickRoles[root.pickRole].category : "";
        return all
            .filter(a => !a.noDisplay)
            // Managing shows exactly the hidden ones; every other mode shows
            // exactly the rest.
            .filter(a => settingsStore.isAppHidden(a.id) === root.manageHidden)
            .filter(a => cat === "" || (a.categories || []).indexOf(cat) >= 0)
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

    readonly property int calcOffset: hasCalc ? 1 : 0
    readonly property int appOffset: calcOffset + matchedActions.length
    readonly property int totalRows: appOffset + filtered.length

    function toggle() {
        open = !open;
        if (open) { query = ""; selectedIndex = 0; }
    }
    function openAt(idx) {
        if (!open) { open = true; query = ""; }
        selectedIndex = idx < 0 ? Math.max(0, root.totalRows - 1)
                                : Math.min(idx, Math.max(0, root.totalRows - 1));
    }
    function close() { open = false; pickRole = ""; manageHidden = false; }
    // The highlighted shell-toggle action, if any (drives Space-to-toggle).
    function highlightedToggle() {
        const ai = selectedIndex - calcOffset;
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
        const ai = i - calcOffset;
        if (ai >= 0 && ai < matchedActions.length) {
            const a = matchedActions[ai];
            a.run();
            // An action that put us into pick mode wants the launcher to stay
            // up — the list it just narrowed is the point.
            if (!a.isToggle && root.pickRole === "" && !root.manageHidden) close();
            return;
        }
        const item = filtered[i - appOffset];
        if (item && root.manageHidden) {
            settingsStore.setAppHidden(item.id, false);
            root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.totalRows - 1));
            return;                            // stay in the list
        }
        if (item && root.pickRole !== "") {
            setDefaultProc.command = ["bash", Paths.scripts + "/default-app.sh", "set", root.pickRole, item.id];
            setDefaultProc.startDetached();
            close();
            return;
        }
        if (item) item.execute();
        close();
    }

    Process { id: copyProc; command: [] }

    // Popup height follows the list (up to what the screen allows), so there
    // is no dead space under the last row; the footer stays pinned below it.
    readonly property real fitHeight: Math.max(340, Math.min(
        anchorBar && anchorBar.screen ? Math.min(anchorBar.screen.height - 160, 680) : 600,
        contentCol.implicitHeight))

    readonly property string emptyTitle: {
        if (root.manageHidden) return settingsStore.hiddenAppCount > 0 ? "No hidden apps match" : "Nothing hidden";
        if (root.pickRole !== "") return "No " + root.pickLabel + " apps found";
        return "No results";
    }
    readonly property string emptySubtitle: {
        if (root.manageHidden && settingsStore.hiddenAppCount === 0) return "Ctrl+D hides an app from the launcher";
        return root.query !== "" ? "Nothing matches \u201c" + root.query + "\u201d" : "";
    }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("spotlight", "w", 560)
        cardHeight: settingsStore.flyoutSize("spotlight", "h", root.fitHeight)
        onDismissed: root.open = false
        onKeyPressed: (e) => {
            const n = root.totalRows;
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (e.key === Qt.Key_Escape && (root.pickRole !== "" || root.manageHidden)) {
                root.manageHidden = false;
                root.cancelPick(); e.accepted = true;
            } else if (!ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                root.toggleHiddenView(); e.accepted = true;
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
                    text: root.manageHidden ? "Hidden apps"
                        : root.pickRole === "" ? "Launcher" : "Default " + root.pickLabel
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    elide: Text.ElideRight
                }
                LauncherChipButton {
                    visible: root.pickRole === ""
                    glyph: root.manageHidden ? "󰁍" : "󰈉"
                    text: root.manageHidden ? "Back to apps"
                        : settingsStore.hiddenAppCount > 0 ? "Hidden \u00b7 " + settingsStore.hiddenAppCount : "Hidden"
                    active: root.manageHidden
                    onClicked: root.toggleHiddenView()
                }
                LauncherChipButton {
                    visible: root.pickRole !== ""
                    glyph: "󰁍"
                    text: "Cancel"
                    onClicked: root.cancelPick()
                }
            }

            LauncherSearchBar {
                Layout.fillWidth: true
                text: root.query
                glyph: root.manageHidden ? "󰈉" : "󰍉"
                placeholder: root.manageHidden
                    ? (settingsStore.hiddenAppCount > 0 ? "Pick one to show again" : "Nothing hidden")
                    : root.pickRole === "" ? "Search apps, actions, or type = to calculate"
                    : "Pick a " + root.pickLabel
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
                                    highlighted: root.selectedIndex === (index + root.calcOffset)
                                    Layout.fillWidth: true
                                    onPicked: root.activate(index + root.calcOffset)
                                    onHovered: root.selectedIndex = index + root.calcOffset
                                }
                            }

                            LauncherSectionHeader {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacing.md
                                Layout.rightMargin: Theme.spacing.md
                                Layout.topMargin: Theme.spacing.xs
                                visible: root.filtered.length > 0
                                title: root.manageHidden ? "HIDDEN APPS" : "APPLICATIONS"
                                count: root.filtered.length
                            }
                            Repeater {
                                id: appsRepeater
                                model: root.filtered.slice(0, settingsStore.spotlightCap)
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
                        }

                        LauncherEmptyState {
                            anchors.centerIn: parent
                            visible: root.totalRows === 0
                            glyph: root.manageHidden ? "󰈉" : "󰍉"
                            title: root.emptyTitle
                            subtitle: root.emptySubtitle
                        }
                    }
                }
            }

            LauncherFooter {
                Layout.fillWidth: true
                hints: root.manageHidden
                    ? [{ key: "\u21b5", label: "show again" }, { key: "\u2190\u2192", label: "back to all" }, { key: "Esc", label: "close" }]
                    : root.pickRole === ""
                    ? [{ key: "\u2191\u2193", label: "navigate" }, { key: "\u21b5", label: "launch" },
                       { key: "Ctrl+D", label: "hide" }, { key: "\u2190\u2192", label: "hidden" }, { key: "Esc", label: "close" }]
                    : [{ key: "\u21b5", label: "set as default " + root.pickLabel }, { key: "Esc", label: "back" }]
            }

            Connections {
                target: root
                function onSelectedIndexChanged() { Qt.callLater(contentCol.syncSelection) }
            }

            // Point the selection plate at the highlighted row and keep that
            // row inside the viewport.
            function syncSelection() {
                const idx = root.selectedIndex;
                const ai = idx - root.calcOffset;
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
                else if (top < viewTop + pad) to = Math.max(0, top - pad - (ai === 0 || idx === root.appOffset ? 32 : 0));
                else if (bot > viewBot - pad) to = Math.min(maxY, bot - results.height + pad);
                if (to === viewTop) return;
                scrollAnim.stop();
                scrollAnim.to = to;
                scrollAnim.start();
            }
        }
    }
}
