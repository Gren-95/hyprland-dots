import QtQuick

Rectangle {
    id: root
    property bool pinned: false
    signal toggled()
    implicitWidth: 22
    implicitHeight: 22
    radius: 4 * Theme.radiusScale
    color: ma.containsMouse ? Theme.bgAlt : "transparent"
    scale: ma.pressed ? 0.85 : 1.0
    Behavior on color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
    Text {
        anchors.centerIn: parent
        // Tack tilts upright when pinned; eased so the flip reads as motion.
        rotation: root.pinned ? 0 : -35
        text: "󰐃"
        color: root.pinned ? Theme.accent.blue : "#78716c"
        font.family: Theme.font
        font.pixelSize: 13
        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
        Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
