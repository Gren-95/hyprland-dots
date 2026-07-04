// Full-width toggle pill: leading tinted icon square, label + description,
// trailing on/off track switch. Generic — state comes in via `on`, what a
// click does is up to the consumer (picked()). Extracted from QuickActions'
// inline ToggleRow so the Settings panel can reuse it.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row
    property string glyph: ""
    property string offGlyph: glyph   // glyph shown while off (defaults to glyph)
    property color accent: Theme.accent.blue
    property string label: ""
    property string desc: ""
    property bool on: false
    property bool highlighted: false
    signal picked()
    signal hovered()

    implicitHeight: 54
    radius: 10
    color: row.on
        ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
        : (rowMa.containsMouse ? Theme.bgHover : "#1a1716")
    border.color: row.on ? accent : (row.highlighted ? Theme.mutedDeep : Theme.borderSubtle)
    border.width: row.on ? 2 : 1
    scale: rowMa.pressed ? 0.98 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
    Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: Theme.spacing.lg

        // Icon square
        Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: Qt.rgba(row.accent.r, row.accent.g, row.accent.b, row.on ? 0.20 : 0.08)
            Text {
                anchors.centerIn: parent
                text: row.on ? row.glyph : row.offGlyph
                color: row.on ? row.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
            }
        }

        // Title + description
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Text {
                text: row.label
                color: row.on ? Theme.fg : Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: row.on
            }
            Text {
                Layout.fillWidth: true
                text: row.desc
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                elide: Text.ElideRight
            }
        }

        // Track-style switch indicator
        Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 10
            color: row.on ? row.accent : Theme.borderSubtle
            border.color: row.on ? row.accent : Theme.border
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Rectangle {
                width: 14
                height: 14
                radius: 7
                color: Theme.fg
                anchors.verticalCenter: parent.verticalCenter
                x: row.on ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            }
        }
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.picked()
        onContainsMouseChanged: if (containsMouse) row.hovered()
    }
}
