// Quick Actions tile: glyph over label. Toggles fill with their accent while
// on and carry a state dot; one-shots stay neutral until hover/highlight. The
// keyboard-highlighted tile gets the primary-accent outline.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tile
    property var entry
    property bool isToggle: false
    property bool on: false
    property bool highlighted: false
    signal picked()
    signal hovered()
    readonly property color accent: (tile.entry && tile.entry.accent !== undefined)
        ? tile.entry.accent : Theme.fg
    readonly property bool lit: tile.highlighted || ma.containsMouse

    implicitHeight: Theme.height.tile
    radius: 10 * Theme.radiusScale
    color: tile.on
        ? Theme.alpha(accent, ma.containsMouse ? 0.24 : 0.16)
        : tile.lit ? Theme.alpha(accent, 0.10) : Theme.bgInset
    border.color: tile.highlighted ? Theme.accentPrimary
                : tile.on ? accent
                : ma.containsMouse ? Theme.alpha(accent, 0.5)
                : Theme.borderSubtle
    border.width: tile.highlighted || tile.on ? 2 : 1
    scale: ma.pressed ? 0.95 : (tile.lit ? 1.03 : 1.0)
    Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
    Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Theme.spacing.md * 2
        spacing: Theme.spacing.xs
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: tile.entry
                ? (tile.isToggle && !tile.on ? (tile.entry.offGlyph || tile.entry.glyph) : tile.entry.glyph)
                : ""
            color: tile.on || tile.lit ? tile.accent : Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xxl
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: tile.entry ? tile.entry.label : ""
            color: tile.on || tile.lit ? Theme.fg : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: tile.on || tile.highlighted
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
    }

    // State never rides on colour alone: toggles show a dot that is filled
    // while on and hollow while off.
    Rectangle {
        visible: tile.isToggle
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacing.md
        implicitWidth: 8
        implicitHeight: 8
        radius: 4
        color: tile.on ? tile.accent : "transparent"
        border.width: 1
        border.color: tile.on ? tile.accent : Theme.mutedDeep
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.picked()
        onContainsMouseChanged: if (containsMouse) tile.hovered()
    }
}
