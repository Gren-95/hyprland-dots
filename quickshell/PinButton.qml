import QtQuick

Rectangle {
    id: root
    property bool pinned: false
    signal toggled()
    implicitWidth: 22
    implicitHeight: 22
    radius: 4
    color: ma.containsMouse ? "#292524" : "transparent"
    Text {
        anchors.centerIn: parent
        rotation: root.pinned ? 0 : -35
        text: "󰐃"
        color: root.pinned ? "#3b82f6" : "#78716c"
        font.family: "FiraCode Nerd Font"
        font.pixelSize: 13
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
