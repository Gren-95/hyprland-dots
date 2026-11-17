// One tab of the Icons & cursors popup: the themes a script lists, which of
// them are in use, and applying one. The script answers `list` (JSON array of
// {id, name, comment, samples, ...}), `get` and `set <id>`; scripts/
// icon-theme.sh and scripts/cursor-theme.sh both do.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: src

    // Script name under Paths.scripts.
    property string script: ""
    // settingsStore property holding the recently applied ids, newest first.
    property string recentsSetting: ""
    // Turns the output of `get` into {themeId: badge text} for every theme
    // in use.
    property var parseGet: text => ({})

    // As listed. Kept for the session: listing can take seconds.
    property var listed: []
    property bool loading: false
    property var inUse: ({})
    // Theme being applied; its row shows a spinner until `set` returns.
    property string applying: ""

    // Shown order: recently applied themes first, then the rest by name.
    readonly property var themes: {
        const recents = settingsStore[recentsSetting] || [];
        const rank = t => { const i = recents.indexOf(t.id); return i < 0 ? recents.length : i; };
        return listed.slice().sort((a, b) => rank(a) - rank(b)
                                    || a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
    }

    // Index of the first theme in use, for the initial keyboard cursor.
    function currentIndex() {
        return Math.max(0, themes.findIndex(t => inUse[t.id] !== undefined));
    }

    function load() {
        if (listed.length === 0 && !loading) {
            loading = true;
            listProc.running = true;
        }
        getProc.running = true;
    }

    function apply(theme) {
        if (!theme || applying !== "") return;
        applying = theme.id;
        setProc.command = ["bash", Paths.scripts + "/" + script, "set", theme.id];
        setProc.running = true;
    }

    Process {
        id: listProc
        command: ["bash", Paths.scripts + "/" + src.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    src.listed = JSON.parse(text);
                } catch (e) {
                    console.warn("ThemeSource:", src.script, "list:", e);
                    src.listed = [];
                }
                src.loading = false;
            }
        }
    }
    Process {
        id: getProc
        command: ["bash", Paths.scripts + "/" + src.script, "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    src.inUse = src.parseGet(text);
                } catch (e) {
                    console.warn("ThemeSource:", src.script, "get:", e);
                }
            }
        }
    }
    Process {
        id: setProc
        onExited: (code) => {
            if (code === 0) {
                // Record the themes being left too, so the first switch
                // already puts them at the top.
                const ids = [src.applying].concat(Object.keys(src.inUse), settingsStore[src.recentsSetting] || []);
                settingsStore[src.recentsSetting] = ids.filter((id, i) => id !== "" && ids.indexOf(id) === i);
                getProc.running = true;
            } else {
                console.warn("ThemeSource:", src.script, "set exited with", code);
            }
            src.applying = "";
        }
    }
}
