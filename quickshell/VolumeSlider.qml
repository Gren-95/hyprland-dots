import QtQuick

Rectangle {
    id: vs
    property real value: 0
    signal moved()
    implicitHeight: 18
    radius: height / 2
    color: "#1f1c1a"
    border.color: Theme.borderStrong
    border.width: 1

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 2
        width: Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * vs.value))
        radius: height / 2
        color: Theme.accent.blue
    }

    Rectangle {
        id: thumb
        width: 22; height: 22
        radius: 11
        color: Theme.fg
        border.color: Theme.accent.blue
        border.width: 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(-width / 2 + 1,
            Math.min(parent.width - width / 2 - 1,
                (parent.width - 2) * vs.value - width / 2))
        visible: dragArea.containsMouse || dragArea.pressed
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.margins: -10
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => { vs.value = Math.max(0, Math.min(1, (e.x + anchors.margins) / vs.width)); vs.moved(); }
        onPositionChanged: (e) => {
            if (pressed) {
                vs.value = Math.max(0, Math.min(1, (e.x + anchors.margins) / vs.width));
                vs.moved();
            }
        }
    }
}
