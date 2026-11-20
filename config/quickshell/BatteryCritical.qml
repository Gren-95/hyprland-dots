// The critical-battery action, once for the whole shell (it lived on each
// bar's battery icon, so two monitors sent two warnings and ran two timers).
// The low-battery warnings come from the battery-notify daemon
// (scripts/battery-notify.sh). At the critical level a cancelable 15 s
// countdown suspends; plugging in cancels it, even when a charge threshold
// keeps the battery from charging.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Scope {
    id: root

    property int criticalPct: 5
    property string action: "suspend"

    readonly property var dev: UPower.displayDevice
    readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
    readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
        || dev.state === UPowerDeviceState.FullyCharged)
    readonly property bool plugged: dev && !UPower.onBattery

    onPctChanged: check()
    onChargingChanged: if (charging) timer.stop();
    onPluggedChanged: if (plugged) timer.stop();

    function check() {
        if (charging || plugged || pct <= 0) return;
        if (criticalPct > 0 && pct <= criticalPct && action === "suspend" && !timer.running) {
            proc.command = ["notify-send", "-u", "critical",
                "Battery critical", "Suspending in 15 s — plug in to cancel"];
            proc.startDetached();
            timer.start();
        }
    }

    Timer {
        id: timer
        interval: 15000
        onTriggered: {
            if (!root.charging && !root.plugged) {
                proc.command = ["systemctl", "suspend"];
                proc.startDetached();
            }
        }
    }
    Process { id: proc; command: [] }
}
