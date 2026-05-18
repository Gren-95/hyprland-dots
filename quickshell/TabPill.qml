// Tab pill used in the Bluetooth/Wi-Fi tab strip.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: tp
    property string glyph: ""
    property string label: ""
    property bool active: false
    property color accent: Theme.accentPrimary
    signal picked()
    radius: 13
    color: tp.active
        ? Qt.rgba(tp.accent.r, tp.accent.g, tp.accent.b, 0.20)
        : (tpMa.containsMouse ? "#262220" : "transparent")
    border.color: tp.active ? tp.accent : "transparent"
    border.width: tp.active ? 1 : 0
    Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
    Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

    RowLayout {
        anchors.centerIn: parent
        spacing: Theme.spacing.sm
        Text {
            text: tp.glyph
            color: tp.active ? tp.accent : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            text: tp.label
            color: tp.active ? Theme.fg : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: tp.active
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
