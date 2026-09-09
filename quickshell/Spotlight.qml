import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

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
            setDefaultProc.command = ["bash", Quickshell.env("HOME")
                + "/.config/scripts/default-app.sh", "set", root.pickRole, item.id];
            setDefaultProc.startDetached();
            close();
            return;
        }
        if (item) item.execute();
        close();
    }

    Process { id: copyProc; command: [] }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("spotlight", "w", 560)
        cardHeight: settingsStore.flyoutSize("spotlight", "h", 560)
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
        Item {
                id: contentRoot
                anchors.fill: parent
                ColumnLayout {
                    id: headerCol
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: Theme.spacing.lg
                    spacing: Theme.spacing.md

                    Text {
                        Layout.fillWidth: true
                        text: root.manageHidden ? "Hidden apps"
                            : root.pickRole === "" ? "Launcher" : "Default " + root.pickLabel
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.lg
                        Text {
                            text: "󰍉"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.hero
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.query || (root.manageHidden
                            ? (settingsStore.hiddenAppCount > 0 ? "Pick one to show again"
                                                                : "Nothing hidden")
                            : root.pickRole === "" ? "Spotlight Search"
                            : "Pick a " + root.pickLabel)
                            color: root.query ? Theme.fg : Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xxl
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                }

                Text {
                    id: hintFooter
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                    text: root.manageHidden
                        ? "↵ show again · ←/→ back to all · Esc close"
                        : root.pickRole === ""
                        ? "↑/↓ navigate · ↵ launch · Ctrl+D hide · ←/→ hidden · Esc close"
                        : "↵ set as default " + root.pickLabel + " · Esc back"
                    color: Theme.disabled
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    horizontalAlignment: Text.AlignHCenter
                }

                Flickable {
                    id: results
                    anchors {
                        top: headerCol.bottom
                        left: parent.left
                        right: parent.right
                        bottom: hintFooter.top
                        topMargin: 6
                        leftMargin: 8
                        rightMargin: 8
                        bottomMargin: 6
                    }
                    contentHeight: resultsCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: resultsCol
                        width: parent.width
                        spacing: 2

                        CalcRow {
                            visible: root.hasCalc
                            expr: root.calcExpr
                            result: root.calcResult
                            highlighted: root.selectedIndex === 0
                            Layout.fillWidth: true
                            onPicked: root.activate(0)
                            onHovered: root.selectedIndex = 0
                        }

                        Text {
                            Layout.leftMargin: 6
                            Layout.topMargin: 4
                            visible: root.matchedActions.length > 0
                            text: "SHELL"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        Repeater {
                            id: actionsRepeater
                            model: root.matchedActions
                            delegate: ActionRow {
                                required property var modelData
                                required property int index
                                action: modelData
                                highlighted: root.selectedIndex === (index + root.calcOffset)
                                Layout.fillWidth: true
                                onPicked: root.activate(index + root.calcOffset)
                                onHovered: root.selectedIndex = index + root.calcOffset
                            }
                        }

                        Text {
                            Layout.leftMargin: 6
                            Layout.topMargin: 4
                            visible: root.filtered.length > 0
                            text: "APPLICATIONS"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }

                        Repeater {
                            id: appsRepeater
                            model: root.filtered.slice(0, settingsStore.spotlightCap)
                            delegate: SpotlightRow {
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
                }

                // Keep the highlighted row in view as arrows move selection.
                Connections {
                    target: root
                    function onSelectedIndexChanged() { Qt.callLater(contentRoot.ensureVisible) }
                }
                function ensureVisible() {
                    const idx = root.selectedIndex;
                    // Calc row sits at the very top; pin to start.
                    if (root.hasCalc && idx === 0) {
                        results.contentY = 0;
                        return;
                    }
                    const ai = idx - root.calcOffset;
                    const item = ai < root.matchedActions.length
                        ? actionsRepeater.itemAt(ai)
                        : appsRepeater.itemAt(idx - root.appOffset);
                    if (!item) return;
                    const top = item.y;
                    const bot = top + item.height;
                    const viewTop = results.contentY;
                    const viewBot = viewTop + results.height;
                    const pad = 8;
                    if (top < viewTop + pad) {
                        results.contentY = Math.max(0, top - pad);
                    } else if (bot > viewBot - pad) {
                        results.contentY = Math.min(
                            Math.max(0, results.contentHeight - results.height),
                            bot - results.height + pad
                        );
                    }
                }
        }
    }

    // Shell action result row: tinted glyph square, name, live state pill.
    component ActionRow: Rectangle {
        id: arow
        property var action
        property bool highlighted: false
        signal picked()
        signal hovered()
        readonly property bool on: arow.action && arow.action.isToggle ? arow.action.state() : false
        readonly property color accent: arow.action ? arow.action.accent : Theme.accentPrimary
        implicitHeight: 52
        radius: 8 * Theme.radiusScale
        color: arow.highlighted ? Theme.bgActive : (aHover.containsMouse ? Theme.bgHover : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.lg
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 8 * Theme.radiusScale
                color: Qt.rgba(arow.accent.r, arow.accent.g, arow.accent.b, arow.on ? 0.25 : 0.12)
                Text {
                    anchors.centerIn: parent
                    text: arow.action ? arow.action.glyph : ""
                    color: arow.on || arow.highlighted ? arow.accent : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                }
            }
            Text {
                Layout.fillWidth: true
                text: arow.action ? arow.action.name : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                font.bold: arow.highlighted
                elide: Text.ElideRight
            }
            Rectangle {
                visible: arow.action && arow.action.isToggle
                implicitWidth: stateLbl.implicitWidth + 14
                implicitHeight: 20
                radius: 10 * Theme.radiusScale
                color: arow.on ? Qt.rgba(arow.accent.r, arow.accent.g, arow.accent.b, 0.2) : "transparent"
                border.color: arow.on ? arow.accent : Theme.borderStrong
                border.width: 1
                Text {
                    id: stateLbl
                    anchors.centerIn: parent
                    text: arow.on ? "on" : "off"
                    color: arow.on ? arow.accent : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.bold: true
                }
            }
            Text {
                visible: arow.action && !arow.action.isToggle
                text: "↵ open"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
            }
        }
        MouseArea {
            id: aHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arow.picked()
            onContainsMouseChanged: if (containsMouse) arow.hovered()
        }
    }

    component CalcRow: Rectangle {
        id: crow
        property string expr: ""
        property string result: ""
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 60
        radius: 8 * Theme.radiusScale
        color: crow.highlighted ? Theme.bgActive : (cHover.containsMouse ? Theme.bgHover : "transparent")
        border.color: Theme.accentPrimary
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: Theme.spacing.lg
            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 6 * Theme.radiusScale
                color: Theme.accent.blueDeep
                Text {
                    anchors.centerIn: parent
                    text: "="
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                    font.bold: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: crow.result
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: crow.expr + " ="
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Text {
                text: "↵ Copy"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
        }
        MouseArea {
            id: cHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: crow.picked()
            onContainsMouseChanged: if (containsMouse) crow.hovered()
        }
    }

    component SpotlightRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 52
        radius: 8 * Theme.radiusScale
        color: row.highlighted ? Theme.bgActive : (hover.containsMouse ? Theme.bgHover : "transparent")
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.lg
            IconImage {
                implicitSize: 36
                source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: row.entry ? row.entry.name : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: row.highlighted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    visible: row.entry && row.entry.comment
                    text: row.entry ? row.entry.comment : ""
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
            Text {
                visible: row.highlighted
                text: "↵"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.picked()
            onContainsMouseChanged: if (containsMouse) row.hovered()
        }
    }
}
