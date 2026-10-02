// Vertical scroller for a day-panel column. Its preferred height is the
// natural height of what it holds, so the panel can size itself to the
// content; when the screen caps the panel it shrinks and scrolls instead.
// Children go inside the braces and stack in a column.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Flickable {
    id: flick
    property alias spacing: col.spacing
    default property alias contentData: col.data
    readonly property real naturalHeight: col.implicitHeight

    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.preferredHeight: naturalHeight
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ThinScrollBar {
        policy: flick.contentHeight > flick.height + 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    ColumnLayout {
        id: col
        width: flick.width - Theme.spacing.md
        spacing: Theme.spacing.lg
    }
}
