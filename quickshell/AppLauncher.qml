import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property bool pinned: false
    property string query: ""
    property int selectedIndex: 0
    property var anchorBar: null
    property var anchorItem: null
    signal navigateNext()
    signal navigatePrev()

    readonly property string calcExpr: {
        const q = root.query.trim();
        if (q.startsWith("=")) return q.slice(1).trim();
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
    readonly property int calcOffset: hasCalc ? 1 : 0
    readonly property int totalRows: calcOffset + filtered.length

    readonly property var filtered: {
        if (!DesktopEntries.applications) return [];
        const all = DesktopEntries.applications.values || [];
        const q = root.query.toLowerCase();
        return all
            .filter(a => !a.noDisplay)
            .filter(a => {
                if (!q) return true;
                const name = (a.name || "").toLowerCase();
                const gen = (a.genericName || "").toLowerCase();
                const cmt = (a.comment || "").toLowerCase();
                return name.includes(q) || gen.includes(q) || cmt.includes(q);
            })
            .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    }

    function toggle() {
        open = !open;
        if (open) { query = ""; selectedIndex = 0; }
    }
    function close() { open = false; }
    function openAt(_idx) {
        open = true;
        query = ""; selectedIndex = 0;
    }
    function activate(i) {
        if (hasCalc && i === 0) {
            copyProc.command = ["wl-copy", root.calcResult];
            copyProc.startDetached();
            close();
            return;
        }
        const item = filtered[i - calcOffset];
        if (item) item.execute();
        close();
    }

    Process { id: copyProc; command: [] }

    PopupWindow {
        id: popup
        visible: root.open && root.anchorBar !== null
        color: "transparent"
        anchor.window: root.anchorBar
        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        implicitWidth: 420
        implicitHeight: 520

        SproutBg { anchors.fill: parent; fillColor: "#292524"; borderColor: "#78716c"; tailX: width / 2 }
        Item {
            anchors.fill: parent
            focus: root.open
            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                const n = root.filtered.length;
                if (e.key === Qt.Key_Escape) {
                    root.close(); e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    root.navigateNext(); e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    root.navigatePrev(); e.accepted = true;
                } else if (e.key === Qt.Key_Down) {
                    const total = root.totalRows;
                    if (total > 0) root.selectedIndex = Math.min(total - 1, root.selectedIndex + 1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Up) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
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
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PinButton {
                        pinned: root.pinned
                        onToggled: root.pinned = !root.pinned
                    }
                    Text {
                        text: "󰍉"
                        color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 16
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.query || "Search apps…"
                        color: root.query ? "#f5f5f4" : "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }
                    Text {
                        text: root.filtered.length
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 11
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#44403c" }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: appsCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: appsCol
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

                        Repeater {
                            model: root.filtered.slice(0, 80)
                            delegate: AppLauncherRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                highlighted: root.selectedIndex === (index + root.calcOffset)
                                Layout.fillWidth: true
                                onPicked: root.activate(index + root.calcOffset)
                                onHovered: root.selectedIndex = index + root.calcOffset
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: root.open && !root.pinned
        windows: [popup]
        onCleared: root.close()
    }

    component CalcRow: Rectangle {
        id: crow
        property string expr: ""
        property string result: ""
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 48
        radius: 6
        color: crow.highlighted ? "#3b3531" : (cHover.containsMouse ? "#262220" : "transparent")
        border.color: "#3b82f6"
        border.width: 1
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                radius: 5
                color: "#1d4ed8"
                Text { anchors.centerIn: parent; text: "="; color: "#fafaf9"
                    font.family: "FiraCode Nerd Font"; font.pixelSize: 15; font.bold: true }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text { text: crow.result; color: "#fafaf9"
                    font.family: "FiraCode Nerd Font"; font.pixelSize: 14; font.bold: true
                    elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: crow.expr + " ="; color: "#a8a29e"
                    font.family: "FiraCode Nerd Font"; font.pixelSize: 10
                    elide: Text.ElideRight; Layout.fillWidth: true }
            }
            Text { text: "↵ copy"; color: "#78716c"
                font.family: "FiraCode Nerd Font"; font.pixelSize: 10 }
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

    component AppLauncherRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 40
        radius: 6
        color: row.highlighted ? "#3b3531" : (hover.containsMouse ? "#262220" : "transparent")
        border.color: row.highlighted ? "#78716c" : "transparent"
        border.width: row.highlighted ? 1 : 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            IconImage {
                implicitSize: 26
                source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: row.entry ? row.entry.name : ""
                    color: "#f5f5f4"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    font.bold: row.highlighted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    visible: row.entry && row.entry.comment
                    text: row.entry ? row.entry.comment : ""
                    color: "#78716c"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
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
