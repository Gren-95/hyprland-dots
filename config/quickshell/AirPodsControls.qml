// Extra controls for AirPods, shown in a Bluetooth device row's details when
// the device name matches /airpods/i and it is connected.
//
// Battery per bud and case, noise control and conversation awareness come
// from the patched librepods daemon (AirPodsBattery singleton); commands go
// through scripts/airpods.sh. The codec row and "Fix audio" act on the
// PipeWire card directly, so they work without librepods too.
//
// Built from the shell's own idioms: level tiles like BatteryCard, a sliding
// segmented selector like ProfileSelector, a toggle card like NotifPane's.
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
    spacing: Theme.spacing.md

    // ===== Commands =====
    Process { id: cmdProc; command: [] }
    function run(args) {
        cmdProc.command = ["bash", Paths.scripts + "/airpods.sh"].concat(args);
        cmdProc.startDetached();
    }

    // Active A2DP profile of the card, refreshed while the section is shown.
    property string profile: ""
    Process {
        id: profileProc
        command: ["bash", Paths.scripts + "/airpods.sh", "codec-status", ac.mac]
        stdout: StdioCollector { onStreamFinished: ac.profile = text.trim() }
    }
    Timer {
        interval: 2000
        repeat: true
        running: ac.visible && ac.mac !== ""
        triggeredOnStart: true
        onTriggered: if (!profileProc.running) profileProc.running = true
    }

    // Noise-control modes as librepods numbers them.
    readonly property var modes: [
        { mode: 1, key: "off",          glyph: "󱡐", label: "Off",          accent: Theme.accent.slate },
        { mode: 2, key: "anc",          glyph: "󰋋", label: "Noise cancel", accent: Theme.accent.purple },
        { mode: 3, key: "transparency", glyph: "󰟅", label: "Transparency", accent: Theme.accent.teal },
        { mode: 4, key: "adaptive",     glyph: "󰙴", label: "Adaptive",     accent: Theme.accent.blue },
    ].filter(m => m.mode !== 1 || AirPodsBattery.allowOff)
    readonly property int modeIndex: modes.findIndex(m => m.mode === AirPodsBattery.listeningMode)

    readonly property var codecs: [
        { profile: "a2dp-sink",        key: "aac",    label: "AAC" },
        { profile: "a2dp-sink-sbc_xq", key: "sbc-xq", label: "SBC-XQ" },
        { profile: "a2dp-sink-sbc",    key: "sbc",    label: "SBC" },
    ]

    function levelColor(v) {
        return v > 0.5 ? Theme.accent.green : v > 0.2 ? Theme.accent.yellow : Theme.accent.red;
    }

    component SectionLabel: Text {
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.xs
        font.letterSpacing: 1
        font.bold: true
    }

    // ===== Battery =====
    RowLayout {
        visible: ac.live
        Layout.fillWidth: true
        spacing: Theme.spacing.sm
        Repeater {
            model: [
                { glyph: "󱡏", label: "Left",  v: AirPodsBattery.left,      charging: false },
                { glyph: "󱡏", label: "Right", v: AirPodsBattery.right,     charging: false },
                { glyph: "󰏗", label: "Case",  v: AirPodsBattery.caseLevel, charging: AirPodsBattery.caseCharging },
            ]
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property bool known: modelData.v >= 0
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 58
                radius: 10 * Theme.radiusScale
                color: Theme.bgInset
                border.color: Theme.borderSubtle
                border.width: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.md
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.sm
                        Text {
                            text: tile.modelData.glyph
                            color: tile.known ? Theme.fgMuted : Theme.disabled
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                        }
                        Text {
                            Layout.fillWidth: true
                            text: tile.modelData.label
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                        Text {
                            text: (tile.modelData.charging ? "󱐋" : "")
                                + (tile.known ? Math.round(tile.modelData.v * 100) + "%" : "–")
                            color: tile.known ? Theme.fg : Theme.disabled
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                            font.bold: tile.known
                        }
                    }
                    // Level bar.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Theme.bgDeep
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, tile.modelData.v))
                            height: parent.height
                            radius: 2
                            visible: tile.known
                            color: tile.modelData.charging ? Theme.accent.green : ac.levelColor(tile.modelData.v)
                            Behavior on width { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                        }
                    }
                }
            }
        }
    }

    // ===== Noise control: sliding segmented selector =====
    SectionLabel { visible: ac.live; text: "NOISE CONTROL" }
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

    // ===== Conversation awareness: toggle card =====
    Rectangle {
        id: conv
        visible: ac.live && AirPodsBattery.conversationDetect >= 0
        readonly property bool on: AirPodsBattery.conversationDetect === 1
        Layout.fillWidth: true
        implicitHeight: 50
        radius: 10 * Theme.radiusScale
        color: conv.on ? Theme.alpha(Theme.accent.orange, 0.16)
             : (convMa.containsMouse ? Theme.bgActive : Theme.bgInset)
        border.color: conv.on ? Theme.accent.orange : Theme.borderSubtle
        border.width: 1
        scale: convMa.pressed ? 0.97 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.lg
            anchors.rightMargin: Theme.spacing.lg
            spacing: Theme.spacing.md
            Text {
                text: "󰆉"
                color: conv.on ? Theme.accent.orange : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: "Conversation awareness"
                    color: conv.on ? Theme.fg : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: conv.on
                }
                Text {
                    text: "Lowers the volume when you start speaking"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }
            // Switch.
            Rectangle {
                implicitWidth: 34
                implicitHeight: 18
                radius: 9
                color: conv.on ? Theme.accent.orange : Theme.bgDeep
                border.color: conv.on ? Theme.accent.orange : Theme.borderStrong
                border.width: 1
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    y: 3
                    x: conv.on ? parent.width - width - 3 : 3
                    color: conv.on ? Theme.fgOnAccent : Theme.muted
                    Behavior on x { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                }
            }
        }
        MouseArea {
            id: convMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ac.run(["conversation", conv.on ? "off" : "on"])
        }
    }

    // ===== Audio: codec chips and Fix audio =====
    SectionLabel { text: "AUDIO" }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.sm
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 8 * Theme.radiusScale
            color: Theme.bgInset
            border.color: Theme.borderSubtle
            border.width: 1
            Row {
                anchors.fill: parent
                anchors.margins: 3
                Repeater {
                    model: ac.codecs
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool active: ac.profile === modelData.profile
                        width: (parent.width) / ac.codecs.length
                        height: parent.height
                        radius: 6 * Theme.radiusScale
                        color: chip.active ? Theme.alpha(Theme.accentPrimary, 0.22)
                             : chipMa.containsMouse ? Theme.bgActive : "transparent"
                        border.color: chip.active ? Theme.accentPrimary : "transparent"
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                        Text {
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: chip.active ? Theme.fg : Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                            font.bold: chip.active
                        }
                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { ac.run(["codec", ac.mac, chip.modelData.key]); ac.profile = chip.modelData.profile; }
                        }
                    }
                }
            }
        }
        // One bud silent while the other plays: drop the audio profile and
        // bring it back, which reconnects the stream to both buds.
        Rectangle {
            implicitWidth: fixRow.implicitWidth + Theme.spacing.lg * 2
            implicitHeight: 32
            radius: 8 * Theme.radiusScale
            color: fixMa.containsMouse ? Theme.bgActive : Theme.bgInset
            border.color: Theme.borderStrong
            border.width: 1
            scale: fixMa.pressed ? 0.95 : 1.0
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Row {
                id: fixRow
                anchors.centerIn: parent
                spacing: Theme.spacing.sm
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰑓"
                    color: Theme.accent.blueBright
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    RotationAnimation on rotation {
                        id: spin
                        running: false
                        from: 0; to: 360
                        duration: 900
                        easing.type: Easing.OutCubic
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Fix audio"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
            }
            MouseArea {
                id: fixMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { spin.restart(); ac.run(["reset-audio", ac.mac]); }
            }
        }
    }
}
