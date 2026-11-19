// AirPods noise control, under a connected AirPods row in the Bluetooth
// flyout. The modes come from the patched librepods daemon
// (AirPodsBattery singleton); commands go through scripts/airpods.sh.
// Battery per bud, conversation awareness, the codec and "Fix audio" are in
// the settings app (Bluetooth, AirPods Details).
//
// A sliding segmented selector like ProfileSelector.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: ac
    property var device
    readonly property string mac: device ? String(device.address) : ""
    // librepods is connected to these AirPods: noise control applies.
    readonly property bool live: AirPodsBattery.handles(mac)
    spacing: Theme.spacing.md

    // ===== Commands =====
    Process { id: cmdProc; command: [] }
    function run(args) {
        cmdProc.command = ["bash", Paths.scripts + "/airpods.sh"].concat(args);
        cmdProc.startDetached();
    }

    // Noise-control modes as librepods numbers them.
    readonly property var modes: [
        { mode: 1, key: "off",          glyph: "󱡐", label: "Off",          accent: Theme.accent.slate },
        { mode: 2, key: "anc",          glyph: "󰋋", label: "Noise cancel", accent: Theme.accent.purple },
        { mode: 3, key: "transparency", glyph: "󰟅", label: "Transparency", accent: Theme.accent.teal },
        { mode: 4, key: "adaptive",     glyph: "󰙴", label: "Adaptive",     accent: Theme.accent.blue },
    ].filter(m => m.mode !== 1 || AirPodsBattery.allowOff)
    readonly property int modeIndex: modes.findIndex(m => m.mode === AirPodsBattery.listeningMode)

    // ===== Noise control: sliding segmented selector =====
    Rectangle {
        id: track
        visible: ac.live
        Layout.fillWidth: true
        implicitHeight: 62
        radius: 10 * Theme.radiusScale
        color: Theme.bgInset
        border.color: Theme.borderSubtle
        border.width: 1
        readonly property real pad: 4
        readonly property real segW: ac.modes.length > 0 ? (width - pad * 2) / ac.modes.length : 0

        Rectangle {
            visible: ac.modeIndex >= 0
            y: track.pad
            height: track.height - track.pad * 2
            width: track.segW
            x: track.pad + Math.max(0, ac.modeIndex) * track.segW
            radius: 8 * Theme.radiusScale
            color: ac.modeIndex >= 0 ? ac.modes[ac.modeIndex].accent : "transparent"
            Behavior on x { NumberAnimation { duration: Theme.duration.slow; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
            Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
        }
        Row {
            anchors.fill: parent
            anchors.margins: track.pad
            Repeater {
                model: ac.modes
                delegate: Item {
                    id: seg
                    required property var modelData
                    required property int index
                    readonly property bool active: ac.modeIndex === index
                    width: track.segW
                    height: parent.height
                    Rectangle {
                        anchors.fill: parent
                        radius: 8 * Theme.radiusScale
                        color: segMa.containsMouse && !seg.active ? Theme.bgActive : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 1
                        scale: segMa.pressed ? 0.92 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: seg.modelData.glyph
                            color: seg.active ? Theme.fgOnAccent : seg.modelData.accent
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xl
                            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: seg.modelData.label
                            color: seg.active ? Theme.fgOnAccent : Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.bold: seg.active
                            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                        }
                    }
                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ac.run(["mode", seg.modelData.key])
                    }
                }
            }
        }
    }
}
