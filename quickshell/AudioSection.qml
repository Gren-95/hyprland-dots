// One audio endpoint (output or input) as a card: title and a device
// dropdown header, a mute button with the volume slider, and a device list
// that only reveals when the dropdown is opened.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

Rectangle {
    id: section
    property string title: ""
    property var node
    property bool isSink: true
    property int selectedIndex: -1
    property bool toggleHighlighted: false
    // True when the keyboard cursor is somewhere in this section, so the
    // volume slider shows its thumb + accent as the active adjust target.
    property bool sliderActive: false
    // Whether the device list is revealed. Owned by the parent so the
    // keyboard handler can flip it too.
    property bool expanded: false
    signal deviceHovered(int idx)
    signal toggleHovered()
    signal expandToggled()

    readonly property var devices: {
        if (!Pipewire.nodes) return [];
        const all = Pipewire.nodes.values || [];
        return all.filter(n => n.isSink === section.isSink && !n.isStream && n.audio);
    }
    readonly property bool muted: !!(node && node.audio && node.audio.muted)
    readonly property real volume: node && node.audio ? node.audio.volume : 0
    readonly property string deviceName: node ? (node.nickname || node.description || node.name || "") : "No device"
    readonly property string glyph: {
        if (!isSink) return muted ? "󰍭" : "󰍬";
        if (muted) return "󰖁";
        return volume < 0.34 ? "󰕿" : volume < 0.67 ? "󰖀" : "󰕾";
    }

    implicitHeight: col.implicitHeight + Theme.spacing.lg * 2
    radius: 10 * Theme.radiusScale
    color: Theme.bg
    border.color: sliderActive ? Theme.borderStrong : Theme.border
    border.width: 1
    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
    clip: true

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.lg
        spacing: Theme.spacing.md

        // ----- Title + device dropdown header -----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            Text {
                text: section.title
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.letterSpacing: 1
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                id: dd
                Layout.maximumWidth: 230
                implicitHeight: Theme.height.control
                implicitWidth: ddRow.implicitWidth + 18
                radius: height / 2
                color: ddMa.containsMouse || section.expanded ? Theme.bgActive : Theme.bgInset
                border.color: section.expanded ? Theme.accentPrimary : Theme.borderStrong
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                scale: ddMa.pressed ? 0.96 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                RowLayout {
                    id: ddRow
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, dd.Layout.maximumWidth - 18)
                    spacing: Theme.spacing.sm
                    Text {
                        Layout.fillWidth: true
                        text: section.deviceName
                        color: Theme.fg
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                    }
                    Text {
                        text: "󰅀"
                        color: section.expanded ? Theme.accentPrimary : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        rotation: section.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    }
                }
                MouseArea {
                    id: ddMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: section.expandToggled()
                }
            }
        }

        // ----- Mute button + volume slider -----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            visible: !!(section.node && section.node.audio)

            Rectangle {
                implicitWidth: 40
                implicitHeight: 40
                radius: 10 * Theme.radiusScale
                color: muteMa.containsMouse ? Theme.bgActive : Theme.bgInset
                border.color: section.toggleHighlighted ? Theme.fg : (section.muted ? Theme.accent.red : Theme.borderStrong)
                border.width: section.toggleHighlighted ? 2 : 1
                scale: muteMa.pressed ? 0.9 : 1.0
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                Text {
                    anchors.centerIn: parent
                    text: section.glyph
                    color: section.muted ? Theme.accent.red : (section.isSink ? Theme.fg : Theme.accent.orange)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                }
                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        section.toggleHovered();
                        if (section.node && section.node.audio)
                            section.node.audio.muted = !section.node.audio.muted;
                    }
                    onContainsMouseChanged: if (containsMouse) section.toggleHovered()
                }
            }

            VolumeSlider {
                Layout.fillWidth: true
                value: section.volume
                showThumb: section.sliderActive
                opacity: section.muted ? 0.45 : 1.0
                border.color: section.sliderActive ? Theme.fg : Theme.borderStrong
                border.width: section.sliderActive ? 2 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
                onMoved: {
                    if (section.node && section.node.audio) section.node.audio.volume = value;
                }
            }
            Text {
                text: Math.round(section.volume * 100) + "%"
                color: section.muted ? Theme.mutedDeep : Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: true
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
            }
        }

        // ----- Device list: revealed by the dropdown -----
        Item {
            id: reveal
            Layout.fillWidth: true
            Layout.preferredHeight: section.expanded ? list.implicitHeight : 0
            clip: true
            opacity: section.expanded ? 1.0 : 0.0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }

            ColumnLayout {
                id: list
                width: parent.width
                spacing: 2
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong; Layout.bottomMargin: 4 }
                Repeater {
                    model: section.devices
                    delegate: AudioDeviceRow {
                        required property var modelData
                        required property int index
                        node: modelData
                        isActive: section.node === modelData
                        highlighted: section.selectedIndex === index
                        Layout.fillWidth: true
                        onPicked: {
                            if (section.isSink) Pipewire.preferredDefaultAudioSink = modelData;
                            else Pipewire.preferredDefaultAudioSource = modelData;
                        }
                        onHovered: section.deviceHovered(index)
                    }
                }
            }
        }
    }
}
