// Application result row: large icon, name, comment. The selection plate is
// drawn by the list (LauncherSelection); the row only tints its text.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: row
    property var entry
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: 56
    scale: hover.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.xl
        anchors.rightMargin: Theme.spacing.lg
        spacing: Theme.spacing.lg
        IconImage {
            implicitSize: 40
            source: row.entry ? Quickshell.iconPath(row.entry.icon, "application-x-executable") : ""
            asynchronous: true
            scale: row.highlighted ? 1.06 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: row.entry ? row.entry.name : ""
                color: row.highlighted ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                font.bold: row.highlighted
                elide: Text.ElideRight
                Layout.fillWidth: true
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
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
            text: "↵"
            color: Theme.accentPrimary
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            opacity: row.highlighted ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
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
