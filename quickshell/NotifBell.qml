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
    scale: bellMa.pressed ? 0.88 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Anchor the notification-center flyout to this bell (also covers the
    // Super+N global shortcut, which only calls toggleCenter()). Live
    // binding: when the bell is hidden via placement, fall back to
    // bar-center instead of anchoring to an invisible item.
    Component.onCompleted: {
        if (bell.notifs) {
            bell.notifs.anchorBar = bell.parentBar;
            bell.notifs.anchorItem = Qt.binding(() => bell.visible ? bell : null);
        }
    }

    // Ring the bell whenever the unread count climbs.
    property int _lastCount: 0
    Connections {
        target: bell.notifs
        function onUnreadCountChanged() {
            if (bell.notifs && bell.notifs.unreadCount > bell._lastCount && !bell.notifs.dnd)
                ringAnim.restart();
            bell._lastCount = bell.notifs ? bell.notifs.unreadCount : 0;
        }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            id: bellGlyph
            text: bell.notifs && bell.notifs.dnd ? "󰂛"
                : (bell.notifs && bell.notifs.unreadCount > 0 ? "󰂞" : "󰂚")
            color: bell.notifs && bell.notifs.dnd ? Theme.accent.orange : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            transformOrigin: Item.Top
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

            SequentialAnimation {
                id: ringAnim
                NumberAnimation { target: bellGlyph; property: "rotation"; to:  16; duration: 70 }
                NumberAnimation { target: bellGlyph; property: "rotation"; to: -13; duration: 110 }
                NumberAnimation { target: bellGlyph; property: "rotation"; to:   9; duration: 100 }
                NumberAnimation { target: bellGlyph; property: "rotation"; to:   0; duration: 90; easing.type: Theme.easing.standard }
            }
        }
        Rectangle {
            id: badge
            visible: bell.notifs && bell.notifs.unreadCount > 0 && !bell.notifs.dnd
            implicitWidth: cnt.implicitWidth + 8
            implicitHeight: 14
            radius: 7 * Theme.radiusScale
            color: Theme.accent.red
            // Pop in on appearance.
            scale: visible ? 1.0 : 0.0
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
            Text {
                id: cnt
                anchors.centerIn: parent
                text: bell.notifs ? String(bell.notifs.unreadCount) : "0"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: true
            }
        }
    }

    HoverHandler { id: bellHover }
    BarTooltip {
        bar: bell.parentBar
        target: bell
        text: "Notifications · Super+N"
        active: bellHover.hovered
    }

    MouseArea {
        id: bellMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!bell.notifs) return;
            if (e.button === Qt.RightButton) bell.notifs.dnd = !bell.notifs.dnd;
            else bell.notifs.toggleCenter();
        }
    }
}
