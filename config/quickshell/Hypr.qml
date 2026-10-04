pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Since Hyprland 0.55 (Lua config), `hyprctl dispatch` takes a Lua
// dispatcher expression — old-style "dispatch exec foo" args error out.
Singleton {
    Process { id: dispatchProc; command: [] }
    // Run a raw Lua dispatcher expression, e.g. "hl.dsp.focus({ workspace = 3 })"
    function dispatch(luaExpr) {
        dispatchProc.command = ["hyprctl", "dispatch", luaExpr];
        dispatchProc.startDetached();
    }
    function focusWorkspace(id) {
        dispatch("hl.dsp.focus({ workspace = " + Number(id) + " })");
    }
    function execute(cmd) {
        dispatch("hl.dsp.exec_cmd('" + String(cmd).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "')");
    }
}
