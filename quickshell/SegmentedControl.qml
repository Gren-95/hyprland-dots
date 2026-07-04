// Compact 2-3 option pill selector (TabPill styling, no sliding indicator).
// options: [{ id, label }] — `value` marks the active one, clicking emits
// selected(id). Used by the Settings panel for placement choices.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: seg
    property var options: []
    property string value: ""
    signal selected(string id)

    implicitHeight: Theme.height.chip + 4
    implicitWidth: segRow.implicitWidth + 8
    radius: height / 2
    color: Theme.bgDeep
    border.color: Theme.borderSubtle
    border.width: 1

    RowLayout {
        id: segRow
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: seg.options
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: seg.value === modelData.id
                implicitWidth: segLbl.implicitWidth + 16
                implicitHeight: Theme.height.chip
                radius: height / 2
                color: active ? Theme.bgActive : (segMa.containsMouse ? Theme.bgHover : "transparent")
                border.color: active ? Theme.mutedDeep : "transparent"
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

                Text {
                    id: segLbl
                    anchors.centerIn: parent
                    text: modelData.label
                    color: active ? Theme.fg : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: active
                }
                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.selected(modelData.id)
                }
            }
        }
    }
}
