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
    spacing: 10
    Text {
        text: br.glyph
        color: br.highlighted ? Theme.fg : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: 16
        Layout.preferredWidth: 20
        horizontalAlignment: Text.AlignHCenter
    }
    Text {
        text: br.label
        color: br.highlighted ? Theme.fg : Theme.muted
        font.family: Theme.font
        font.pixelSize: 11
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
        font.pixelSize: 11
        font.bold: br.highlighted
        Layout.preferredWidth: 38
        horizontalAlignment: Text.AlignRight
    }
}
