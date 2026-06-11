// Hover tooltip for bar elements. Anchors a small popup just below `target`
// (needs `bar` so it can draw outside the thin bar window). Drive `active`
// from a HoverHandler / MouseArea.containsMouse on the bar element.
import QtQuick
import Quickshell

PopupWindow {
    id: tip
    property string text: ""
    property var bar: null
    property var target: null
    property bool active: false
    property int delay: 500

    property bool _show: false
    visible: tip._show && tip.text !== "" && tip.bar && tip.target
    color: "transparent"
    anchor.window: tip.bar
    anchor.item: tip.target
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

    implicitWidth: label.implicitWidth + 16
    implicitHeight: label.implicitHeight + 10

    onActiveChanged: {
        if (tip.active) showTimer.restart();
        else { showTimer.stop(); tip._show = false; }
    }
    Timer { id: showTimer; interval: tip.delay; onTriggered: if (tip.active) tip._show = true }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius.sm
        color: Theme.bgAlt
        border.color: Theme.borderStrong
        border.width: 1
        Text {
            id: label
            anchors.centerIn: parent
            text: tip.text
            color: Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
    }
}
