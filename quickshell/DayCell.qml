// One day of the month grid: the number, up to three feed-coloured event
// dots (then "+N"), a hover wash, and an accent ring that eases in on the
// selected day. Today carries a softer ring and an accent number.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: cell
    property int day: 0
    property bool outsideMonth: false
    property bool isWeekend: false
    property bool isToday: false
    property bool isSelected: false
    property int eventCount: 0
    property var eventColors: []
    signal clicked()

    implicitHeight: 44
    radius: 10 * Theme.radiusScale
    color: cell.isSelected ? Theme.bgActive
         : cellMa.containsMouse ? Theme.bgHover
         : "transparent"
    scale: cellMa.pressed ? 0.94 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Today ring.
    Rectangle {
        anchors.fill: parent
        radius: cell.radius
        color: "transparent"
        border.color: Theme.alpha(Theme.accentPrimary, 0.55)
        border.width: 1
        opacity: cell.isToday && !cell.isSelected ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }
    // Selection ring.
    Rectangle {
        anchors.fill: parent
        radius: cell.radius
        color: "transparent"
        border.color: Theme.accentPrimary
        border.width: 2
        opacity: cell.isSelected ? 1.0 : 0.0
        scale: cell.isSelected ? 1.0 : 0.88
        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 3
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: cell.day
            color: cell.outsideMonth ? Theme.disabled
                 : cell.isToday ? Theme.accentPrimary
                 : cell.isWeekend ? Theme.muted
                 : Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            font.bold: cell.isToday || cell.isSelected
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 5
            spacing: 3
            Repeater {
                model: cell.eventColors
                delegate: Rectangle {
                    required property var modelData
                    width: 5; height: 5; radius: 2.5 * Theme.radiusScale
                    color: cell.outsideMonth ? Theme.disabled : modelData
                }
            }
            Text {
                visible: cell.eventCount > 3
                text: "+" + (cell.eventCount - 3)
                color: cell.outsideMonth ? Theme.disabled : Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: true
            }
        }
    }

    MouseArea {
        id: cellMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: cell.clicked()
    }
}
