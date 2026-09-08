// SuperWatch — tells the hold-to-browse overlays when Super comes back up.
//
// Hyprland does not deliver the hyprland-global-shortcuts "released" event:
// measured, quickshell sees "pressed" for a SUPER + Super_L bind and never the
// matching release. Every overlay that wants "commit when you let go" was
// hanging off that event, so none of them ever committed — the workspace
// overview only ever landed via Enter or a click.
//
// The key state itself is readable, though. evdev knows, and `evtest --query`
// reports it in about 3ms without root for anyone in the input group. So this
// polls it while an overlay is up and emits released() once both Super keys
// are actually off, which is the one mechanism that has been shown to work.
//
// `active` is driven from shell.qml as "any hold overlay is open"; consumers
// listen for released() and ignore it if it is not theirs (their commit is a
// no-op when closed). poke() restarts the clock after an interaction.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool active: false
    signal released()

    readonly property int pollInterval: 120     // while the probe works
    readonly property int fallbackDelay: 500    // no probe: time since last poke
    // Cleared the first time the probe answers with something unexpected —
    // no evtest, no readable device — after which this degrades to a timer.
    property bool probeUsable: true

    function poke() { if (root.active) tick.restart() }

    onActiveChanged: {
        if (root.active) tick.restart();
        else { tick.stop(); probe.running = false }
    }

    Timer {
        id: tick
        interval: root.probeUsable ? root.pollInterval : root.fallbackDelay
        repeat: false
        onTriggered: {
            if (!root.probeUsable) { root.released(); return }
            probe.running = false;
            probe.running = true;
        }
    }

    // Exits 10 while either Super key is down, 0 once both are up.
    Process {
        id: probe
        command: ["sh", "-c",
            "for d in /dev/input/by-path/*-event-kbd; do " +
            "[ -r \"$d\" ] || continue; " +
            "evtest --query \"$d\" EV_KEY KEY_LEFTMETA;  [ $? -eq 10 ] && exit 10; " +
            "evtest --query \"$d\" EV_KEY KEY_RIGHTMETA; [ $? -eq 10 ] && exit 10; " +
            "done; exit 0"]
        running: false
        onExited: (code) => {
            if (!root.active) return;
            if (code === 10) { tick.restart(); return }          // still held
            if (code !== 0) {
                console.warn("SuperWatch: key probe unusable (exit", code +
                             "), falling back to a timer");
                root.probeUsable = false;
                tick.restart();
                return;
            }
            root.released();
        }
    }
}
