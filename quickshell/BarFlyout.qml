// Bar-anchored flyout. Hangs directly under a bar item (icon) with the
// SproutBg tail pointing up at it, growing downward out of the bar —
// Windows-tray-flyout style. Successor to BarPopupCard (which centered
// itself on screen).
//
// Content goes inside the BarFlyout {} braces directly — it lands inside
// the inner FocusScope via the default-property alias, below the tail.
// The FocusScope owns keyboard focus; handle keys via `onKeyPressed`
// (unaccepted Escape closes by default).
//
// Positioning is computed manually into anchor.rect (top-left semantics):
// centered under `anchorItem`, clamped to the screen edges, with the tail
// tracking the icon so edge-clamped flyouts still point at their opener.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: card
    property var parentBar
    // Bar item the flyout hangs from. Falls back to bar-center when unset.
    property Item anchorItem: null
    property bool open: false
    property int cardWidth: 380
    property int cardHeight: 460
    property bool pinned: false
    property color fillColor: Theme.bgAlt
    property color borderColor: Theme.popupBorder
    // Gap kept between the flyout body and the screen's side edges.
    readonly property int edgeMargin: 8
    default property alias contentData: contentScope.data
    signal dismissed()
    signal keyPressed(var event)

    function close() { if (card.open) card.dismissed(); }

    // Icon center in bar-window coordinates. The extra `_reposition` term
    // only exists to create reactive dependencies (layout shifts, tray items
    // appearing) — mapToItem alone doesn't re-evaluate when ancestors move.
    readonly property real _reposition: (card.anchorItem ? card.anchorItem.x + card.anchorItem.width : 0)
        + (card.parentBar ? card.parentBar.width : 0) + (card.open ? 1 : 0)
    readonly property real _iconCenterX: {
        const dep = card._reposition;
        if (!card.anchorItem || !card.parentBar)
            return card.parentBar ? card.parentBar.width / 2 : 0;
        return card.anchorItem.mapToItem(null, card.anchorItem.width / 2, 0).x + dep * 0;
    }
    readonly property real _clampedX: Math.max(
        card.edgeMargin,
        Math.min((card.parentBar ? card.parentBar.width : 0) - implicitWidth - card.edgeMargin,
                 card._iconCenterX - implicitWidth / 2))

    anchor.window: card.parentBar
    anchor.rect.x: card._clampedX
    anchor.rect.y: card.parentBar ? card.parentBar.height : 0
    implicitWidth: cardWidth
    implicitHeight: cardHeight + bg.tailHeight
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
        showTail: true
        // Tail points at the icon even when the body is edge-clamped.
        tailX: card._iconCenterX - card._clampedX
        scale: card.open ? 1.0 : 0.94
        opacity: card.open ? 1.0 : 0.0
        transformOrigin: Item.Top
        Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    FocusScope {
        id: contentScope
        anchors.fill: parent
        anchors.topMargin: bg.tailHeight
        focus: card.open
        scale: card.open ? 1.0 : 0.94
        opacity: card.open ? 1.0 : 0.0
        transformOrigin: Item.Top
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
