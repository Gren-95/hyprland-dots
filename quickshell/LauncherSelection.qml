// Animated selection highlight shared by the launcher lists: a bgActive plate
// with an accent rail that glides to whichever row `target` points at.
// Parent it to the list's content item (same coordinate space as the rows).
import QtQuick

Rectangle {
    id: sel
    property Item target: null
    property real inset: 0
    property real offsetY: 0

    visible: target !== null
    x: inset
    width: parent ? parent.width - inset * 2 : 0
    y: target ? target.y + offsetY : 0
    height: target ? target.height : 0
    radius: 8 * Theme.radiusScale
    color: Theme.bgActive
    Behavior on y { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    Behavior on height { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 16
        radius: 1.5 * Theme.radiusScale
        color: Theme.accentPrimary
    }
}
