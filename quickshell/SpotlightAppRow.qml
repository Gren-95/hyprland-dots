// Application result row: icon, name, comment.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: row
    property var entry
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: 52
    radius: 8 * Theme.radiusScale
    color: row.highlighted ? Theme.bgActive : (hover.containsMouse ? Theme.bgHover : "transparent")
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: Theme.spacing.lg
        IconImage {
            implicitSize: 36
            source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
            asynchronous: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: row.entry ? row.entry.name : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                font.bold: row.highlighted
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: row.entry && row.entry.comment
                text: row.entry ? row.entry.comment : ""
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Text {
            visible: row.highlighted
            text: "↵"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
        onContainsMouseChanged: if (containsMouse) row.hovered()
    }
}
