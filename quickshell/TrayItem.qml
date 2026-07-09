import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: tray
    property SystemTrayItem item
    property var anchorWindow: null
    // Watched by the overflow chevron so its flyout pins itself while a
    // tray context menu (a separate window) is open — otherwise the focus
    // grab would dismiss the flyout and destroy the menu under the cursor.
    readonly property bool menuOpen: menuAnchor.visible
    Layout.fillHeight: true
    implicitWidth: 28

    scale: hoverArea.pressed ? 0.88 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 4 * Theme.radiusScale
        color: hoverArea.containsMouse ? Theme.bgAlt : "transparent"
        opacity: tray.item && tray.item.status === Status.Passive ? 0.5 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }

    IconImage {
        id: trayIcon
        anchors.centerIn: parent
        implicitSize: 18
        source: tray.item ? tray.item.icon : ""
        asynchronous: true
        layer.enabled: true
        layer.effect: MultiEffect {
            brightness: 0.6
            saturation: -0.6
        }
    }

    QsMenuAnchor {
        id: menuAnchor
        // Anchor against whichever window actually hosts this item (bar OR
        // a flyout) — a mismatched window/item pair positions the menu in
        // the wrong coordinate space.
        anchor.window: tray.QsWindow.window
        anchor.item: tray
        anchor.edges: Edges.Bottom
        menu: tray.item ? tray.item.menu : null
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: (e) => {
            if (!tray.item) return;
            if (e.button === Qt.LeftButton) {
                if (tray.item.onlyMenu) menuAnchor.open();
                else tray.item.activate();
            } else if (e.button === Qt.MiddleButton) {
                tray.item.secondaryActivate();
            } else if (e.button === Qt.RightButton) {
                if (tray.item.hasMenu) menuAnchor.open();
            }
        }
        onWheel: (e) => {
            if (!tray.item) return;
            if (e.angleDelta.y !== 0) tray.item.scroll(e.angleDelta.y, false);
            if (e.angleDelta.x !== 0) tray.item.scroll(e.angleDelta.x, true);
        }
    }
}
