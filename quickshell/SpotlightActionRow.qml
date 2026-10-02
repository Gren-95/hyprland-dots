// Shell action result row: tinted glyph square, name, live state pill.
import QtQuick
import QtQuick.Layouts

Item {
    id: arow
    property var action
    property bool highlighted: false
    signal picked()
    signal hovered()
    readonly property bool on: arow.action && arow.action.isToggle ? arow.action.state() : false
    readonly property color accent: arow.action ? arow.action.accent : Theme.accentPrimary
    implicitHeight: 56
    scale: aHover.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.xl
        anchors.rightMargin: Theme.spacing.lg
        spacing: Theme.spacing.lg
        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 10 * Theme.radiusScale
            color: Theme.alpha(arow.accent, arow.on ? 0.28 : (arow.highlighted ? 0.2 : 0.12))
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Text {
                anchors.centerIn: parent
                text: arow.action ? arow.action.glyph : ""
                color: arow.on || arow.highlighted ? arow.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            }
        }
        Text {
            Layout.fillWidth: true
            text: arow.action ? arow.action.name : ""
            color: arow.highlighted ? Theme.fg : Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            font.bold: arow.highlighted
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Rectangle {
            visible: arow.action && arow.action.isToggle
            implicitWidth: stateLbl.implicitWidth + 20
            implicitHeight: 26
            radius: height / 2
            color: arow.on ? Theme.alpha(arow.accent, 0.2) : Theme.bgInset
            border.color: arow.on ? arow.accent : Theme.borderStrong
            border.width: 1
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }
            Text {
                id: stateLbl
                anchors.centerIn: parent
                text: arow.on ? "on" : "off"
                color: arow.on ? arow.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: true
                Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            }
        }
        Text {
            visible: arow.action && !arow.action.isToggle
            text: "↵ open"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            opacity: arow.highlighted ? 1.0 : 0.6
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
        }
    }
    MouseArea {
        id: aHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: arow.picked()
        onContainsMouseChanged: if (containsMouse) arow.hovered()
    }
}
