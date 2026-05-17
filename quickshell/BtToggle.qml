import QtQuick

Rectangle {
    id: tg
    property string label: ""
    property bool active: false
    property bool highlighted: false
    signal clicked()
    implicitWidth: lbl.implicitWidth + 16
    implicitHeight: Theme.height.chip
    radius: 11
    color: tg.active ? "#1d4ed8" : Theme.bgAlt
    border.color: tg.highlighted ? Theme.fg : (tg.active ? Theme.accent.blue : Theme.borderStrong)
    border.width: tg.highlighted ? 2 : 1
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
    Text {
        id: lbl
        anchors.centerIn: parent
        text: tg.label
        color: "#f5f5f4"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.bold: tg.active
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.clicked()
    }
}
