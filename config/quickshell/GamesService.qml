// Games for the launchers' Games view: installed Steam games from
// scripts/games.sh (with their cover art, launched through Steam) plus
// desktop apps in the Game category. Instantiated once in shell.qml as games.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    // Steam games shaped like desktop entries, so the launcher rows and
    // filters take them as they are.
    property var steam: []

    function refresh() { if (!proc.running) proc.running = true; }

    // `apps` (DesktopEntries) in the Game category, then Steam's games;
    // a desktop shortcut Steam made for a game it lists is left out.
    function list(apps) {
        const names = steam.map(g => g.name.toLowerCase());
        const desktop = apps.filter(a => (a.categories || []).indexOf("Game") >= 0
            && names.indexOf((a.name || "").toLowerCase()) < 0);
        return desktop.concat(steam);
    }

    function _entry(g) {
        return {
            id: g.id,
            name: g.name,
            genericName: "",
            comment: "Steam",
            icon: "",
            art: g.art || "",
            categories: ["Game"],
            noDisplay: false,
            execute: () => Cmd.run(["steam", "steam://rungameid/" + g.appid]),
        };
    }

    Process {
        id: proc
        command: ["bash", Paths.scripts + "/games.sh", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { svc.steam = JSON.parse(text).map(g => svc._entry(g)); }
                catch (e) { svc.steam = []; }
            }
        }
    }

    Component.onCompleted: refresh()
}
