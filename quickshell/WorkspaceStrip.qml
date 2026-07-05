// Workspace pill row for the bar. Pass `glyphFn` to map workspace id to
// the icon string (defaults to the id itself).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland

RowLayout {
    id: strip
    spacing: Theme.spacing.md
    property var glyphFn: (id) => "" + id
    property var parentBar: null

    HoverHandler { id: wsHover }
    BarTooltip {
        bar: strip.parentBar
        target: strip
        text: "Workspaces · Super+1–9"
        active: wsHover.hovered
    }

    Repeater {
        model: Hyprland.workspaces
        delegate: Item {
            id: pill
            required property var modelData
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight

            RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 3

            Text {
                text: strip.glyphFn(pill.modelData.id)
                color: pill.modelData.active ? "#f5f5f4"
                     : (wsMa.containsMouse ? Theme.muted : Theme.mutedDeep)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                // Active workspace pops; press dips for a tactile tap.
                scale: wsMa.pressed ? 0.8 : (pill.modelData.active ? 1.18 : 1.0)
                Behavior on color { ColorAnimation  { duration: Theme.duration.normal } }
                Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
            }

            // Tiny app icons for windows on this workspace (optional).
            Repeater {
                model: settingsStore.workspaceWindowIcons ? pill.modelData.toplevels : null
                delegate: IconImage {
                    required property var modelData
                    required property int index
                    visible: index < 3   // cap per pill
                    implicitSize: 12
                    opacity: pill.modelData.active ? 1.0 : 0.55
                    asynchronous: true
                    source: {
                        const cls = (modelData.lastIpcObject && modelData.lastIpcObject.class)
                            ? modelData.lastIpcObject.class : "";
                        return cls ? Quickshell.iconPath(cls.toLowerCase(), "application-x-executable") : "";
                    }
                }
            }

            }

            MouseArea {
                id: wsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + pill.modelData.id)
                onWheel: (e) => Hyprland.dispatch(
                    "workspace " + (e.angleDelta.y > 0 ? "e+1" : "e-1"))
            }
        }
    }
}
