// Bar icon for notifications. Just a clickable bell + unread badge.
// The actual notification-center panel lives in Notifications.qml; this
// component only toggles its `centerOpen` state.
import QtQuick
import QtQuick.Layouts

Item {
    id: bell
    property var parentBar
    property var notifs: null
    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 14

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            text: bell.notifs && bell.notifs.dnd ? "󰂛"
                : (bell.notifs && bell.notifs.unreadCount > 0 ? "󰂞" : "󰂚")
            color: bell.notifs && bell.notifs.dnd ? Theme.accent.orange : "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Rectangle {
            visible: bell.notifs && bell.notifs.unreadCount > 0 && !bell.notifs.dnd
            implicitWidth: cnt.implicitWidth + 8
            implicitHeight: 14
            radius: 7
            color: Theme.accent.red
            Text {
                id: cnt
                anchors.centerIn: parent
                text: bell.notifs ? String(bell.notifs.unreadCount) : "0"
                color: "#f5f5f4"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!bell.notifs) return;
            if (e.button === Qt.RightButton) bell.notifs.dnd = !bell.notifs.dnd;
            else bell.notifs.toggleCenter();
        }
    }
}
