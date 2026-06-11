// iOS-style status dots for the bar. Each dot appears only while its thing is
// active and collapses to zero width otherwise (toggling width, not visible —
// a visible:false item doesn't reliably re-appear inside a layout):
//   - green  → a camera (/dev/video*) is open by an app
//   - orange → an app is capturing the microphone (a PipeWire source-output)
//   - red    → the screen is being recorded (gpu-screen-recorder), pulsing
//   - blue   → WayVNC remote access is running
//   - yellow → sleep/idle is being inhibited (Stay Awake / fullscreen / media)
// Hover any dot for a label. One shared poll drives all of them.
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.Mpris

RowLayout {
    id: si
    property var parentBar: null
    spacing: 0
    Layout.fillHeight: true

    property bool cameraOn: false
    property bool micOn: false
    property bool recording: false
    property bool remoteOn: false
    property bool idleHyprOff: false     // hypridle not running (Stay Awake)
    property bool fullscreenApp: false
    property bool immichOn: false        // Immich sync schedule enabled
    property bool jellyfinOn: false      // Jellyfin sync schedule enabled

    readonly property bool mediaPlaying: {
        const ps = (Mpris.players && Mpris.players.values) || [];
        for (let i = 0; i < ps.length; i++)
            if (ps[i] && ps[i].playbackState === MprisPlaybackState.Playing) return true;
        return false;
    }
    readonly property bool sleepInhibit: idleHyprOff || fullscreenApp || mediaPlaying
    readonly property bool anyOn: cameraOn || micOn || recording || remoteOn
                                  || sleepInhibit || immichOn || jellyfinOn
    readonly property string sleepReason: {
        const r = [];
        if (si.idleHyprOff)   r.push("Stay Awake");
        if (si.fullscreenApp) r.push("fullscreen app");
        if (si.mediaPlaying)  r.push("media playing");
        return "Sleep prevented · " + r.join(" · ");
    }

    Process {
        id: probe
        command: ["sh", "-c",
            // Camera: either an app holds /dev/video* directly (OBS, Zoom…),
            // or — for libcamera/PipeWire-portal apps like Firefox — a PipeWire
            // Video/Source node is actively streaming (state "running").
            "c=0; lsof /dev/video* 2>/dev/null | grep -vE 'COMMAND|pipewire|wireplumb' | grep -q . && c=1; " +
            "[ \"$c\" = 0 ] && pw-dump 2>/dev/null | jq -e 'any(.[]; .type==\"PipeWire:Interface:Node\" and (.info.props[\"media.class\"]//\"\")==\"Video/Source\" and (.info.state//\"\")==\"running\")' >/dev/null 2>&1 && c=1; " +
            "m=0; [ -n \"$(pactl list short source-outputs 2>/dev/null)\" ] && m=1; " +
            "r=0; pgrep -x gpu-screen-recorder >/dev/null && r=1; " +
            "v=0; pgrep -x wayvnc >/dev/null && v=1; " +
            "h=0; pgrep -x hypridle >/dev/null || h=1; " +
            "f=0; hyprctl workspaces -j 2>/dev/null | jq -e 'any(.[]; .hasfullscreen // false)' >/dev/null 2>&1 && f=1; " +
            "s=$(bash $HOME/.config/scripts/sync-toggle.sh status all 2>/dev/null); " +
            "i=0; echo \"$s\" | grep -q 'immich=1' && i=1; " +
            "j=0; echo \"$s\" | grep -q 'jellyfin=1' && j=1; " +
            "echo \"c$c m$m r$r v$v h$h f$f i$i j$j\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                si.cameraOn      = text.indexOf("c1") >= 0;
                si.micOn         = text.indexOf("m1") >= 0;
                si.recording     = text.indexOf("r1") >= 0;
                si.remoteOn      = text.indexOf("v1") >= 0;
                si.idleHyprOff   = text.indexOf("h1") >= 0;
                si.fullscreenApp = text.indexOf("f1") >= 0;
                si.immichOn      = text.indexOf("i1") >= 0;
                si.jellyfinOn    = text.indexOf("j1") >= 0;
            }
        }
    }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: probe.running = true }

    component Dot: Item {
        id: dot
        property string glyph: ""
        property color tint: Theme.fg
        property bool on: false
        property bool pulse: false
        property string tip: ""
        Layout.fillHeight: true
        implicitWidth: dot.on ? (g.implicitWidth + 14) : 0

        Text {
            id: g
            anchors.centerIn: parent
            visible: dot.on
            text: dot.glyph
            color: dot.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            // Soft blink while recording.
            SequentialAnimation on opacity {
                running: dot.pulse && dot.on
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.35; duration: 750; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 0.35; to: 1.0; duration: 750; easing.type: Easing.InOutQuad }
            }
        }
        HoverHandler { id: dh; enabled: dot.on }
        BarTooltip { bar: si.parentBar; target: dot; text: dot.tip; active: dh.hovered && dot.on }
    }

    // Leading gap + subtle divider so the status cluster reads as a distinct
    // group next to the bell — present only when something is showing.
    Item {
        Layout.fillHeight: true
        implicitWidth: si.anyOn ? 18 : 0
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
    Dot { glyph: "󰋩"; tint: "#f59e0b";           on: si.immichOn;     tip: "Immich photo sync on" }
    Dot { glyph: "󰝚"; tint: "#818cf8";           on: si.jellyfinOn;   tip: "Jellyfin music sync on" }
}
