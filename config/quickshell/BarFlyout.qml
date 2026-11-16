// Bar flyout: the shell's popup surface, centred on the screen of the bar
// that opened it.
//
// Content goes inside the BarFlyout {} braces directly — it lands inside
// the inner FocusScope via the default-property alias. The FocusScope owns
// keyboard focus; handle keys via `onKeyPressed` (unaccepted Escape closes by
// default).
//
// Flyouts used to be able to hang under their bar icon with a tail; every one
// was centred, so that positioning code was removed. Modules still remember
// which icon opened them, for the bar highlight, not for placement.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: card
    property var parentBar
    property bool open: false
    property int cardWidth: 380
    property int cardHeight: 460
    property bool pinned: false
    property color fillColor: Theme.bgAlt
    property color borderColor: Theme.popupBorder
    default property alias contentData: contentScope.data
    signal dismissed()
    signal keyPressed(var event)

    function close() { if (card.open) card.dismissed(); }

    anchor.window: card.parentBar
    anchor.rect.x: card.parentBar ? (card.parentBar.width - implicitWidth) / 2 : 0
    anchor.rect.y: card.parentBar && card.parentBar.screen ? (card.parentBar.screen.height - implicitHeight) / 2 : 0
    implicitWidth: cardWidth
    implicitHeight: cardHeight
    visible: card.open
    color: "transparent"

    onOpenChanged: open ? popupManager.opened(card) : popupManager.closed(card)

    // When the popup maps (e.g. opened by a click on the bar icon), the inner
    // FocusScope's `focus: true` claims focus within its scope but doesn't
    // always become the window's *active* focus item, so key events never
    // arrive. Force it once the surface is up so keyboard nav works regardless
    // of how the popup was opened.
    onVisibleChanged: if (visible) Qt.callLater(contentScope.forceActiveFocus)

    SproutBg {
        id: bg
        anchors.fill: parent
        fillColor: card.fillColor
        borderColor: card.borderColor
        showTail: false
        scale: card.open ? 1.0 : 0.94
        opacity: card.open ? 1.0 : 0.0
        transformOrigin: Item.Center
        Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    FocusScope {
        id: contentScope
        anchors.fill: parent
        focus: card.open
        scale: card.open ? 1.0 : 0.94
        opacity: card.open ? 1.0 : 0.0
        transformOrigin: Item.Center
        Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Keys.onPressed: (e) => {
            card.keyPressed(e);
            if (!e.accepted && e.key === Qt.Key_Escape) {
                card.close();
                e.accepted = true;
            }
        }
    }

    HyprlandFocusGrab {
        active: card.open && !card.pinned
        windows: [card]
        // Don't assign to card.open here — it would break the consumer's
        // `open: <state>` binding, leaving the popup permanently unable to
        // reopen. Let the consumer reset its own state via onDismissed.
        onCleared: card.dismissed()
    }
}
