import QtQuick
import QtQuick.Layouts

Rectangle {
    id: vrow
    property var entry
    property bool isExitNode: false
    property bool highlighted: false
    signal copied()
    signal exitToggled()
    signal hovered()
    Layout.fillWidth: true
    implicitHeight: 40
    radius: 6
    color: vrow.highlighted ? "#3b3531" : (vrowMa.containsMouse ? Theme.bgAlt : "transparent")
    border.color: vrow.isExitNode ? Theme.accent.purple : "transparent"
    border.width: vrow.isExitNode ? 1 : 0

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            Layout.alignment: Qt.AlignVCenter
            radius: 4
            color: vrow.entry && vrow.entry.online ? Theme.accent.green : Theme.disabled
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: vrow.entry ? vrow.entry.host : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: 12
                font.bold: vrow.entry && vrow.entry.online
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: vrow.entry && vrow.entry.ips.length > 0 ? vrow.entry.ips[0] : ""
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: 9
                elide: Text.ElideRight
            }
        }
        Rectangle {
            visible: vrow.entry && vrow.entry.exitNodeOption
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            radius: 11
            color: vrow.isExitNode ? Theme.accent.purple : "transparent"
            border.color: vrow.isExitNode ? Theme.accent.purple : Theme.border
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: "↗"
                color: vrow.isExitNode ? "#0a0a0a" : Theme.muted
                font.family: Theme.font
                font.pixelSize: 11
                font.bold: true
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: vrow.exitToggled()
            }
        }
        Text {
            text: "󰆏"
            color: vrowMa.containsMouse ? Theme.muted : Theme.border
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: vrowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: vrow.copied()
        onContainsMouseChanged: if (containsMouse) vrow.hovered()
    }
}
