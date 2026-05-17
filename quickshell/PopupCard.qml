// Centered modal overlay: full-screen dim backdrop + a centered Rectangle.
// Esc closes, click-outside closes, opacity/scale animates on open/close.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

Scope {
    id: root
    property bool open: false
    default property alias content: contentSlot.data
    property int cardWidth: 640
    property int cardHeight: 480
    property real backdropOpacity: 0.45
    property bool exclusiveKeyboard: false   // Polkit wants this; most don't
    signal closed()

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
                anchors.fill: parent
                focus: root.open
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.cardWidth
                    height: root.cardHeight
                    radius: 14
                    color: Theme.bgAlt
                    border.color: Theme.borderStrong
                    border.width: 1
                    scale: root.open ? 1.0 : 0.96
                    opacity: root.open ? 1.0 : 0.0
                    Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                    Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

                    Item {
                        id: contentSlot
                        anchors.fill: parent
                    }
                }
            }
        }
    }
}
