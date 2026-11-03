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

    // Keyboard layout: Hyprland's activelayout event ("<device>,<layout>")
    // fires for every keyboard on a switch, so the layout name is compared
    // with the last one seen. One hyprctl read at startup seeds it.
    property string _layout: ""
    Process {
        running: true
        command: ["sh", "-c", "hyprctl devices -j | jq -r '.keyboards[] | select(.main) | .active_keymap' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: if (svc._layout === "") svc._layout = text.trim()
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const layout = event.data.slice(event.data.indexOf(",") + 1);
            if (layout === "" || layout === svc._layout) return;
            const seeded = svc._layout !== "";
            svc._layout = layout;
            if (seeded && svc._ready && svc.want("layout"))
                osd.showToast("󰌌", "Keyboard layout", layout, Theme.accent.teal);
        }
    }
}
