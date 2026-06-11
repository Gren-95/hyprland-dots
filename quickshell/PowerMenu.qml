// Power menu: Suspend / Logout / Reboot / Shutdown. (Lock is just Super+L.)
// Triggered by Super+Shift+E. Arrows or h/l navigate, Enter commits, Esc cancels.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool open: false
    property int selectedIndex: 0

    readonly property var entries: [
        { glyph: "󰒲", label: "Suspend",  accent: Theme.accent.purple, cmd: ["systemctl", "suspend"] },
        { glyph: "󰗽", label: "Logout",   accent: Theme.accent.yellow, cmd: ["hyprctl", "dispatch", "exit"] },
        { glyph: "󰜉", label: "Reboot",   accent: Theme.accent.orange, cmd: ["systemctl", "reboot"] },
        { glyph: "󰐥", label: "Shutdown", accent: Theme.accent.red,    cmd: ["systemctl", "poweroff"] },
    ]

    function toggle()  { open = !open; if (open) selectedIndex = 0; }
    function close()   { open = false; }
    function activate(i) {
        const e = entries[i];
        if (!e) return;
        runProc.command = e.cmd;
        runProc.startDetached();
        close();
    }
    function cycle(dir) {
        selectedIndex = (selectedIndex + dir + entries.length) % entries.length;
    }

    Process { id: runProc; command: [] }

    PopupCard {
        open: root.open
        cardWidth: 480
        cardHeight: 180
        backdropOpacity: 0.55
        onClosed: root.close()
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                root.cycle(1); e.accepted = true;
            } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                root.cycle(-1); e.accepted = true;
            } else if (e.key === Qt.Key_Tab) {
                root.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                root.activate(root.selectedIndex); e.accepted = true;
            }
        }
        contentComponent: Component {
            Item {
                RowLayout {
                    anchors.centerIn: parent
                    spacing: Theme.spacing.md
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
        implicitHeight: 100
        radius: 10
        color: tile.highlighted ? Qt.rgba(tile.entry.accent.r, tile.entry.accent.g, tile.entry.accent.b, 0.12)
                                : Theme.bgHover
        border.color: tile.highlighted ? tile.entry.accent : Theme.borderSubtle
        border.width: 1
        scale: tileMa.pressed ? 0.94 : (tile.highlighted ? 1.05 : 1.0)
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacing.sm
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.entry ? tile.entry.glyph : ""
                color: tile.entry ? tile.entry.accent : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.entry ? tile.entry.label : ""
                color: tile.highlighted ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: tile.highlighted
            }
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
            onContainsMouseChanged: if (containsMouse) tile.hovered()
        }
    }
}
