// Pinned wired-connection row shown above the Wi-Fi network list when a
// managed ethernet adapter is present (built-in / USB / dock). Mirrors
// WifiNetworkRow's look; teal is the wired accent.
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking

Rectangle {
    id: er
    property var device            // Quickshell.Networking WiredDevice
    property bool highlighted: false
    signal hovered()
    signal picked()
    signal editRequested()
    Layout.fillWidth: true
    implicitHeight: Theme.height.rowSm
    radius: Theme.radius.sm

    readonly property bool isConnected: er.device && er.device.connected
    readonly property bool hasLink: er.device && er.device.hasLink
    readonly property bool isBusy: er.device
        && (er.device.state === ConnectionState.Connecting
         || er.device.state === ConnectionState.Disconnecting)
    function _speed(mbps) {
        if (!mbps) return "";
        return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s";
    }

    color: er.highlighted ? Theme.bgActive : (eHover.containsMouse ? Theme.bgHover : "transparent")
    scale: eHover.pressed ? 0.985 : 1.0
    Behavior on color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Animated selection / hover accent rail.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 12
        radius: 1.5 * Theme.radiusScale
        color: Theme.accent.teal
        opacity: er.isConnected ? 1.0 : (er.highlighted ? 0.8 : (eHover.containsMouse ? 0.4 : 0.0))
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: Theme.spacing.md
        Text {
            text: "󰈀"
            color: er.isConnected ? Theme.accent.teal : (er.hasLink ? Theme.muted : Theme.mutedDeep)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: "Ethernet"
            color: er.isConnected ? Theme.fg : Theme.fgMuted
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: er.isConnected
        }
        Spinner {
            visible: er.isBusy
            color: Theme.accent.yellow
            implicitWidth: 13
            implicitHeight: 13
        }
        Text {
            visible: !er.hasLink
            text: "no cable"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
        }
        Text {
            visible: !!(er.isConnected && er.device && er.device.linkSpeed > 0)
            text: er.device ? er._speed(er.device.linkSpeed) : ""
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
        }
        Text {
            visible: er.isConnected
            text: "✓"
            color: Theme.accent.teal
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    // Click → edit the connection (nm-connection-editor); right-click →
    // toggle (disconnect/reconnect). Keyboard Enter mirrors right-click.
    MouseArea {
        id: eHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (e.button === Qt.RightButton) { er.picked(); return; }
            er.editRequested();
        }
        onContainsMouseChanged: if (containsMouse) er.hovered()
    }
}
