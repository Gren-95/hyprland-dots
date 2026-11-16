pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// AirPods state that BlueZ does not expose, from the patched librepods daemon
// (librepods.service, see scripts/librepods/):
//  - battery levels (0..1) from $XDG_RUNTIME_DIR/librepods-battery.json
//  - noise control and conversation awareness from librepods-controls.json
// Commands go back through scripts/airpods.sh.
Singleton {
    id: svc
    // Address of the AirPods the battery file describes, upper-case; "" when unknown.
    property string address: ""
    // Lowest of the two buds, -1 when neither bud reports.
    property real level: -1
    // Per component, -1 when not reported or not connected.
    property real left: -1
    property real right: -1
    property real caseLevel: -1
    property bool caseCharging: false

    // 1 off, 2 noise cancellation, 3 transparency, 4 adaptive; 0 = unknown.
    property int listeningMode: 0
    // Whether the AirPods allow "Off" as a listening mode (a setting on them).
    property bool allowOff: false
    // -1 unknown, 0 off, 1 on.
    property int conversationDetect: -1

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/librepods-battery.json"
        watchChanges: true
        onLoaded: svc.apply(text())
        // The daemon removes the file when the AirPods disconnect.
        onLoadFailed: svc.clear()
        onFileChanged: reload()
    }
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/librepods-controls.json"
        watchChanges: true
        onLoaded: svc.applyControls(text())
        onLoadFailed: { svc.listeningMode = 0; svc.conversationDetect = -1; }
        onFileChanged: reload()
    }

    function clear() {
        svc.address = "";
        svc.level = -1;
        svc.left = -1;
        svc.right = -1;
        svc.caseLevel = -1;
        svc.caseCharging = false;
    }
    function _bud(c) {
        return c && c.connected && typeof c.level === "number" ? c.level / 100 : -1;
    }
    // Anything unreadable or incomplete hides the indicator rather than
    // keeping the last level.
    function apply(raw) {
        let state = null;
        try { state = JSON.parse(raw); } catch (e) { /* handled below */ }
        const components = state && state.components;
        if (!components || !state.mac) { clear(); return; }
        svc.left = _bud(components.left);
        svc.right = _bud(components.right);
        const c = components["case"];
        svc.caseLevel = c && typeof c.level === "number" && c.level > 0 ? c.level / 100 : -1;
        svc.caseCharging = !!(c && c.charging);
        const buds = [svc.left, svc.right].filter(v => v >= 0);
        svc.address = String(state.mac).toUpperCase();
        svc.level = buds.length > 0 ? Math.min(...buds) : -1;
    }
    function applyControls(raw) {
        let s = null;
        try { s = JSON.parse(raw); } catch (e) { return; }
        if (!s) return;
        if (typeof s.listening_mode === "number") svc.listeningMode = s.listening_mode;
        if (typeof s.allow_off === "boolean") svc.allowOff = s.allow_off;
        if (typeof s.conversation_detect === "boolean") svc.conversationDetect = s.conversation_detect ? 1 : 0;
    }

    // Battery level for a device address, -1 when this daemon has none for it.
    function levelFor(deviceAddress) {
        return svc.level >= 0 && String(deviceAddress).toUpperCase() === svc.address ? svc.level : -1;
    }
    // True when the daemon is talking to this device (controls apply to it).
    function handles(deviceAddress) {
        return svc.address !== "" && String(deviceAddress).toUpperCase() === svc.address;
    }
}
