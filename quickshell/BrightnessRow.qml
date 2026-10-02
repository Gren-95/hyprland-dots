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
        font.pixelSize: Theme.fontSize.xl
        Layout.preferredWidth: 24
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        text: br.label
        color: br.highlighted ? Theme.fg : Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.base
        font.bold: br.highlighted
        Layout.preferredWidth: 80
    }
    VolumeSlider {
        Layout.fillWidth: true
        implicitHeight: 24
        value: br.value
        showThumb: br.highlighted
        border.color: br.highlighted ? Theme.fg : Theme.borderStrong
        border.width: br.highlighted ? 2 : 1
        onMoved: br.moved(value)
        HoverHandler { onHoveredChanged: if (hovered) br.hovered() }
    }
    Text {
        text: Math.round(br.value * 100) + "%"
        color: br.highlighted ? Theme.fg : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.base
        font.bold: br.highlighted
        Layout.preferredWidth: 46
        horizontalAlignment: Text.AlignRight
    }
}
