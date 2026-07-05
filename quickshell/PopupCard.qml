// Top drawer: a card hanging from the bar's bottom edge — top-center by
// default, or top-right for toast-like sheets (edge: "right"). Replaces the
// old fullscreen dim-backdrop centered modal; in the unified shell nothing
// floats free of the bar. Esc closes; click-away closes via focus grab
// unless the consumer needs exclusive keyboard (polkit).
//
// Pass content via `contentComponent: Component { ... }`.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool open: false
    property int cardWidth: 640
    property int cardHeight: 480
    property string edge: "center"   // "center" | "right"
    property int topOffset: 0        // extra gap below the bar (dodge toasts)
    property bool exclusiveKeyboard: false
    property Component contentComponent: null
    signal closed()
    signal keyPressed(var event)

    // Only emit the signal — assigning `open = false` here would clobber
    // any `open: <consumerState>` binding and the drawer couldn't reopen.
    // Consumers must reset their own state in onClosed.
    function close() { root.closed(); }

    PanelWindow {
        id: win
        visible: root.open
        color: "transparent"
        anchors { top: true; right: root.edge === "right" }
        margins { top: settingsStore.barHeight + root.topOffset; right: root.edge === "right" ? 12 : 0 }
        implicitWidth: root.cardWidth
        implicitHeight: root.cardHeight
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open
            ? (root.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
            : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius.lg
            color: Theme.bgAlt
            border.color: Theme.borderStrong
            border.width: 1
            scale: root.open ? 1.0 : 0.96
            opacity: root.open ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        }

        FocusScope {
            id: focusWrap
            anchors.fill: parent
            focus: root.open
            Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; return; }
                root.keyPressed(e);
            }
            Loader {
                anchors.fill: parent
                active: root.open
                sourceComponent: root.contentComponent
            }
        }

        // Click-away close. Skipped for exclusive-keyboard consumers (auth
        // prompts must only close via explicit cancel / Esc).
        HyprlandFocusGrab {
            active: root.open && !root.exclusiveKeyboard
            windows: [win]
            onCleared: root.closed()
        }
    }
}
