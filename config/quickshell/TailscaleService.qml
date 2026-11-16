pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Read-only Tailscale status for the "VPN up/down" toasts. Control lives in
// nm-applet, through the NetworkManager Tailscale VPN plugin.
Singleton {
    id: svc
    property string state: ""        // "Running" | "Stopped" | "NoState" | ""
    property string tailnet: ""
    readonly property bool running: state === "Running"
    // Set from shell.qml while game mode is on: polling stops, and a refresh
    // on the way out of game mode catches any change made meanwhile.
    property bool paused: false
    onPausedChanged: if (!paused) refresh()

    function refresh() { if (!proc.running) proc.running = true; }

    Process {
        id: proc
        command: ["tailscale", "status", "--json", "--peers=false"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { svc.state = ""; return; }
                svc.state = raw.BackendState || "Stopped";
                svc.tailnet = raw.CurrentTailnet ? (raw.CurrentTailnet.Name || "") : "";
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.indexOf("doesn't appear to be running") >= 0) svc.state = "";
            }
        }
    }
    Timer { running: !svc.paused; interval: 15000; repeat: true; triggeredOnStart: true; onTriggered: svc.refresh() }
}
