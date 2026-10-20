// Game mode state. scripts/gamemode.sh owns the mode and writes
// $XDG_RUNTIME_DIR/gamemode ("off" or "on <previous profile>"); this watches
// that file so the bar hides and Do Not Disturb turns on, whichever way the
// mode was toggled (keybind, script, or the launcher action below).
// Instantiated once in shell.qml as gameMode.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    // The Notifications service, handed in by shell.qml.
    property var notifs: null

    property bool active: false
    // Do Not Disturb as the user had it before game mode switched it on.
    property bool _dndBefore: false

    function toggle() {
        Cmd.run(["bash", Paths.scripts + "/gamemode.sh", "toggle"]);
    }

    onActiveChanged: {
        if (!notifs) return;
        if (active) {
            _dndBefore = notifs.dnd;
            notifs.dnd = true;
        } else {
            notifs.dnd = _dndBefore;
        }
    }

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/gamemode"
        watchChanges: true
        onLoaded: svc.active = text().trim().startsWith("on")
        onFileChanged: reload()
        // First boot: the script has not written the file yet. Create it so
        // there is something to watch.
        onLoadFailed: setText("off\n")
    }
}
