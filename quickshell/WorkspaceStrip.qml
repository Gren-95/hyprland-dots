// Workspace pill row for the bar. Pass `glyphFn` to map workspace id to
// the icon string (defaults to the id itself).
import QtQuick
import QtQuick.Layouts
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
        delegate: Text {
            id: wsLabel
            required property var modelData
            text: strip.glyphFn(modelData.id)
            color: modelData.active ? "#f5f5f4"
                 : (wsMa.containsMouse ? Theme.muted : Theme.mutedDeep)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            // Active workspace pops; press dips for a tactile tap.
            scale: wsMa.pressed ? 0.8 : (modelData.active ? 1.18 : 1.0)
            Behavior on color { ColorAnimation  { duration: Theme.duration.normal } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
            MouseArea {
                id: wsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + modelData.id)
                onWheel: (e) => Hyprland.dispatch(
                    "workspace " + (e.angleDelta.y > 0 ? "e+1" : "e-1"))
            }
        }
    }
}
