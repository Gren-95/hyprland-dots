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
    // True when the keyboard cursor is somewhere in this section, so the
    // volume slider shows its thumb + accent as the active adjust target.
    property bool sliderActive: false
    signal deviceHovered(int idx)
    signal toggleHovered()
    spacing: Theme.spacing.sm

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
        spacing: Theme.spacing.md
        visible: !!(section.node && section.node.audio)
        VolumeSlider {
            Layout.fillWidth: true
            value: section.node && section.node.audio ? section.node.audio.volume : 0
            showThumb: section.sliderActive
            border.color: section.sliderActive ? Theme.fg : Theme.borderStrong
            border.width: section.sliderActive ? 2 : 1
            onMoved: {
                if (section.node && section.node.audio) section.node.audio.volume = value;
            }
        }
        Text {
            text: section.node && section.node.audio
                ? Math.round(section.node.audio.volume * 100) + "%" : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
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
