import QtQuick
import QtQuick.Layouts

RowLayout {
    id: br
    property string glyph: ""
    property string label: ""
    property real value: 0
    property bool highlighted: false
    signal moved(real v)
    signal hovered()
    spacing: Theme.spacing.md
    Text {
        text: br.glyph
        color: br.highlighted ? Theme.fg : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.lg
        Layout.preferredWidth: 20
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        text: br.label
        color: br.highlighted ? Theme.fg : Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.bold: br.highlighted
        Layout.preferredWidth: 70
    }
    VolumeSlider {
        Layout.fillWidth: true
        value: br.value
        border.color: br.highlighted ? Theme.fg : Theme.borderStrong
        border.width: br.highlighted ? 2 : 1
        onMoved: br.moved(value)
        HoverHandler { onHoveredChanged: if (hovered) br.hovered() }
    }
    Text {
        text: Math.round(br.value * 100) + "%"
        color: br.highlighted ? Theme.fg : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.bold: br.highlighted
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
    }
}
