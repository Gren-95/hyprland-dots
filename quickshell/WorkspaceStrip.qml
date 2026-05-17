// Workspace pill row for the bar. Pass `glyphFn` to map workspace id to
// the icon string (defaults to the id itself).
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

RowLayout {
    id: strip
    spacing: Theme.spacing.md
    property var glyphFn: (id) => "" + id

    Repeater {
        model: Hyprland.workspaces
        delegate: Text {
            required property var modelData
            text: strip.glyphFn(modelData.id)
            color: modelData.active ? "#f5f5f4" : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + modelData.id)
                onWheel: (e) => Hyprland.dispatch(
                    "workspace " + (e.angleDelta.y > 0 ? "e+1" : "e-1"))
            }
        }
    }
}
