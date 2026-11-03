// State of the things only our own toggles change: WayVNC remote access and
// the Immich / Jellyfin sync schedules. wayvnc-toggle.sh and sync-toggle.sh
// call `qs ipc call status refresh` when they finish, so the bar dots follow
// at once; the slow poll only recovers from changes made outside them.
// Instantiated once in shell.qml as remoteSyncStatus.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    property bool remoteOn: false
    property bool immichOn: false        // Immich sync schedule enabled
    property bool jellyfinOn: false      // Jellyfin sync schedule enabled

    function refresh() { settle.restart(); }

    IpcHandler {
        target: "status"
        function refresh(): void { svc.refresh(); }
    }

    // A toggle script may still be winding down when it calls refresh().
    Timer { id: settle; interval: 600; onTriggered: probe.running = true }

    Process {
        id: probe
        command: ["sh", "-c",
            "v=0; pgrep -x wayvnc >/dev/null && v=1; " +
            "s=$(bash $HOME/.config/scripts/sync-toggle.sh status all 2>/dev/null); " +
            "i=0; echo \"$s\" | grep -q 'immich=1' && i=1; " +
            "j=0; echo \"$s\" | grep -q 'jellyfin=1' && j=1; " +
            "echo \"v$v i$i j$j\""]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                svc.remoteOn  = text.indexOf("v1") >= 0;
                svc.immichOn  = text.indexOf("i1") >= 0;
                svc.jellyfinOn = text.indexOf("j1") >= 0;
            }
        }
    }
    Timer {
        running: !gameMode.active
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
}
