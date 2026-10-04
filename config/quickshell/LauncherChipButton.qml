// Pill button used in launcher headers (hidden-apps toggle, cancel, delete all).
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: chip
    property string text: ""
    property string glyph: ""
    property bool danger: false
    property bool active: false
    signal clicked()

    implicitHeight: 34
    implicitWidth: label.implicitWidth + Theme.spacing.xl * 2
    radius: height / 2
    color: ma.containsMouse
        ? (danger ? Theme.accent.redDeep : Theme.bgActive)
        : (active ? Theme.alpha(Theme.accentPrimary, 0.16) : Theme.bgInset)
    border.color: danger ? Theme.accent.redDeep : (active ? Theme.accentPrimary : Theme.borderStrong)
    border.width: 1
    scale: ma.pressed ? 0.95 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    Text {
        id: label
        anchors.centerIn: parent
        text: (chip.glyph !== "" ? chip.glyph + "  " : "") + chip.text
        color: chip.danger ? (ma.containsMouse ? Theme.fg : Theme.accent.redSoft)
            : (chip.active ? Theme.accentPrimary : Theme.fgMuted)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.base
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.clicked()
    }
}
