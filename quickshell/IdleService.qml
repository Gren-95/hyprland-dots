// Owns the hypridle lifecycle — inhibited = daemon stopped. Combines the
// manual Stay Awake toggle with automatic conditions (media playing / on
// AC power, per settings). Instantiated once in shell.qml as idleService;
// QuickActions' Stay Awake tile and StatusIndicators' pgrep dot both
// observe the same daemon state.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Scope {
    id: svc

    property bool manual: false          // the user's Stay Awake toggle
    property bool daemonRunning: true    // reconciled via pgrep below
    property bool inFlight: false        // skip reconcile while toggling

    readonly property bool anyPlaying: {
        const list = (Mpris.players && Mpris.players.values) || [];
        return list.some(p => p && p.playbackState === MprisPlaybackState.Playing);
    }
    readonly property bool onAC: !UPower.onBattery

    readonly property bool wantInhibit: manual
        || (settingsStore.idleInhibitOnMedia && anyPlaying)
        || (settingsStore.idleInhibitOnPower && onAC)
    readonly property bool effectiveInhibited: !daemonRunning
    readonly property string reason: manual ? "manual"
        : (settingsStore.idleInhibitOnMedia && anyPlaying) ? "media playing"
        : (settingsStore.idleInhibitOnPower && onAC) ? "on AC power"
        : ""

    function toggleManual() {
        manual = !manual;
        apply();   // user intent applies immediately, no debounce
    }

    // Automatic condition changes are debounced so a track skip or a brief
    // pause doesn't churn the daemon.
    onWantInhibitChanged: applyTimer.restart()
    Timer { id: applyTimer; interval: 2000; onTriggered: svc.apply() }

    function apply() {
        if (wantInhibit === !daemonRunning) return;   // already as desired
        inFlight = true;
        clearInFlight.restart();
        toggleProc.command = ["sh", "-c", wantInhibit
            ? "pkill -x hypridle"
            : "pgrep -x hypridle >/dev/null || (hypridle & disown)"];
        toggleProc.startDetached();
        daemonRunning = !wantInhibit;   // optimistic; pgrep reconciles
    }

    Process { id: toggleProc; command: [] }
    Timer {
        id: clearInFlight
        interval: 1500
        onTriggered: { svc.inFlight = false; checkProc.running = true; }
    }

    // Reconcile against reality (covers external kills/starts of hypridle).
    Process {
        id: checkProc
        command: ["sh", "-c", "pgrep -x hypridle >/dev/null && echo 1 || echo 0"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: svc.daemonRunning = text.trim() === "1"
        }
    }
    Timer {
        running: !svc.inFlight
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: checkProc.running = true
    }
}
