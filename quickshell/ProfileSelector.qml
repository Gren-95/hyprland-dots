// Power-profile selector: a vertical stack of 3 clickable cards. Each card
// shows the profile's icon, name, and a short description. The active
// profile gets a colored accent border + filled radio dot on the right.
// Keyboard-highlighted (tabIndex) card gets a subtle outer ring.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

ColumnLayout {
    id: ps
    property var profiles: []
    property int activeIndex: 0
    property int highlightedIndex: -1
    signal picked(int index)
    signal hovered(int index)
    spacing: Theme.spacing.sm

    function _glyph(p)  { return p === PowerProfile.Performance ? "󱐋"          : p === PowerProfile.Balanced ? "󰾅" : "󰌪" }
    function _label(p)  { return p === PowerProfile.Performance ? "Performance" : p === PowerProfile.Balanced ? "Balanced" : "Power Saver" }
    function _accent(p) { return p === PowerProfile.Performance ? Theme.accent.red     : p === PowerProfile.Balanced ? Theme.accent.yellow : Theme.accent.green }
    function _desc(p)   { return p === PowerProfile.Performance ? "Maximum speed — runs hotter, drains battery"
                               : p === PowerProfile.Balanced    ? "Default — even power and performance"
                                                                : "Extends battery life by throttling" }

    Repeater {
        model: ps.profiles
        delegate: Rectangle {
            id: card
            required property var modelData
            required property int index
            readonly property bool isActive: ps.activeIndex === index
            readonly property bool isHighlighted: ps.highlightedIndex === index
            readonly property color accent: ps._accent(modelData)

            Layout.fillWidth: true
            implicitHeight: Theme.height.card
            radius: 10
            color: isActive
                ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
                : (cardMa.containsMouse ? Theme.bgHover : "#1a1716")
            border.color: isActive ? accent : (isHighlighted ? Theme.mutedDeep : Theme.borderSubtle)
            border.width: isActive ? 2 : 1
            scale: cardMa.pressed ? 0.97 : (isHighlighted ? 1.02 : 1.0)
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: Theme.spacing.lg

                // Icon column with tinted background
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    color: Qt.rgba(card.accent.r, card.accent.g, card.accent.b, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: ps._glyph(card.modelData)
                        color: card.accent
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
                        text: ps._label(card.modelData)
                        color: card.isActive ? Theme.fg : Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        font.bold: card.isActive
                    }
                    Text {
                        Layout.fillWidth: true
                        text: ps._desc(card.modelData)
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        elide: Text.ElideRight
                    }
                }

                // Radio indicator on right
                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    radius: 9
                    color: "transparent"
                    border.color: card.isActive ? card.accent : Theme.border
                    border.width: 2
                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: card.accent
                        scale: card.isActive ? 1.0 : 0.0
                        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.emphasized } }
                    }
                }
            }

            MouseArea {
                id: cardMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ps.picked(index)
                onContainsMouseChanged: if (containsMouse) ps.hovered(index)
            }
        }
    }
}
