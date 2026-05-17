pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    Process { id: dispatchProc; command: [] }
    function dispatch(...args) {
        dispatchProc.command = ["hyprctl", "dispatch"].concat(args);
        dispatchProc.startDetached();
    }
    function execute(cmd) {
        dispatchProc.command = ["hyprctl", "dispatch", "exec", cmd];
        dispatchProc.startDetached();
    }
}
