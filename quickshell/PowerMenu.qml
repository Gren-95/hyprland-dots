// Centered modal power menu: Lock / Suspend / Logout / Reboot / Shutdown.
// Triggered by Super+Shift+E.  Arrow/h-l/Tab/digits 1-5 navigate, Enter or
// click commits, Esc cancels.  Destructive actions are visually offset.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool open: false
    property int selectedIndex: 0
    property string hostname: ""
    property string uptime: ""

    // Five power actions. `destructive: true` shifts the tile into the warn
    // colour group and adds a visual divider before it.
    readonly property var entries: [
        { glyph: "󰌾", label: "Lock",     hint: "Lock screen",            accent: Theme.accent.blue, cmd: ["loginctl", "lock-session"],          destructive: false },
        { glyph: "󰒲", label: "Suspend",  hint: "Sleep to RAM",            accent: Theme.accent.purple, cmd: ["systemctl", "suspend"],              destructive: false },
        { glyph: "󰗽", label: "Logout",   hint: "End Hyprland session",    accent: Theme.accent.yellow, cmd: ["hyprctl", "dispatch", "exit"],       destructive: false },
        { glyph: "󰜉", label: "Reboot",   hint: "Restart the system",      accent: Theme.accent.orange, cmd: ["systemctl", "reboot"],                destructive: true  },
        { glyph: "󰐥", label: "Shutdown", hint: "Power off",               accent: Theme.accent.red, cmd: ["systemctl", "poweroff"],              destructive: true  },
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
    function cycle(dir) {
        const n = entries.length;
        selectedIndex = (selectedIndex + dir + n) % n;
    }

    Process { id: runProc; command: [] }
    Process {
        id: statProc
        running: false
        command: ["sh", "-c", "echo \"$(hostname)\"$'\\t'\"$(uptime -p)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("\t");
                root.hostname = (parts[0] || "").trim();
                root.uptime = (parts[1] || "").trim();
            }
        }
    }

    PopupCard {
        open: root.open
        cardWidth: 720
        cardHeight: 340
        backdropOpacity: 0.55
        onClosed: root.close()
        onKeyPressed: (e) => {
            const n = root.entries.length;
            if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                root.cycle(1); e.accepted = true;
            } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                root.cycle(-1); e.accepted = true;
            } else if (e.key === Qt.Key_Tab) {
                root.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
            } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_5) {
                root.selectedIndex = e.key - Qt.Key_1; e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                root.activate(root.selectedIndex); e.accepted = true;
            }
        }
        contentComponent: Component {
            Item {
                ColumnLayout {
                    id: cardCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 28
                    }
                    spacing: 22

                    // Header
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacing.xs
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Power"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xl
                            font.bold: true
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.hostname && root.uptime
                                ? root.hostname + "  ·  " + root.uptime
                                : (root.hostname || " ")
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "ACTIONS"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.letterSpacing: 1
                        font.bold: true
                    }

                    // Tiles
                    RowLayout {
                        id: tilesRow
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -8
                        spacing: Theme.spacing.md
                        Repeater {
                            model: root.entries
                            delegate: PowerTile {
                                required property var modelData
                                required property int index
                                entry: modelData
                                indexLabel: index + 1
                                highlighted: root.selectedIndex === index
                                // Add a visual divider before the first destructive tile.
                                showSeparator: modelData.destructive
                                    && (index > 0 && !root.entries[index - 1].destructive)
                                onPicked: root.activate(index)
                                onHovered: root.selectedIndex = index
                            }
                        }
                    }

                    // Footer: hint for the currently focused tile
                    Text {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter
                        text: root.entries[root.selectedIndex]
                            ? root.entries[root.selectedIndex].hint
                            : ""
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "1-5 jump  ·  ←/→ navigate  ·  Enter confirm  ·  Esc cancel"
                        color: Theme.disabled
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                    }
                }
            }
        }
    }

    component PowerTile: Item {
        id: tileWrap
        property var entry
        property bool highlighted: false
        property bool showSeparator: false
        property int indexLabel: 0
        signal picked()
        signal hovered()
        implicitWidth: tile.implicitWidth + (showSeparator ? 24 : 0)
        implicitHeight: tile.implicitHeight

        // Divider between safe and destructive groups
        Rectangle {
            visible: tileWrap.showSeparator
            anchors {
                left: parent.left
                leftMargin: 11
                verticalCenter: parent.verticalCenter
            }
            width: 1
            height: tile.height - 24
            color: Theme.border
        }

        Rectangle {
            id: tile
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            implicitWidth: 108
            implicitHeight: 124
            radius: 14
            color: tileWrap.highlighted ? "#262220" : Theme.bgHover
            border.color: tileWrap.highlighted
                ? (tileWrap.entry ? tileWrap.entry.accent : Theme.fg)
                : Theme.border
            border.width: tileWrap.highlighted ? 2 : 1
            scale: tileWrap.highlighted ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.spacing.md
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: tileWrap.entry ? tileWrap.entry.glyph : ""
                    color: tileWrap.entry ? tileWrap.entry.accent : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.huge
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: tileWrap.entry ? tileWrap.entry.label : ""
                    color: tileWrap.highlighted ? Theme.fg : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: tileWrap.highlighted
                }
            }

            // Number badge top-left
            Rectangle {
                anchors { top: parent.top; left: parent.left; margins: 8 }
                implicitWidth: 18
                implicitHeight: 18
                radius: 9
                color: tileWrap.highlighted
                    ? (tileWrap.entry ? tileWrap.entry.accent : Theme.fg)
                    : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: tileWrap.indexLabel
                    color: tileWrap.highlighted ? "#0a0a0a" : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.bold: true
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tileWrap.picked()
                onContainsMouseChanged: if (containsMouse) tileWrap.hovered()
            }
        }
    }
}
