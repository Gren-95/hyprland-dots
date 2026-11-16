// Extra controls for AirPods, shown in a Bluetooth device row's details when
// the device name matches /airpods/i and it is connected.
//
// Battery per bud and case, noise control and conversation awareness come
// from the patched librepods daemon (AirPodsBattery singleton); commands go
// through scripts/airpods.sh. The codec row and "Fix audio" act on the
// PipeWire card directly, so they work without librepods too.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: ac
    property var device
    readonly property string mac: device ? String(device.address) : ""
    // librepods is connected to these AirPods: battery and noise control apply.
    readonly property bool live: AirPodsBattery.handles(mac)
    spacing: Theme.spacing.sm

    // ===== Command runner =====
    Process { id: cmdProc; command: [] }
    function run(args) {
        cmdProc.command = ["bash", Paths.scripts + "/airpods.sh"].concat(args);
        cmdProc.startDetached();
    }

    // Active A2DP profile of the card, refreshed while the details are open.
    property string profile: ""
    Process {
        id: profileProc
        command: ["bash", Paths.scripts + "/airpods.sh", "codec-status", ac.mac]
        stdout: StdioCollector { onStreamFinished: ac.profile = text.trim() }
    }
    function refreshProfile() { if (ac.mac !== "" && !profileProc.running) profileProc.running = true; }
    Timer {
        interval: 2000
        repeat: true
        running: ac.visible
        triggeredOnStart: true
        onTriggered: ac.refreshProfile()
    }

    // ===== Small building blocks =====
    component Caption: Text {
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
    }
    component Choice: Rectangle {
        id: ch
        property string label: ""
        property bool selected: false
        property bool enabled: true
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 8 * Theme.radiusScale
        opacity: ch.enabled ? 1 : 0.4
        color: ch.selected ? Theme.alpha(Theme.accentPrimary, 0.22)
             : chMa.containsMouse ? Theme.bgActive : Theme.bgInset
        border.color: ch.selected ? Theme.accentPrimary : Theme.borderStrong
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Text {
            anchors.centerIn: parent
            text: ch.label
            color: ch.selected ? Theme.fg : Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
        MouseArea {
            id: chMa
            anchors.fill: parent
            hoverEnabled: true
            enabled: ch.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: ch.picked()
        }
    }

    // ===== Battery per bud =====
    RowLayout {
        visible: ac.live
        Layout.fillWidth: true
        spacing: Theme.spacing.lg
        Repeater {
            model: [
                { name: "Left", v: AirPodsBattery.left },
                { name: "Right", v: AirPodsBattery.right },
                { name: AirPodsBattery.caseCharging ? "Case ⚡" : "Case", v: AirPodsBattery.caseLevel },
            ]
            delegate: Caption {
                required property var modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData.name + "  " + (modelData.v >= 0 ? Math.round(modelData.v * 100) + "%" : "–")
                color: modelData.v >= 0 && modelData.v <= 0.2 ? Theme.accent.red : Theme.fgMuted
            }
        }
    }

    // ===== Noise control =====
    Caption { visible: ac.live; text: "Noise control" }
    RowLayout {
        visible: ac.live
        Layout.fillWidth: true
        spacing: Theme.spacing.sm
        Choice {
            label: "Off"
            visible: AirPodsBattery.allowOff
            selected: AirPodsBattery.listeningMode === 1
            onPicked: ac.run(["mode", "off"])
        }
        Choice { label: "Noise cancel"; selected: AirPodsBattery.listeningMode === 2; onPicked: ac.run(["mode", "anc"]) }
        Choice { label: "Transparency"; selected: AirPodsBattery.listeningMode === 3; onPicked: ac.run(["mode", "transparency"]) }
        Choice { label: "Adaptive"; selected: AirPodsBattery.listeningMode === 4; onPicked: ac.run(["mode", "adaptive"]) }
    }
    RowLayout {
        visible: ac.live && AirPodsBattery.conversationDetect >= 0
        Layout.fillWidth: true
        spacing: Theme.spacing.sm
        Caption { Layout.fillWidth: true; text: "Conversation awareness" }
        Choice {
            Layout.fillWidth: false
            Layout.preferredWidth: 64
            label: AirPodsBattery.conversationDetect === 1 ? "On" : "Off"
            selected: AirPodsBattery.conversationDetect === 1
            onPicked: ac.run(["conversation", AirPodsBattery.conversationDetect === 1 ? "off" : "on"])
        }
    }

    // ===== Audio =====
    Caption { text: "Codec" }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.sm
        Choice { label: "AAC"; selected: ac.profile === "a2dp-sink"; onPicked: { ac.run(["codec", ac.mac, "aac"]); ac.profile = "a2dp-sink"; } }
        Choice { label: "SBC-XQ"; selected: ac.profile === "a2dp-sink-sbc_xq"; onPicked: { ac.run(["codec", ac.mac, "sbc-xq"]); ac.profile = "a2dp-sink-sbc_xq"; } }
        Choice { label: "SBC"; selected: ac.profile === "a2dp-sink-sbc"; onPicked: { ac.run(["codec", ac.mac, "sbc"]); ac.profile = "a2dp-sink-sbc"; } }
        // One bud silent while the other plays: drop the audio profile and
        // bring it back, which reconnects the stream to both buds.
        Choice { label: "Fix audio"; onPicked: ac.run(["reset-audio", ac.mac]) }
    }
}
