import QtQuick
import QtQuick.Layouts

Rectangle {
    id: wr
    property var network
    property bool highlighted: false
    signal hovered()
    signal picked()
    signal forgetRequested()
    Layout.fillWidth: true
    implicitHeight: Theme.height.rowSm
    radius: Theme.radius.sm

    readonly property bool isConnected: wr.network && wr.network.connected
    readonly property bool isKnown: wr.network && wr.network.known
    readonly property bool isBusy: wr.network && wr.network.stateChanging
    // Normalized signal 0–1 (WifiNetwork.signalStrength is a double; some
    // backends report 0–100, so fold that in). -1 = unknown.
    readonly property real sig: {
        if (!wr.network || wr.network.signalStrength === undefined || wr.network.signalStrength === null) return -1;
        const s = wr.network.signalStrength;
        return s > 1 ? s / 100 : s;
    }
    function _wifiGlyph(f) {
        if (f < 0) return "󰤨";
        return f >= 0.75 ? "󰤨" : f >= 0.5 ? "󰤥" : f >= 0.25 ? "󰤢" : f > 0 ? "󰤟" : "󰤯";
    }

    color: wr.highlighted ? Theme.bgActive : (wHover.containsMouse ? Theme.bgHover : "transparent")
    scale: wHover.pressed ? 0.985 : 1.0
    Behavior on color { ColorAnimation  { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    // Animated selection / hover accent rail.
    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: parent.height - 12
        radius: 1.5 * Theme.radiusScale
        color: Theme.accent.green
        opacity: wr.isConnected ? 1.0 : (wr.highlighted ? 0.8 : (wHover.containsMouse ? 0.4 : 0.0))
        Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: Theme.spacing.md
        Text {
            // Strength-aware Wi-Fi glyph (bars reflect signalStrength).
            text: wr._wifiGlyph(wr.sig)
            color: wr.isConnected ? Theme.accent.green : (wr.isKnown ? Theme.muted : Theme.mutedDeep)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            Layout.fillWidth: true
            text: wr.network ? (wr.network.name || "<hidden>") : ""
            color: wr.isConnected ? Theme.fg : Theme.fgMuted
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: wr.isConnected
        }
        Spinner {
            visible: wr.isBusy
            color: Theme.accent.yellow
            implicitWidth: 13
            implicitHeight: 13
        }
        Text {
            visible: wr.isKnown && !wr.isConnected && !wr.isBusy
            text: "saved"
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
        }
        Text {
            visible: wr.isConnected
            text: "✓"
            color: Theme.accent.green
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    MouseArea {
        id: wHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (!wr.network) return;
            if (e.button === Qt.RightButton && wr.network.known) {
                wr.forgetRequested();
                return;
            }
            wr.picked();
        }
        onContainsMouseChanged: if (containsMouse) wr.hovered()
    }
}
