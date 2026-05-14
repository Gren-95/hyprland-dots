// Centered power menu: Lock / Suspend / Logout / Reboot / Shutdown.
// Esc closes, ←/→ + h/l navigate, Enter confirms.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool open: false
    property int selectedIndex: 0
    property string uptime: ""
    property string hostname: ""

    readonly property var entries: [
        { glyph: "󰌾", label: "Lock",     accent: "#3b82f6", cmd: ["loginctl", "lock-session"] },
        { glyph: "󰒲", label: "Suspend",  accent: "#a78bfa", cmd: ["systemctl", "suspend"] },
        { glyph: "󰗽", label: "Logout",   accent: "#eab308", cmd: ["hyprctl", "dispatch", "exit"] },
        { glyph: "󰜉", label: "Reboot",   accent: "#f97316", cmd: ["systemctl", "reboot"] },
        { glyph: "󰐥", label: "Shutdown", accent: "#ef4444", cmd: ["systemctl", "poweroff"] },
    ]

    function toggle() {
        if (open) close();
        else openMenu();
    }
    function openMenu() {
        selectedIndex = 0;
        open = true;
        statProc.running = true;
    }
    function close() { open = false; }
    function activate(i) {
        const e = entries[i];
        if (!e) return;
        runProc.command = e.cmd;
        runProc.startDetached();
        close();
    }

    Process { id: runProc; command: [] }
    Process {
        id: statProc
        running: false
        command: ["sh", "-c", "echo \"$(hostname) | $(uptime -p)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root.hostname = (parts[0] || "").trim();
                root.uptime = (parts[1] || "").trim();
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.5
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: tilesRow.implicitWidth + 56
                height: header.implicitHeight + tilesRow.implicitHeight + 56
                radius: 16
                color: "#292524"
                border.color: "#78716c"
                border.width: 1
                focus: root.open

                Keys.onPressed: (e) => {
                    const n = root.entries.length;
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        root.selectedIndex = (root.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        root.selectedIndex = (root.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab) {
                        const dir = e.modifiers & Qt.ShiftModifier ? -1 : 1;
                        root.selectedIndex = (root.selectedIndex + dir + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex); e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: 18
                    spacing: 4
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Power"
                        color: "#fafaf9"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.hostname && root.uptime
                            ? root.hostname + "  •  " + root.uptime
                            : (root.hostname || "")
                        color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                    }
                }

                RowLayout {
                    id: tilesRow
                    anchors {
                        top: header.bottom
                        topMargin: 16
                        horizontalCenter: parent.horizontalCenter
                    }
                    spacing: 10
                    Repeater {
                        model: root.entries
                        delegate: PowerTile {
                            required property var modelData
                            required property int index
                            entry: modelData
                            highlighted: root.selectedIndex === index
                            onPicked: root.activate(index)
                            onHovered: root.selectedIndex = index
                        }
                    }
                }
            }
        }
    }

    component PowerTile: Rectangle {
        id: tile
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitWidth: 96
        implicitHeight: 96
        radius: 12
        color: tile.highlighted ? "#3b3531" : (mouse.containsMouse ? "#262220" : "#1c1917")
        border.color: tile.highlighted ? (tile.entry ? tile.entry.accent : "#fafaf9") : "#3a3633"
        border.width: tile.highlighted ? 2 : 1

        scale: tile.highlighted ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.entry ? tile.entry.glyph : ""
                color: tile.entry ? tile.entry.accent : "#fafaf9"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 32
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.entry ? tile.entry.label : ""
                color: "#e7e5e4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                font.bold: tile.highlighted
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
            onContainsMouseChanged: if (containsMouse) tile.hovered()
        }
    }
}
