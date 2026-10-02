import QtQuick

// Hover surface behind a bar button: shows the touch area so every target
// reads the same. Parent it to the button and bind `hovered`.
Rectangle {
    property bool hovered: false
    anchors.fill: parent
    anchors.topMargin: 2
    anchors.bottomMargin: 2
    radius: Theme.radius.sm
    color: hovered ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
}
