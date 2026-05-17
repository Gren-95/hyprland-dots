// On-screen display for volume, mic, screen brightness, and keyboard backlight.
// Volume/mic react to Pipewire property changes. Brightness/keyboard-backlight
// are detected by polling sysfs files (libudev-style behaviour, matches swayosd):
// any process that changes brightness — key, brightnessctl, hypridle — triggers
// the OSD.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

Scope {
    id: root

    property string osdIcon: ""
    property string osdLabel: ""
    property real osdLevel: 0
    property bool osdMuted: false
    property color osdAccent: Theme.accent.blue
    property int osdToken: 0
    property bool _ready: false

    // sysfs device discovery + cached max values
    property string blDev: ""
    property string kbDev: ""
    property int blMax: 0
    property int kbMax: 0
    property int blLast: -1
    property int kbLast: -1

    function show(icon, level, label, muted, accent) {
        osdIcon = icon;
        osdLabel = label;
        osdLevel = Math.max(0, Math.min(1, level));
        osdMuted = muted;
        osdAccent = accent;
        osdToken += 1;
        hideTimer.restart();
    }

    Timer { id: hideTimer; interval: 1500; running: false; repeat: false }
    Timer {
        id: readyTimer
        interval: 800
        running: true
        repeat: false
        onTriggered: root._ready = true
    }

    function showVolume() {
        const a = Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio;
        if (!a) return;
        const v = a.volume;
        const icon = a.muted ? "󰸈" : (v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾");
        root.show(icon, v, "Volume", a.muted, Theme.accent.blue);
    }
    function showMic() {
        const a = Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio;
        if (!a) return;
        root.show(a.muted ? "󰍭" : "󰍬", a.volume, "Microphone", a.muted, Theme.accent.green);
    }
    function showBrightness(cur) {
        if (root.blMax <= 0) return;
        const pct = cur / root.blMax;
        const icon = pct < 0.34 ? "󰃞" : pct < 0.67 ? "󰃟" : "󰃠";
        root.show(icon, pct, "Brightness", false, Theme.accent.yellow);
    }
    function showKbBacklight(cur) {
        if (root.kbMax <= 0) return;
        const pct = cur / root.kbMax;
        root.show(cur === 0 ? "󰥻" : "󰌌", pct, "Keyboard backlight", false, Theme.accent.purple);
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    Connections {
        target: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio
        function onVolumeChanged() { if (root._ready) root.showVolume(); }
        function onMutedChanged() { if (root._ready) root.showVolume(); }
    }
    Connections {
        target: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio
        function onMutedChanged() { if (root._ready) root.showMic(); }
    }

    // One-shot device discovery on startup: pick the first backlight in
    // /sys/class/backlight and the first kbd_backlight LED.
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight/ 2>/dev/null | head -1; ls /sys/class/leds/ 2>/dev/null | grep -iE 'kbd_backlight|kbd-backlight|keyboard' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                root.blDev = (lines[0] || "").trim();
                root.kbDev = (lines[1] || "").trim();
                if (root.blDev) maxProc.command = ["sh", "-c",
                    "cat /sys/class/backlight/" + root.blDev + "/max_brightness; cat /sys/class/leds/" + (root.kbDev || ".no.") + "/max_brightness 2>/dev/null || echo 0"];
                if (root.blDev) maxProc.running = true;
            }
        }
    }
    Process {
        id: maxProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                root.blMax = parseInt(parts[0]) || 0;
                root.kbMax = parseInt(parts[1]) || 0;
            }
        }
    }

    // Polling reader: emits one stdout line per fire with "<bl> <kb>".
    Process {
        id: pollProc
        running: false
        command: ["sh", "-c",
            "bl=$(cat /sys/class/backlight/" + (root.blDev || "x") + "/brightness 2>/dev/null || echo -1);" +
            "kb=$(cat /sys/class/leds/" + (root.kbDev || "x") + "/brightness 2>/dev/null || echo -1);" +
            "echo \"$bl $kb\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                const bl = parseInt(parts[0]);
                const kb = parseInt(parts[1]);
                if (isFinite(bl) && bl >= 0) {
                    if (root.blLast === -1) root.blLast = bl;
                    else if (bl !== root.blLast) {
                        root.blLast = bl;
                        if (root._ready) root.showBrightness(bl);
                    }
                }
                if (isFinite(kb) && kb >= 0) {
                    if (root.kbLast === -1) root.kbLast = kb;
                    else if (kb !== root.kbLast) {
                        root.kbLast = kb;
                        if (root._ready) root.showKbBacklight(kb);
                    }
                }
            }
        }
    }
    Timer {
        interval: 200
        running: root.blDev !== "" && root.blMax > 0
        repeat: true
        onTriggered: {
            if (!pollProc.running) pollProc.running = true;
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            color: "transparent"

            anchors { bottom: true; left: true; right: true }
            margins.bottom: 60
            implicitHeight: 120
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // Empty input region — the panel is always mapped (so we can fade
            // the card in/out without recreating the surface) but clicks pass
            // straight through to whatever's below it.
            mask: Region {}

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                implicitWidth: cardCol.implicitWidth + 28
                implicitHeight: cardCol.implicitHeight + 20
                radius: 14
                color: Theme.bg
                border.color: Theme.borderStrong
                border.width: 1

                opacity: hideTimer.running ? 1.0 : 0.0
                transform: Translate {
                    y: hideTimer.running ? 0 : 16
                    Behavior on y { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }

                ColumnLayout {
                    id: cardCol
                    anchors.centerIn: parent
                    spacing: Theme.spacing.md

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Theme.spacing.lg
                        Text {
                            text: root.osdIcon
                            color: root.osdMuted ? Theme.mutedDeep : root.osdAccent
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.hero
                        }
                        ColumnLayout {
                            spacing: 0
                            Text {
                                text: root.osdLabel
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                            }
                            Text {
                                text: root.osdMuted ? "Muted" : Math.round(root.osdLevel * 100) + "%"
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xl
                                font.bold: true
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Theme.bgAlt
                        Rectangle {
                            width: parent.width * (root.osdMuted ? 0 : root.osdLevel)
                            height: parent.height
                            radius: 3
                            color: root.osdAccent
                            Behavior on width { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                        }
                    }
                }
            }
        }
    }
}
