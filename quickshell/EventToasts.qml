// System-event confirmations through the OSD pill (charger plugged,
// default audio output changed, VPN up/down, keyboard layout switched).
// Each is opt-in via settingsStore.eventToasts. Suppressed during the
// first seconds after boot so initial property settles don't fire
// spurious toasts.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Scope {
    id: svc
    property bool _ready: false
    Timer { interval: 5000; running: true; onTriggered: svc._ready = true }
    function want(k) { return (settingsStore.eventToasts || {})[k] === true; }

    Connections {
        target: UPower
        function onOnBatteryChanged() {
            if (!svc._ready || !svc.want("charger")) return;
            const pct = UPower.displayDevice ? Math.round(UPower.displayDevice.percentage * 100) : 0;
            osd.showToast(UPower.onBattery ? "󰂃" : "󰂄",
                UPower.onBattery ? "On battery" : "Charging",
                pct + "%",
                UPower.onBattery ? Theme.accent.yellow : Theme.accent.green);
        }
    }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            if (!svc._ready || !svc.want("audio")) return;
            const s = Pipewire.defaultAudioSink;
            osd.showToast("󰓃", "Audio output",
                s ? (s.description || s.name || "unknown") : "none",
                Theme.accent.blue);
        }
    }

    Connections {
        target: TailscaleService
        function onRunningChanged() {
            if (!svc._ready || !svc.want("vpn")) return;
            osd.showToast("󰒃",
                TailscaleService.running ? "VPN up" : "VPN down",
                TailscaleService.running ? (TailscaleService.tailnet || "connected") : "disconnected",
                TailscaleService.running ? Theme.accent.purple : Theme.muted);
        }
    }

    // Keyboard layout: quickshell's Hyprland rawEvent stream doesn't
    // deliver in this build, so poll the active keymap (only while the
    // layout toast is enabled — no cost otherwise).
    property string _layout: ""
    Process {
        id: layoutProc
        command: ["sh", "-c",
            "hyprctl devices -j | sed -n 's/.*\"active_keymap\": \"\\([^\"]*\\)\".*/\\1/p' | head -1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim();
                if (!l) return;
                if (svc._layout !== "" && l !== svc._layout && svc._ready && svc.want("layout"))
                    osd.showToast("󰌌", "Keyboard layout", l, Theme.accent.teal);
                svc._layout = l;
            }
        }
    }
    Timer {
        running: svc.want("layout")
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: layoutProc.running = true
    }
}
