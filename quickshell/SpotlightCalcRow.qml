// Calculator result row: the evaluated value, its expression, and a copy hint.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: crow
    property string expr: ""
    property string result: ""
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: 60
    radius: 8 * Theme.radiusScale
    color: crow.highlighted ? Theme.bgActive : (cHover.containsMouse ? Theme.bgHover : "transparent")
    border.color: Theme.accentPrimary
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: Theme.spacing.lg
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 6 * Theme.radiusScale
            color: Theme.accent.blueDeep
            Text {
                anchors.centerIn: parent
                text: "="
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                font.bold: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: crow.result
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                text: crow.expr + " ="
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
        Text {
            text: "↵ Copy"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }
    MouseArea {
        id: cHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: crow.picked()
        onContainsMouseChanged: if (containsMouse) crow.hovered()
    }
}
