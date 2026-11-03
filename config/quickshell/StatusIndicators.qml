// iOS-style status dots for the bar. Each dot appears only while its thing is
// active and collapses to zero width otherwise (toggling width, not visible —
// a visible:false item doesn't reliably re-appear inside a layout):
//   - green  → a camera (/dev/video*) is open by an app
//   - orange → an app is capturing the microphone (a PipeWire source-output)
//   - red    → the screen is being recorded (gpu-screen-recorder), pulsing
//   - blue   → WayVNC remote access is running
//   - yellow → sleep/idle is being inhibited (Stay Awake / fullscreen / media)
// Hover any dot for a label. Camera and mic come from PipeWire, recording from
// ScreenRecorder, sleep inhibit from IdleService, and the rest from
// RemoteSyncStatus, so nothing here polls.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

RowLayout {
    id: si
    property var parentBar: null
    spacing: 0
    Layout.fillHeight: true

    // Camera / mic: an app is capturing, i.e. a PipeWire input stream exists.
    // (A camera opened straight through /dev/video*, bypassing PipeWire, is
    // not seen.)
    PwObjectTracker { objects: Pipewire.nodes.values }
    readonly property bool cameraOn:
        Pipewire.nodes.values.some(n => n.properties && n.properties["media.class"] === "Stream/Input/Video")
    readonly property bool micOn: Pipewire.nodes.values.some(n => n.type === PwNodeType.AudioInStream)
    readonly property bool recording: recorder.recording
    readonly property bool remoteOn: remoteSyncStatus.remoteOn
    readonly property bool idleHyprOff: !idleService.daemonRunning   // Stay Awake
    readonly property bool fullscreenApp: idleService.fullscreenActive
    readonly property bool immichOn: remoteSyncStatus.immichOn
    readonly property bool jellyfinOn: remoteSyncStatus.jellyfinOn

    readonly property bool mediaPlaying: {
        const ps = (Mpris.players && Mpris.players.values) || [];
        for (let i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].playbackState === MprisPlaybackState.Playing) return true;
        return false;
    }
    readonly property bool sleepInhibit: idleHyprOff || fullscreenApp || mediaPlaying
    // Master switch from Quick Actions ("Activity icons"); hides the whole
    // cluster when off, regardless of what's active.
    readonly property bool enabled: settingsStore.activityIconsVisible
    readonly property bool anyOn: enabled && (cameraOn || micOn || recording || remoteOn
                                  || sleepInhibit || immichOn || jellyfinOn)
    readonly property string sleepReason: {
        const r = [];
        if (si.idleHyprOff)   r.push("Stay Awake");
        if (si.fullscreenApp) r.push("fullscreen app");
        if (si.mediaPlaying)  r.push("media playing");
        return "Sleep prevented · " + r.join(" · ");
    }

    component Dot: Item {
        id: dot
        property string glyph: ""
        property color tint: Theme.fg
        property bool on: false
        property bool pulse: false
        property string tip: ""
        // Gated by the master switch so one toggle hides every dot.
        readonly property bool show: dot.on && si.enabled
        Layout.fillHeight: true
        implicitWidth: dot.show ? (g.implicitWidth + 22) : 0

        Text {
            id: g
            anchors.centerIn: parent
            visible: dot.show
            text: dot.glyph
            color: dot.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            // Soft blink while recording.
            SequentialAnimation on opacity {
                running: dot.pulse && dot.show
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 750; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.35; to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
            }
        }
        HoverHandler { id: dh; enabled: dot.show }
        BarTooltip { bar: si.parentBar; target: dot; text: dot.tip; active: dh.hovered && dot.show }
    }

    // Leading gap + subtle divider so the status cluster reads as a distinct
    // group next to the bell — present only when something is showing.
    Item {
        Layout.fillHeight: true
        implicitWidth: si.anyOn ? 26 : 0
        Text {
            anchors.centerIn: parent
            visible: si.anyOn
            text: "│"
            color: Theme.disabled
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            opacity: si.anyOn ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
        }
    }

    Dot { glyph: "󰄀"; tint: Theme.accent.green;  on: si.cameraOn;     tip: "Camera in use" }
    Dot { glyph: "󰍬"; tint: Theme.accent.orange; on: si.micOn;        tip: "Microphone in use" }
    Dot { glyph: "󰑊"; tint: Theme.accent.red;    on: si.recording;   pulse: true; tip: "Screen recording" }
    Dot { glyph: "󰢹"; tint: Theme.accent.blue;   on: si.remoteOn;     tip: "Remote access · WayVNC :5900" }
    Dot { glyph: "󰅶"; tint: Theme.accent.yellow; on: si.sleepInhibit; tip: si.sleepReason }
    Dot { glyph: "󰋩"; tint: Theme.accent.orange;           on: si.immichOn;     tip: "Immich photo sync on" }
    Dot { glyph: "󰝚"; tint: Theme.accent.purple;           on: si.jellyfinOn;   tip: "Jellyfin music sync on" }
}
