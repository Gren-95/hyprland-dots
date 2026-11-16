pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// AirPods battery levels (0..1), which BlueZ does not expose. The librepods
// daemon (librepods.service) writes them to $XDG_RUNTIME_DIR/librepods-battery.json.
Singleton {
    id: svc
    // Address of the AirPods the file describes, upper-case; "" when unknown.
    property string address: ""
    // Lowest of the two buds, -1 when neither bud reports.
    property real level: -1

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/librepods-battery.json"
        watchChanges: true
        onLoaded: svc.apply(text())
        // The daemon removes the file when the AirPods disconnect.
        onLoadFailed: svc.clear()
        onFileChanged: reload()
    }

    function clear() {
        svc.address = "";
        svc.level = -1;
    }
    // Anything unreadable or incomplete hides the indicator rather than
    // keeping the last level.
    function apply(raw) {
        let state = null;
        try { state = JSON.parse(raw); } catch (e) { /* handled below */ }
        const components = state && state.components;
        if (!components || !state.mac) { clear(); return; }
        const buds = ["left", "right"]
            .map(name => components[name])
            .filter(bud => bud && bud.connected && typeof bud.level === "number")
            .map(bud => bud.level / 100);
        svc.address = String(state.mac).toUpperCase();
        svc.level = buds.length > 0 ? Math.min(...buds) : -1;
    }

    // Battery level for a device address, -1 when this daemon has none for it.
    function levelFor(deviceAddress) {
        return svc.level >= 0 && String(deviceAddress).toUpperCase() === svc.address ? svc.level : -1;
    }
}
