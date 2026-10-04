// Search input bar for the keyboard-driven launchers (Spotlight, Clipboard).
// Keystrokes arrive through the flyout's key handler, so this only renders the
// query: icon, typed text with a blinking caret, a result-count chip and a
// clear button. The accent focus ring marks it as the live input.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: bar
    property string text: ""
    property string placeholder: ""
    property string glyph: "󰍉"
    property string countText: ""
    signal cleared()

    implicitHeight: 52
    radius: 10 * Theme.radiusScale
    color: Theme.bgInset
    border.color: Theme.accentPrimary
    border.width: 1

    // Soft outer focus ring.
    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: bar.radius + 3
        color: "transparent"
        border.color: Theme.alpha(Theme.accentPrimary, 0.28)
        border.width: 3
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.lg
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.lg

        Text {
            text: bar.glyph
            color: bar.text !== "" ? Theme.accentPrimary : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xxl
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                id: typed
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 4)
                text: bar.text
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                elide: Text.ElideLeft
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: bar.placeholder
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                elide: Text.ElideRight
                opacity: bar.text === "" ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
            }
            Rectangle {
                id: caret
                anchors.verticalCenter: parent.verticalCenter
                x: typed.width + 2
                width: 2
                height: Theme.fontSize.xl + 4
                radius: 1
                color: Theme.accentPrimary
                SequentialAnimation on opacity {
                    running: true
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.15; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.15; to: 1.0; duration: 520; easing.type: Easing.InOutSine }
                }
            }
        }

        Rectangle {
            visible: bar.countText !== ""
            implicitWidth: countLabel.implicitWidth + 16
            implicitHeight: Theme.height.chip + 2
            radius: height / 2
            color: Theme.bgActive
            Text {
                id: countLabel
                anchors.centerIn: parent
                text: bar.countText
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: true
            }
        }

        Rectangle {
            id: clearBtn
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: width / 2
            enabled: bar.text !== ""
            opacity: enabled ? 1.0 : 0.0
            scale: clearMa.pressed ? 0.88 : (enabled ? 1.0 : 0.7)
            color: clearMa.containsMouse ? Theme.bgActive : "transparent"
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: clearMa.containsMouse ? Theme.fg : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
            MouseArea {
                id: clearMa
                anchors.fill: parent
                hoverEnabled: true
                enabled: clearBtn.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.cleared()
            }
        }
    }
}
