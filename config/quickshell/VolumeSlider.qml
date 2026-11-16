import QtQuick

Rectangle {
    id: vs
    property real value: 0
    // Force the thumb + accent to show even without a pointer — used to mark
    // the slider as the active keyboard target.
    property bool showThumb: false
    // Fill colour; a muted slider draws its fill grey instead.
    property color accent: Theme.accentPrimary
    property bool muted: false
    readonly property color _fill: vs.muted ? Theme.disabled : vs.accent
    signal moved()
    implicitHeight: 18
    radius: height / 2
    color: Theme.bgInset
    border.color: Theme.borderStrong
    border.width: 1
    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

    Rectangle {
        id: fill
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 2
        width: Math.max(0, Math.min(parent.width - 4, (parent.width - 4) * vs.value))
        radius: height / 2
        color: vs._fill
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        // Glide for external changes (keys/OSD); stay 1:1 with the finger
        // while dragging so the fill never lags the cursor.
        Behavior on width {
            enabled: !dragArea.pressed
            NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard }
        }
    }

    Rectangle {
        id: thumb
        width: 22; height: 22
        radius: 11 * Theme.radiusScale
        color: Theme.fg
        border.color: vs._fill
        border.width: 2
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(-width / 2 + 1,
            Math.min(parent.width - width / 2 - 1,
                (parent.width - 2) * vs.value - width / 2))
        // Fade + scale in on hover (or when keyboard-active) instead of
        // popping into existence; dip on press.
        opacity: (dragArea.containsMouse || dragArea.pressed || vs.showThumb) ? 1.0 : 0.0
        scale: dragArea.pressed ? 0.88 : ((dragArea.containsMouse || vs.showThumb) ? 1.0 : 0.7)
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
        Behavior on scale   { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        Behavior on x {
            enabled: !dragArea.pressed
            NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.margins: -10
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: (e) => { vs.value = Math.max(0, Math.min(settingsStore.maxVolume / 100, (e.x + anchors.margins) / vs.width)); vs.moved(); }
        onPositionChanged: (e) => {
            if (pressed) {
                vs.value = Math.max(0, Math.min(settingsStore.maxVolume / 100, (e.x + anchors.margins) / vs.width));
                vs.moved();
            }
        }
    }
}
