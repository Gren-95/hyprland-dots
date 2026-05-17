import QtQuick
import QtQuick.Layouts

Rectangle {
    id: dr
    property var device
    property bool highlighted: false
    signal hovered()
    Layout.fillWidth: true
    implicitHeight: 36
    radius: 6
    color: dr.highlighted ? "#3b3531" : (hover.containsMouse ? Theme.bgAlt : "transparent")
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8
        Text {
            text: dr.device && dr.device.connected ? "󰂱" : "󰂯"
            color: dr.device && dr.device.connected ? "#60a5fa" : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: 14
        }
        Text {
            Layout.fillWidth: true
            text: dr.device ? (dr.device.name || dr.device.deviceName || dr.device.address) : ""
            color: "#f5f5f4"
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 12
        }
        Text {
            visible: dr.device && dr.device.batteryAvailable
            text: dr.device ? Math.round(dr.device.battery * 100) + "%" : ""
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: 11
        }
        Text {
            visible: dr.device && dr.device.pairing
            text: "pairing…"
            color: Theme.accent.yellow
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!dr.device) return;
            if (e.button === Qt.RightButton) {
                dr.device.forget();
                return;
            }
            if (dr.device.connected) dr.device.disconnect();
            else dr.device.connect();
        }
        onContainsMouseChanged: if (containsMouse) dr.hovered()
    }
}
