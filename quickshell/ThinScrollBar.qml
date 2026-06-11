// Slim scroll indicator for Flickables. Shows only when content overflows
// (AsNeeded); brightens while scrolling/hovering, dims at rest. Use as:
//   Flickable { ScrollBar.vertical: ThinScrollBar {} }
import QtQuick
import QtQuick.Controls

ScrollBar {
    id: sb
    policy: ScrollBar.AsNeeded
    width: 5
    padding: 1
    contentItem: Rectangle {
        implicitWidth: 4
        radius: 2
        color: Theme.muted
        opacity: sb.pressed ? 0.9 : (sb.active ? 0.6 : 0.3)
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }
}
