pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Which backlight devices this machine has, found once by listing sysfs.
// Osd (change detection) and AudioPowerModule (sliders) both build on it, so
// neither hardcodes a vendor's device name.
Singleton {
    id: svc
    // First entry in /sys/class/backlight, "" when there is none.
    property string blDev: ""
    // First keyboard LED under /sys/class/leds, "" when there is none. The
    // name doubles as brightnessctl's --device value.
    property string kbDev: ""

    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight/ 2>/dev/null | head -1; ls /sys/class/leds/ 2>/dev/null | grep -iE 'kbd_backlight|kbd-backlight|keyboard' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                // kbDev first: Osd reacts to blDev changing and reads both.
                svc.kbDev = (lines[1] || "").trim();
                svc.blDev = (lines[0] || "").trim();
            }
        }
    }
}
