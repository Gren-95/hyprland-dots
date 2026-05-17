// Persisted user preferences. Singleton so any component can bind to a flag
// and toggling propagates everywhere. Values are stored as one tiny file per
// flag under ~/.cache/quickshell — keeps the persistence layer trivial and
// avoids the JSON-escape dance via shell.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: settings

    // ===== Flags =====
    property bool mediaKeysVisible: false

    // ===== Internals =====
    // Saving is skipped while `loaded` is false so the initial assignment
    // from the file watcher doesn't bounce back through Process.
    property bool loaded: false

    Process { id: saveProc; command: [] }

    function _save(filename, val) {
        if (!loaded) return;
        const v = val ? "1" : "0";
        saveProc.command = ["sh", "-c",
            "mkdir -p ~/.cache/quickshell && echo " + v + " > ~/.cache/quickshell/" + filename];
        saveProc.startDetached();
    }

    onMediaKeysVisibleChanged: _save("media-keys.enabled", mediaKeysVisible)

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/media-keys.enabled"
        watchChanges: true
        onLoaded: {
            settings.mediaKeysVisible = text().trim() === "1";
            settings.loaded = true;
        }
        onFileChanged: reload()
    }

    Component.onCompleted: {
        // If the file doesn't exist yet, loaded never fires — flip it on
        // after a short delay so toggles save properly.
        loadedTimer.start();
    }
    Timer {
        id: loadedTimer
        interval: 200
        onTriggered: settings.loaded = true
    }
}
