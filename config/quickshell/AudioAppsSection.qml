// The per-app mixer card of the Sound popup: one row per playback stream, so a
// single app (a browser tab, a game) can be turned down without touching the
// master volume. Hidden while nothing is playing.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

Rectangle {
    id: section

    // Application playback streams only: devices are not streams, and capture
    // streams are not sinks.
    readonly property var streams: {
        if (!Pipewire.nodes) return [];
        return (Pipewire.nodes.values || []).filter(n => n.isStream && n.isSink && n.audio);
    }

    visible: streams.length > 0
    implicitHeight: col.implicitHeight + Theme.spacing.xl * 2
    radius: 10 * Theme.radiusScale
    color: Theme.bg
    border.color: Theme.border
    border.width: 1
    clip: true

    // Without a tracker a stream's volume and mute state are not bound.
    PwObjectTracker { objects: section.streams }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.sm

        Text {
            text: "APPS"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            font.letterSpacing: 1
            font.bold: true
        }
        Repeater {
            model: section.streams
            delegate: AudioAppRow {
                required property var modelData
                node: modelData
                Layout.fillWidth: true
            }
        }
    }
}
