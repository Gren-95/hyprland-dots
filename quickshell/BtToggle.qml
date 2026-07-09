import QtQuick

Rectangle {
    id: tg
    property string label: ""
    property bool active: false
    property bool highlighted: false
    signal clicked()
    implicitWidth: lbl.implicitWidth + 18
    implicitHeight: Theme.height.chip
    radius: 11 * Theme.radiusScale
    color: tg.active ? "#1d4ed8" : Theme.bgAlt
    border.color: tg.highlighted ? Theme.fg : (tg.active ? Theme.accent.blue : Theme.borderStrong)
    border.width: tg.highlighted ? 2 : 1
    scale: tgMa.pressed ? 0.92 : 1.0
    Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on border.width { NumberAnimation { duration: Theme.duration.fast } }
    Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
    Text {
        id: lbl
        anchors.centerIn: parent
        text: tg.label
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.bold: tg.active
    }
    MouseArea {
        id: tgMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.clicked()
    }
}
