// Keyboard hint strip for the launchers: a key cap followed by what it does.
// `hints` is a list of { key, label }.
import QtQuick

Item {
    id: foot
    property var hints: []
    implicitHeight: flow.childrenRect.height

    Flow {
        id: flow
        width: parent.width
        spacing: Theme.spacing.lg
        Repeater {
            model: foot.hints
            delegate: Row {
                required property var modelData
                spacing: Theme.spacing.sm
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: cap.implicitWidth + 10
                    implicitHeight: cap.implicitHeight + 4
                    radius: 4 * Theme.radiusScale
                    color: Theme.bgInset
                    border.color: Theme.border
                    border.width: 1
                    Text {
                        id: cap
                        anchors.centerIn: parent
                        text: modelData.key
                        color: Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.bold: true
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }
        }
    }
}
