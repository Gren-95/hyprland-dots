import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

ColumnLayout {
    id: section
    property string title: ""
    property var node
    property bool isSink: true
    property int selectedIndex: -1
    property bool toggleHighlighted: false
    signal launchMixer()
    signal deviceHovered(int idx)
    signal toggleHovered()
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: section.title
            color: "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: 13
            font.bold: true
        }
        Item { Layout.fillWidth: true }
        BtToggle {
            label: section.node && section.node.audio && section.node.audio.muted ? "Muted" : "On"
            active: !!(section.node && section.node.audio && !section.node.audio.muted)
            highlighted: section.toggleHighlighted
            onClicked: {
                section.toggleHovered();
                if (section.node && section.node.audio)
                    section.node.audio.muted = !section.node.audio.muted;
            }
            HoverHandler { onHoveredChanged: if (hovered) section.toggleHovered() }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: !!(section.node && section.node.audio)
        VolumeSlider {
            Layout.fillWidth: true
            value: section.node && section.node.audio ? section.node.audio.volume : 0
            onMoved: {
                if (section.node && section.node.audio) section.node.audio.volume = value;
            }
        }
        Text {
            text: section.node && section.node.audio
                ? Math.round(section.node.audio.volume * 100) + "%" : ""
            color: "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: 11
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Repeater {
            model: {
                if (!Pipewire.nodes) return [];
                const all = Pipewire.nodes.values || [];
                return all.filter(n => n.isSink === section.isSink && !n.isStream && n.audio);
            }
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
