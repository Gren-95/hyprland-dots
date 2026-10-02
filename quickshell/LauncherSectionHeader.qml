// Small caps group heading inside a launcher list, with an item-count chip.
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: head
    property string title: ""
    property int count: -1
    spacing: Theme.spacing.md
    implicitHeight: 28

    Text {
        text: head.title
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.letterSpacing: 1
        font.bold: true
    }
    Rectangle {
        visible: head.count >= 0
        implicitWidth: num.implicitWidth + 12
        implicitHeight: Theme.height.chip - 4
        radius: height / 2
        color: Theme.bgActive
        Text {
            id: num
            anchors.centerIn: parent
            text: head.count
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
            font.bold: true
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.borderSubtle
    }
}
