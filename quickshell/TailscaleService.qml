pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: svc
    property string state: ""        // "Running" | "Stopped" | "NoState" | ""
    property string tailnet: ""
    property string host: ""
    property var    selfIPs: []
    property var    peers: []
    property string exitNodeId: ""
    readonly property bool daemonOk: state !== ""
    readonly property bool running: state === "Running"

    function refresh() { if (!proc.running) proc.running = true; }
    function toggle() {
        cmd.command = ["tailscale", running ? "down" : "up"];
        cmd.startDetached();
        refreshAfter.restart();
    }
    function setExitNode(id) {
        cmd.command = ["tailscale", "set", "--exit-node=" + (id || "")];
        cmd.startDetached();
        refreshAfter.restart();
    }
    function copyIp(ip) { copy.command = ["wl-copy", ip]; copy.startDetached(); }

    Process {
        id: proc
        command: ["tailscale", "status", "--json"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { svc.state = ""; return; }
                svc.state = raw.BackendState || "Stopped";
                svc.tailnet = raw.CurrentTailnet ? (raw.CurrentTailnet.Name || "") : "";
                if (raw.Self) {
                    svc.host = raw.Self.HostName || "";
                    svc.selfIPs = raw.Self.TailscaleIPs || [];
                } else { svc.host = ""; svc.selfIPs = []; }
                const pl = [];
                const po = raw.Peer || {};
                for (const k in po) {
                    const p = po[k];
                    pl.push({
                        id: k, host: p.HostName || "",
                        dns: (p.DNSName || "").replace(/\.$/, ""),
                        ips: p.TailscaleIPs || [],
                        online: !!p.Online,
                        exitNodeOption: !!p.ExitNodeOption,
                        exitNode: !!p.ExitNode,
                    });
                }
                pl.sort((a, b) => a.online !== b.online ? (a.online ? -1 : 1) : a.host.localeCompare(b.host));
                svc.peers = pl;
                svc.exitNodeId = "";
                for (const p of pl) if (p.exitNode) { svc.exitNodeId = p.id; break; }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.indexOf("doesn't appear to be running") >= 0) svc.state = "";
            }
        }
    }
    Process { id: cmd; command: [] }
    Process { id: copy; command: [] }
    Timer { id: refreshAfter; interval: 800; repeat: false; onTriggered: svc.refresh() }
    Timer { running: true; interval: 15000; repeat: true; triggeredOnStart: true; onTriggered: svc.refresh() }
}
