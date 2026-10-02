// Centered placeholder for an empty launcher list: big glyph, title, hint.
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: empty
    property string glyph: "󰍉"
    property string title: ""
    property string subtitle: ""
    spacing: Theme.spacing.md

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 64
        Layout.preferredHeight: 64
        radius: width / 2
        color: Theme.bgInset
        border.color: Theme.borderStrong
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: empty.glyph
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.hero
        }
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 360
        text: empty.title
        color: Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.lg
        font.bold: true
        elide: Text.ElideRight
    }
    Text {
        Layout.alignment: Qt.AlignHCenter
        visible: empty.subtitle !== ""
        text: empty.subtitle
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.base
    }
}
