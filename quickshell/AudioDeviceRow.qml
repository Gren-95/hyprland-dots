import QtQuick
import QtQuick.Layouts

Rectangle {
    id: arow
    property var node
    property bool isActive: false
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: 26
    radius: 4
    color: arow.highlighted ? "#3b3531"
         : arow.isActive ? Theme.bgHover
         : (rowMa.containsMouse ? Theme.bgAlt : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 6
        Text {
            text: arow.isActive ? "●" : "○"
            color: arow.isActive ? "#60a5fa" : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: 11
        }
        Text {
            Layout.fillWidth: true
            text: arow.node ? (arow.node.nickname || arow.node.description || arow.node.name || "") : ""
            color: "#f5f5f4"
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 11
            font.bold: arow.isActive
        }
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: arow.picked()
        onContainsMouseChanged: if (containsMouse) arow.hovered()
    }
}
