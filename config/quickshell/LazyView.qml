// Builds its content only while it is needed. Wrap a modal's window (the
// Variants / BarFlyout / PanelWindow) in a LazyView and bind `shown` to the
// modal's open state: the item tree, bindings and models exist from the first
// open until `linger` ms after it closes (long enough for the fade-out), and
// are freed again afterwards. State other code reads (the open flag, models,
// query text, anchors) belongs outside the LazyView, in the modal's own Scope.
import QtQuick
import Quickshell

Scope {
    id: root

    property bool shown: false
    property int linger: 600

    default property alias content: loader.component

    LazyLoader {
        id: loader
        active: root.shown || lingerTimer.running
    }
    Timer { id: lingerTimer; interval: root.linger }
    onShownChanged: if (!shown) lingerTimer.restart()
}
