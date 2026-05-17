// Bar-anchored centered modal. Wraps PopupWindow + SproutBg + an animated
// FocusScope so each bar popup doesn't repeat the same boilerplate.
//
// Content goes inside the BarPopupCard {} braces directly — it lands inside
// the inner FocusScope via the default-property alias. The FocusScope owns
// keyboard focus, so use `onKeyPressed` to handle keys (BarPopupCard re-emits
// the FocusScope's Keys.onPressed via the `keyPressed` signal).
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: card
    property var parentBar
    property bool open: false
    property int cardWidth: 360
    property int cardHeight: 460
    property bool pinned: false
    property color borderColor: Theme.mutedDeep
    default property alias contentData: contentScope.data
    signal dismissed()
    signal keyPressed(var event)

    anchor.window: card.parentBar
    anchor.rect.x: card.parentBar ? (card.parentBar.width - implicitWidth) / 2 : 0
    anchor.rect.y: card.parentBar && card.parentBar.screen
        ? (card.parentBar.screen.height - implicitHeight) / 2 : 0
    implicitWidth: cardWidth
    implicitHeight: cardHeight
    visible: card.open
    color: "transparent"

    SproutBg {
        anchors.fill: parent
        fillColor: Theme.bgAlt
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
        Keys.onPressed: (e) => card.keyPressed(e)
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
