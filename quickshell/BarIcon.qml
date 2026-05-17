import QtQuick
import QtQuick.Layouts

Item {
    id: bi
    property string glyph: ""
    property string label: ""
    property string tooltip: ""
    property color color: "#f5f5f4"
    property int pixelSize: 14
    signal clicked()
    signal wheel(bool up)
    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 12
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Text {
            text: bi.glyph
            color: bi.color
            font.family: Theme.font
            font.pixelSize: bi.pixelSize
        }
        Text {
            visible: bi.label !== ""
            text: bi.label
            color: bi.color
            font.family: Theme.font
            font.pixelSize: 13
        }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: bi.clicked()
        onWheel: (e) => bi.wheel(e.angleDelta.y > 0)
    }
}
