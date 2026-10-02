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
        onFileChanged: reload()
    }

    function apply(raw) {
        let state;
        try { state = JSON.parse(raw); } catch (e) { return; }
        const buds = ["left", "right"]
            .map(name => state.components[name])
            .filter(bud => bud && bud.connected)
            .map(bud => bud.level / 100);
        svc.address = String(state.mac).toUpperCase();
        svc.level = buds.length > 0 ? Math.min(...buds) : -1;
    }

    // Battery level for a device address, -1 when this daemon has none for it.
    function levelFor(deviceAddress) {
        return svc.level >= 0 && String(deviceAddress).toUpperCase() === svc.address ? svc.level : -1;
    }
}
