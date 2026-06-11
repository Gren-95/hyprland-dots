import QtQuick
import QtQuick.Layouts

Rectangle {
    id: arow
    property var node
    property bool isActive: false
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: Theme.height.control
    radius: Theme.radius.sm
    color: arow.highlighted ? Theme.bgActive
         : arow.isActive ? Theme.bgHover
         : (rowMa.containsMouse ? Theme.bgAlt : "transparent")
    scale: rowMa.pressed ? 0.985 : 1.0
    Behavior on color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Animated selection / active accent rail.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 10
        radius: 1.5
        color: "#60a5fa"
        opacity: arow.isActive ? 1.0 : (arow.highlighted ? 0.7 : (rowMa.containsMouse ? 0.35 : 0.0))
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 8
        spacing: Theme.spacing.sm
        Text {
            text: arow.isActive ? "●" : "○"
            color: arow.isActive ? "#60a5fa" : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: arow.node ? (arow.node.nickname || arow.node.description || arow.node.name || "") : ""
            color: arow.isActive ? Theme.fg : Theme.fgMuted
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
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
