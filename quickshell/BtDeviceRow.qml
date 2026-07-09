import QtQuick
import QtQuick.Layouts

Rectangle {
    id: dr
    property var device
    property bool highlighted: false
    signal hovered()
    Layout.fillWidth: true
    implicitHeight: Theme.height.rowSm
    radius: Theme.radius.sm

    readonly property bool isConnected: dr.device && dr.device.connected
    readonly property bool isPairing: dr.device && dr.device.pairing

    color: dr.highlighted ? Theme.bgActive : (hover.containsMouse ? Theme.bgHover : "transparent")
    scale: hover.pressed ? 0.985 : 1.0
    Behavior on color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Animated selection / hover accent rail.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 12
        radius: 1.5 * Theme.radiusScale
        color: Theme.accent.blueBright
        opacity: dr.isConnected ? 1.0 : (dr.highlighted ? 0.8 : (hover.containsMouse ? 0.4 : 0.0))
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: Theme.spacing.md
        Text {
            text: dr.isConnected ? "󰂱" : "󰂯"
            color: dr.isConnected ? Theme.accent.blueBright : Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: dr.device ? (dr.device.name || dr.device.deviceName || dr.device.address) : ""
            color: dr.isConnected ? Theme.fg : Theme.fgMuted
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: dr.isConnected
        }
        Text {
            visible: dr.device && dr.device.batteryAvailable && !dr.isPairing
            text: dr.device ? Math.round(dr.device.battery * 100) + "%" : ""
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
        Spinner {
            visible: dr.isPairing
            color: Theme.accent.yellow
            implicitWidth: 13
            implicitHeight: 13
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
