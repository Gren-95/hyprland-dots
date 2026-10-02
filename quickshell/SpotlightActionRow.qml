// Shell action result row: tinted glyph square, name, live state pill.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: arow
    property var action
    property bool highlighted: false
    signal picked()
    signal hovered()
    readonly property bool on: arow.action && arow.action.isToggle ? arow.action.state() : false
    readonly property color accent: arow.action ? arow.action.accent : Theme.accentPrimary
    implicitHeight: 52
    radius: 8 * Theme.radiusScale
    color: arow.highlighted ? Theme.bgActive : (aHover.containsMouse ? Theme.bgHover : "transparent")
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: Theme.spacing.lg
        Rectangle {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            radius: 8 * Theme.radiusScale
            color: Theme.alpha(arow.accent, arow.on ? 0.25 : 0.12)
            Text {
                anchors.centerIn: parent
                text: arow.action ? arow.action.glyph : ""
                color: arow.on || arow.highlighted ? arow.accent : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
            }
        }
        Text {
            Layout.fillWidth: true
            text: arow.action ? arow.action.name : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            font.bold: arow.highlighted
            elide: Text.ElideRight
        }
        Rectangle {
            visible: arow.action && arow.action.isToggle
            implicitWidth: stateLbl.implicitWidth + 14
            implicitHeight: 20
            radius: 10 * Theme.radiusScale
            color: arow.on ? Theme.alpha(arow.accent, 0.2) : "transparent"
            border.color: arow.on ? arow.accent : Theme.borderStrong
            border.width: 1
            Text {
                id: stateLbl
                anchors.centerIn: parent
                text: arow.on ? "on" : "off"
                color: arow.on ? arow.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: true
            }
        }
        Text {
            visible: arow.action && !arow.action.isToggle
            text: "↵ open"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
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
