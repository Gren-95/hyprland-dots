// The one place that decides "idle inhibited, and why". Two mechanisms:
//  - Stay Awake (manual toggle, plus media / AC power per settings) stops the
//    hypridle daemon.
//  - Media playing, a fullscreen window, or a Claude Code session at work holds
//    a ScreenSaver inhibitor (scripts/idle-inhibit-hold.sh) while hypridle keeps
//    running, so its lock-before-sleep still works. Claude Code reports its
//    sessions through hooks (scripts/claude-activity.sh).
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

    // Claude Code sessions currently working, reported by claude-activity.sh.
    property int claudeSessions: 0

    // Automatic holder: wanted while media plays, a window is fullscreen, or
    // Claude Code is working.
    readonly property bool wantHold: anyPlaying || fullscreenActive || claudeSessions > 0
    property bool holding: false
    readonly property string holdReason: anyPlaying ? "media playing"
        : fullscreenActive ? "fullscreen" : "Claude working"

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
    // With hypridle stopped (Stay Awake) the holder has nothing to register
    // with; start it once hypridle is back.
    onDaemonRunningChanged: if (daemonRunning && holding && !holdProc.running) holdProc.running = true

    // The claude-activity.sh hooks call this through `qs ipc call claude active`.
    IpcHandler {
        target: "claude"
        function active(count: int): void { svc.claudeSessions = count; }
    }
    // Read the sessions already working when Quickshell starts, and drop ones
    // whose Stop hook never came (a crashed session) while any is counted.
    Process { id: pruneProc; command: ["bash", Paths.scripts + "/claude-activity.sh", "prune"] }
    Timer {
        running: svc.claudeSessions > 0
        interval: 60000
        repeat: true
        onTriggered: pruneProc.running = true
    }
    Component.onCompleted: {
        if (wantHold) holding = true;
        pruneProc.running = true;
    }

    Process {
        id: holdProc
        command: ["bash", Paths.scripts + "/idle-inhibit-hold.sh", "idle-service", svc.holdReason]
        // The holder exits when it cannot register (hypridle down); try again.
        onExited: if (svc.holding && svc.daemonRunning) holdRetry.restart()
    }
    Timer { id: holdRetry; interval: 5000; onTriggered: if (svc.holding && svc.daemonRunning) holdProc.running = true }

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
