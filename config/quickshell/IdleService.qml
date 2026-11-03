// The one place that decides "idle inhibited, and why". Two mechanisms:
//  - Stay Awake (manual toggle, plus media / AC power per settings) stops the
//    hypridle daemon.
//  - Media playing or a fullscreen window holds a ScreenSaver inhibitor
//    (scripts/idle-inhibit-hold.sh) while hypridle keeps running, so its
//    lock-before-sleep still works.
// Instantiated once in shell.qml as idleService; QuickActions' Stay Awake tile
// and StatusIndicators observe the same state.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower

Scope {
    id: svc

    property bool manual: false          // the user's Stay Awake toggle
    property bool daemonRunning: true    // set by apply(); pgrep re-checks slowly
    property bool inFlight: false        // skip reconcile while toggling

    readonly property bool anyPlaying: {
        const list = (Mpris.players && Mpris.players.values) || [];
        return list.some(p => p && p.playbackState === MprisPlaybackState.Playing);
    }
    readonly property bool onAC: !UPower.onBattery

    readonly property bool wantInhibit: manual
        || (settingsStore.idleInhibitOnMedia && anyPlaying)
        || (settingsStore.idleInhibitOnPower && onAC)
    // Any workspace has a fullscreen window. Quickshell keeps the workspace
    // objects current from Hyprland's events.
    readonly property bool fullscreenActive:
        Hyprland.workspaces.values.some(w => w.lastIpcObject && w.lastIpcObject.hasfullscreen === true)

    // Automatic holder: wanted while media plays or a window is fullscreen.
    readonly property bool wantHold: anyPlaying || fullscreenActive
    property bool holding: false
    readonly property string holdReason: anyPlaying ? "media playing" : "fullscreen"

    readonly property bool effectiveInhibited: !daemonRunning || holding
    readonly property string reason: manual ? "manual"
        : (settingsStore.idleInhibitOnMedia && anyPlaying) ? "media playing"
        : (settingsStore.idleInhibitOnPower && onAC) ? "on AC power"
        : holding ? holdReason
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

    // The holder starts at once but lets go 2 s late, so a track skip or a
    // brief pause does not churn it.
    onWantHoldChanged: {
        if (wantHold) { holdOff.stop(); holding = true; }
        else holdOff.restart();
    }
    Timer { id: holdOff; interval: 2000; onTriggered: svc.holding = false }
    onHoldingChanged: holdProc.running = holding
    Component.onCompleted: if (wantHold) holding = true

    Process {
        id: holdProc
        command: ["bash", Paths.scripts + "/idle-inhibit-hold.sh", "idle-service", svc.holdReason]
        // The holder exits when it cannot register (hypridle down); try again.
        onExited: if (svc.holding) holdRetry.restart()
    }
    Timer { id: holdRetry; interval: 5000; onTriggered: if (svc.holding) holdProc.running = true }

    // Slow check against reality, covering external kills/starts of hypridle.
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
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: checkProc.running = true
    }
}
