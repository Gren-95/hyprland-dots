// One volume line of the Sound popup: an icon (an app icon or a glyph) that
// mutes on click, a label with an optional sub-label, a slider and the level.
// Used for the output, the input and every app stream.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: line
    property string glyph: "󰕾"
    property string iconSource: ""        // app icon file (file://); the glyph shows when empty
    property string label: ""
    property string sublabel: ""
    property real volume: 0
    property bool muted: false
    property color accent: Theme.accentPrimary
    // Keyboard cursor is on this line: outline it and show the slider thumb.
    property bool highlighted: false
    signal moved(real value)
    signal muteToggled()
    signal hovered()

    implicitHeight: 54
    radius: 10 * Theme.radiusScale
    color: line.highlighted ? Theme.bgActive : (hov.hovered ? Theme.bgHover : "transparent")
    border.color: line.highlighted ? Theme.borderStrong : "transparent"
    border.width: 1
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    HoverHandler { id: hov; onHoveredChanged: if (hovered) line.hovered() }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.sm
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.md

        // Icon = mute button: the app's icon when it has one, else a glyph;
        // a muted line always shows the red muted glyph.
        Item {
            implicitWidth: 38
            implicitHeight: 38
            scale: muteMa.pressed ? 0.9 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: line.muted ? Theme.alpha(Theme.accent.red, 0.16)
                     : (muteMa.containsMouse ? Theme.bgActive : Theme.alpha(line.accent, 0.12))
                border.color: line.muted ? Theme.accent.red : Theme.alpha(line.accent, 0.45)
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
            // A plain Image on a file path: Quickshell's IconImage drew
            // nothing when its source arrived through a binding.
            Image {
                anchors.centerIn: parent
                width: 24
                height: 24
                sourceSize.width: 48
                sourceSize.height: 48
                visible: line.iconSource !== "" && !line.muted
                source: line.iconSource
                asynchronous: true
            }
            Text {
                anchors.centerIn: parent
                visible: line.iconSource === "" || line.muted
                text: line.muted ? "󰝟" : line.glyph
                color: line.muted ? Theme.accent.red : line.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
            }
            MouseArea {
                id: muteMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: line.muteToggled()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                Text {
                    text: line.label
                    textFormat: Text.PlainText   // external text: never render markup
                    color: line.muted ? Theme.mutedDeep : Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: line.width * 0.45
                }
                Text {
                    Layout.fillWidth: true
                    visible: line.sublabel !== ""
                    text: line.sublabel
                    textFormat: Text.PlainText   // external text: never render markup
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: line.sublabel === "" }
                Text {
                    text: line.muted ? "Muted" : Math.round(line.volume * 100) + "%"
                    color: line.muted ? Theme.accent.red : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: true
                }
            }
            VolumeSlider {
                Layout.fillWidth: true
                implicitHeight: 14
                value: line.volume
                accent: line.accent
                muted: line.muted
                showThumb: line.highlighted
                border.width: 0
                onMoved: line.moved(value)
            }
        }
    }
}
