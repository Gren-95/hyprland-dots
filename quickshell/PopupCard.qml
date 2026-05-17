// Centered modal overlay: full-screen dim backdrop + a centered Rectangle.
// Esc closes, click-outside closes, scale+opacity animates on open/close.
//
// Pass content via `contentComponent: Component { ... }` (not default-alias
// — that doesn't work across the per-screen Variants delegate).
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property bool open: false
    property int cardWidth: 640
    property int cardHeight: 480
    property real backdropOpacity: 0.45
    property bool exclusiveKeyboard: false
    property Component contentComponent: null
    signal closed()
    signal keyPressed(var event)

    function close() { open = false; root.closed(); }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open
                ? (root.exclusiveKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
                : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: root.backdropOpacity
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            FocusScope {
                id: focusWrap
                anchors.fill: parent
                focus: root.open
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; return; }
                    root.keyPressed(e);
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.cardWidth
                    height: root.cardHeight
                    radius: Theme.radius.lg
                    color: Theme.bgAlt
                    border.color: Theme.borderStrong
                    border.width: 1
                    scale: root.open ? 1.0 : 0.96
                    opacity: root.open ? 1.0 : 0.0
                    Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                    Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

                    Loader {
                        anchors.fill: parent
                        active: root.open
                        sourceComponent: root.contentComponent
                    }
                }
            }
        }
    }
}
