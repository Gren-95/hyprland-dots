// Gives Hyprland's focused-window border its colour: the shell's accent
// (Theme.accentPrimary) or a fixed colour, as chosen in the settings app
// (Windows, Focused window border). With the gradient on it fades to a
// lighter tint of the colour at the chosen angle, the same shape as the
// static orange -> yellow default in hypr/modules/general.lua; off, it is one
// colour. Applied with `hyprctl eval` whenever the colour or the accent
// changes (including the "auto" accent taken from the wallpaper), and again
// after a Hyprland config reload, which brings back the default from
// general.lua.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
    id: border

    // "accent" or a Theme.base colour name (border-colour).
    property string colourName: "accent"
    property bool gradient: true
    property int angle: 45

    readonly property color colour: colourName === "accent" || Theme.base[colourName] === undefined
        ? Theme.accentPrimary : Theme.base[colourName]

    // "rgba(rrggbbaa)" for Hyprland, slightly transparent like the default.
    function _hypr(c) {
        return "rgba(" + c.toString().slice(1) + "ee)";
    }

    function apply() {
        const from = "\"" + border._hypr(border.colour) + "\"";
        const value = border.gradient
            ? "{ colors = {" + from + ", \"" + border._hypr(Qt.lighter(border.colour, 1.35)) + "\"}, angle = " + border.angle + " }"
            : from;
        applyProc.command = ["hyprctl", "eval",
            "hl.config({ general = { col = { active_border = " + value + " } } })"];
        applyProc.running = false;
        applyProc.running = true;
    }

    // Accent changes arrive in bursts (name, then the auto hex); apply once.
    Timer { id: debounce; interval: 150; onTriggered: border.apply() }
    onColourChanged: debounce.restart()
    onGradientChanged: debounce.restart()
    onAngleChanged: debounce.restart()
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
