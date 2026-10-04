// A titled card of the day panel: the shared surface (Theme.bg, 1px border,
// rounded) with the small-caps section label on top. Content goes inside the
// braces and lands in a column below the label; `headerData` puts extra
// controls (counts, buttons) on the right of the label row.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card
    property string title: ""
    property alias spacing: body.spacing
    default property alias contentData: body.data
    property alias headerData: trailing.data

    implicitHeight: col.implicitHeight + Theme.spacing.xl * 2
    radius: 10 * Theme.radiusScale
    color: Theme.bg
    border.color: Theme.border
    border.width: 1

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        RowLayout {
            Layout.fillWidth: true
            visible: card.title !== ""
            spacing: Theme.spacing.md
            Text {
                text: card.title.toUpperCase()
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.letterSpacing: 1
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            RowLayout {
                id: trailing
                spacing: Theme.spacing.md
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Theme.spacing.lg
        }
    }
}
