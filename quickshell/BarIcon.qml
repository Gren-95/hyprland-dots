import QtQuick
import QtQuick.Layouts

Item {
    id: bi
    property string glyph: ""
    property string label: ""
    property string tooltip: ""
    // Pass the bar window to enable the hover tooltip (it needs a surface to
    // draw below the thin bar). Icons without it simply show no tooltip.
    property var parentBar: null
    property color color: "#f5f5f4"
    property int pixelSize: Theme.fontSize.md
    signal clicked()
    signal wheel(bool up)
    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 12
    scale: ma.pressed ? 0.9 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Subtle hover surface so every bar button gets tactile feedback.
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: Theme.radius.sm
        color: ma.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            text: bi.glyph
            color: bi.color
            font.family: Theme.font
            font.pixelSize: bi.pixelSize
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            visible: bi.label !== ""
            text: bi.label
            color: bi.color
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: bi.clicked()
        onWheel: (e) => bi.wheel(e.angleDelta.y > 0)
    }

    BarTooltip {
        bar: bi.parentBar
        target: bi
        text: bi.tooltip
        active: ma.containsMouse
    }
}
