// Windows-style hidden-tray chevron. Sits before the tray and hosts ONLY
// tray apps placed in "overflow" — tucked bar modules render as tiles in
// the Quick Actions grid instead. Only visible when something is tucked.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: chev
    property var parentBar
    property bool popupOpen: false
    // Tray context menus are separate windows; while any is open the flyout
    // pins itself so the focus grab doesn't dismiss it mid-use.
    property int menusOpen: 0

    readonly property var overflowTray: {
        const list = (SystemTray.items && SystemTray.items.values) || [];
        return list.filter(t => settingsStore.trayPlacementOf(t.id || t.title) === "overflow");
    }

    visible: overflowTray.length > 0
    onVisibleChanged: if (!visible) popupOpen = false

    Layout.fillHeight: true
    implicitWidth: visible ? 24 : 0

    Text {
        anchors.centerIn: parent
        text: "󰅃"
        color: chev.popupOpen ? Theme.accentPrimary : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.lg
        rotation: chev.popupOpen ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    HoverHandler { id: chevHover }
    BarTooltip {
        bar: chev.parentBar
        target: chev
        text: "Hidden tray apps"
        active: chevHover.hovered && !chev.popupOpen
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chev.popupOpen = !chev.popupOpen
    }

    BarFlyout {
        parentBar: chev.parentBar
        anchorItem: chev
        open: chev.popupOpen
        pinned: chev.menusOpen > 0
        cardWidth: Math.max(120, Math.min(300, chev.overflowTray.length * 36 + 40))
        cardHeight: trayRow.implicitHeight + 2 * Theme.spacing.lg
        onDismissed: chev.popupOpen = false

        RowLayout {
            id: trayRow
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.sm
            Repeater {
                model: chev.overflowTray
                delegate: TrayItem {
                    required property var modelData
                    item: modelData
                    anchorWindow: chev.parentBar
                    implicitHeight: 28
                    onMenuOpenChanged: chev.menusOpen += menuOpen ? 1 : -1
                }
            }
            Item { Layout.fillWidth: true }
        }
    }
}
