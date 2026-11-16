// One playback stream (an app) in the Sound popup: a mute button, the app name
// with the stream's title, and a volume slider.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

Rectangle {
    id: row
    property var node

    readonly property bool muted: !!(node && node.audio && node.audio.muted)
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property var props: node && node.properties ? node.properties : ({})
    readonly property string appName: props["application.name"] || node.nickname || node.name || "Unknown"
    // The title of what is playing (a tab, a track), when it differs from the app.
    readonly property string streamTitle: {
        const t = props["media.name"] || "";
        return t === appName ? "" : t;
    }
    readonly property string glyph: {
        if (muted) return "󰖁";
        return volume < 0.34 ? "󰕿" : volume < 0.67 ? "󰖀" : "󰕾";
    }

    implicitHeight: 62
    radius: Theme.radius.sm
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        spacing: Theme.spacing.md

        Rectangle {
            implicitWidth: 40
            implicitHeight: 40
            radius: 10 * Theme.radiusScale
            color: muteMa.containsMouse ? Theme.bgActive : Theme.bgInset
            border.color: row.muted ? Theme.accent.red : Theme.borderStrong
            border.width: 1
            scale: muteMa.pressed ? 0.9 : 1.0
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Text {
                anchors.centerIn: parent
                text: row.glyph
                color: row.muted ? Theme.accent.red : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
            }
            MouseArea {
                id: muteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (row.node && row.node.audio) row.node.audio.muted = !row.node.audio.muted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                Text {
                    text: row.appName
                    color: row.muted ? Theme.mutedDeep : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: row.width * 0.3
                }
                Text {
                    Layout.fillWidth: true
                    visible: row.streamTitle !== ""
                    text: row.streamTitle
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
            }
            VolumeSlider {
                Layout.fillWidth: true
                implicitHeight: 20
                value: row.volume
                opacity: row.muted ? 0.45 : 1.0
                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
                onMoved: if (row.node && row.node.audio) row.node.audio.volume = value
            }
        }

        Text {
            text: Math.round(row.volume * 100) + "%"
            color: row.muted ? Theme.mutedDeep : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            font.bold: true
            Layout.preferredWidth: 50
            horizontalAlignment: Text.AlignRight
        }
    }
}
