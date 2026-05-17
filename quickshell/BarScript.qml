import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: bs
    property string scriptName: ""
    property int intervalMs: 5000
    property string onClickArg: ""
    property string onMiddleClickArg: ""
    property string onScrollUpArg: ""
    property string onScrollDownArg: ""
    property var onClickCmd: null
    Layout.fillHeight: true
    implicitWidth: txt.implicitWidth + 12

    property string display: ""
    property string klass: ""
    property string tip: ""

    Text {
        id: txt
        anchors.centerIn: parent
        text: bs.display
        color: bs.colorForClass(bs.klass)
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.md
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (e) => {
            if (e.button === Qt.MiddleButton && bs.onMiddleClickArg !== "")
                bs.run(bs.onMiddleClickArg);
            else if (bs.onClickCmd)
                bs.runCmd(bs.onClickCmd);
            else if (bs.onClickArg !== "")
                bs.run(bs.onClickArg);
        }
        onWheel: (e) => {
            const arg = e.angleDelta.y > 0 ? bs.onScrollUpArg : bs.onScrollDownArg;
            if (arg !== "") bs.run(arg);
        }
    }

    Process {
        id: poller
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/" + bs.scriptName]
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    const j = JSON.parse(line);
                    bs.display = j.text || "";
                    bs.klass = j.class || "";
                    bs.tip = j.tooltip || "";
                } catch (_) {
                    bs.display = line.trim();
                }
            }
        }
    }
    Timer {
        interval: bs.intervalMs; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!poller.running) poller.running = true; }
    }

    function run(arg) {
        const p = Qt.createQmlObject(
            "import Quickshell.Io; Process {}", bs);
        p.command = ["bash", Quickshell.env("HOME") + "/.config/scripts/" + bs.scriptName, arg];
        p.startDetached();
    }
    function runCmd(cmd) {
        const p = Qt.createQmlObject(
            "import Quickshell.Io; Process {}", bs);
        p.command = cmd;
        p.startDetached();
    }
    function colorForClass(c) {
        switch (c) {
            case "connected":   return "#60a5fa";
            case "disconnected":return Theme.mutedDeep;
            case "immich":      return "#f59e0b";
            case "jellyfin":    return "#818cf8";
            case "dnd":         return Theme.accent.orange;
            case "idle-on":     return Theme.accent.green;
            case "idle-off":    return Theme.mutedDeep;
            case "colorpicker": return "#e879f9";
            case "clipboard":   return Theme.accent.slate;
            default:            return "#f5f5f4";
        }
    }
}
