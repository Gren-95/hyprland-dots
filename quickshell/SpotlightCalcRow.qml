// Calculator result row: the evaluated value, its expression, and a copy hint.
import QtQuick
import QtQuick.Layouts

Item {
    id: crow
    property string expr: ""
    property string result: ""
    property bool highlighted: false
    signal picked()
    signal hovered()
    implicitHeight: 72
    scale: cHover.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.xl
        anchors.rightMargin: Theme.spacing.lg
        spacing: Theme.spacing.lg
        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: 10 * Theme.radiusScale
            color: crow.highlighted ? Theme.accent.blueDeep : Theme.alpha(Theme.accent.blue, 0.2)
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Text {
                anchors.centerIn: parent
                text: "="
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
                font.bold: true
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text: crow.result
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
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
            color: crow.highlighted ? Theme.accentPrimary : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
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
