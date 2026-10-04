import QtQuick

// Hover surface behind a bar button: shows the touch area so every target
// reads the same. Parent it to the button and bind `hovered`; bind `active`
// to the open state of the widget the button toggles.
Rectangle {
    property bool hovered: false
    // Held on while the button's widget is open, so the surface stays lit
    // until the widget is dismissed.
    property bool active: false
    anchors.fill: parent
    anchors.topMargin: 2
    anchors.bottomMargin: 2
    radius: Theme.radius.sm
    color: hovered || active ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
}
