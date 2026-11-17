// Gives Hyprland's focused-window border the shell's accent colour: a
// gradient from Theme.accentPrimary to a lighter tint of it, the same shape as
// the static orange -> yellow default in hypr/modules/general.lua. Applied
// with `hyprctl eval` whenever the accent changes (including the "auto"
// accent taken from the wallpaper), and again after a Hyprland config reload,
// which brings back the default from general.lua.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: border

    // "rgba(rrggbbaa)" for Hyprland, slightly transparent like the default.
    function _hypr(c) {
        return "rgba(" + c.toString().slice(1) + "ee)";
    }

    function apply() {
        const from = border._hypr(Theme.accentPrimary);
        const to = border._hypr(Qt.lighter(Theme.accentPrimary, 1.35));
        applyProc.command = ["hyprctl", "eval",
            "hl.config({ general = { col = { active_border = { colors = {\"" + from + "\", \"" + to + "\"}, angle = 45 } } } })"];
        applyProc.running = false;
        applyProc.running = true;
    }

    // Accent changes arrive in bursts (name, then the auto hex); apply once.
    Timer { id: debounce; interval: 150; onTriggered: border.apply() }
    Connections {
        target: Theme
        function onAccentPrimaryChanged() { debounce.restart(); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") debounce.restart();
        }
    }
    Component.onCompleted: debounce.restart()

    Process {
        id: applyProc
        onExited: (code) => { if (code !== 0) console.warn("HyprBorder: hyprctl eval exited with", code); }
    }
}
