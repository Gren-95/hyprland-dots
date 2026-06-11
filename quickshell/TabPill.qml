// Tab pill used in the Bluetooth/Wi-Fi/VPN tab strip. The active background is
// drawn by TabStrip's sliding indicator; this pill only owns its glyph/label
// (colour-eased on activation) plus hover tint and a press-scale tap.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tp
    property string glyph: ""
    property string label: ""
    property bool active: false
    property color accent: Theme.accent.blue
    signal picked()
    radius: 13
    color: (!tp.active && tpMa.containsMouse) ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
    scale: tpMa.pressed ? 0.94 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.centerIn: parent
        spacing: Theme.spacing.sm
        Text {
            text: tp.glyph
            color: tp.active ? tp.accent : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
        }
        Text {
            text: tp.label
            color: tp.active ? Theme.fg : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: tp.active
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
        }
    }
    MouseArea {
        id: tpMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tp.picked()
    }
}
