// Screen-recording state + HUD. Wraps ~/.config/scripts/screenrecord.sh —
// polls its pidfile so the UI stays in sync no matter who toggles it
// (bar icon, Super+Ctrl+R, or external runs of the script).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool recording: false
    property real startEpoch: 0
    property real nowEpoch: Date.now() / 1000
    readonly property int elapsedSec: recording ? Math.max(0, Math.floor(nowEpoch - startEpoch)) : 0
    readonly property string elapsed: {
        const s = elapsedSec;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = s % 60;
        const pad = (n) => n < 10 ? "0" + n : "" + n;
        return h > 0 ? h + ":" + pad(m) + ":" + pad(sec) : pad(m) + ":" + pad(sec);
    }

    readonly property string pidfile: "/tmp/screenrecord.pid"
    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"

    function toggle() {
        toggleProc.command = ["bash", root.scriptPath];
        toggleProc.startDetached();
    }
    function stop() {
        // Same as toggle when recording; explicit name for the HUD button
        if (recording) toggle();
    }

    Process { id: toggleProc; command: [] }

    // Tick the displayed elapsed time
    Timer {
        interval: 500
        running: root.recording
        repeat: true
        onTriggered: root.nowEpoch = Date.now() / 1000
    }

    // Poll the pidfile state. Cheap (file stat in shell).
    Process {
        id: pollProc
        running: false
        command: ["sh", "-c",
            "p=" + root.pidfile + "; " +
            "if [ -f \"$p\" ] && kill -0 \"$(cat \"$p\" 2>/dev/null)\" 2>/dev/null; then " +
            "  printf '1 %s' \"$(stat -c %Y \"$p\" 2>/dev/null || echo 0)\"; " +
            "else " +
            "  printf '0 0'; " +
            "fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(/\s+/);
                const alive = parts[0] === "1";
                const started = parseFloat(parts[1] || "0");
                if (alive && !root.recording) {
                    root.startEpoch = started > 0 ? started : (Date.now() / 1000);
                    root.nowEpoch = Date.now() / 1000;
                    root.recording = true;
                } else if (!alive && root.recording) {
                    root.recording = false;
                }
            }
        }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: pollProc.running = true
    }

    // The HUD flashes for ~2s whenever recording starts or stops so the user
    // gets visual confirmation. Outside that window it stays hidden so it
    // doesn't end up in the captured video (`-w screen` is DRM/KMS direct
    // and can't be excluded by Wayland layer rules).
    property bool _showHud: false
    property bool _justStarted: false
    onRecordingChanged: {
        _justStarted = recording;
        _showHud = true;
        flashHide.restart();
    }
    Timer {
        id: flashHide
        interval: 2200
        repeat: false
        onTriggered: root._showHud = false
    }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root._showHud
            color: "transparent"

            anchors { top: true; right: true }
            margins { top: 48; right: 16 }
            implicitWidth: hud.implicitWidth
            implicitHeight: hud.implicitHeight
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: hud
                implicitWidth: hudRow.implicitWidth + 24
                implicitHeight: hudRow.implicitHeight + 14
                radius: 18
                color: "#1c1917"
                border.color: root._justStarted ? "#7f1d1d" : "#3a3633"
                border.width: 1
                opacity: root._showHud ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 180 } }

                RowLayout {
                    id: hudRow
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: 12
                        radius: 6
                        color: root._justStarted ? "#ef4444" : "#22c55e"
                    }

                    Text {
                        text: root._justStarted ? "Recording started" : "Recording saved"
                        color: "#fafaf9"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 18
                        color: "#3a3633"
                        visible: root._justStarted
                    }

                    // Stop button (only while recording)
                    Rectangle {
                        id: stopBtn
                        visible: root._justStarted
                        Layout.preferredWidth: stopText.implicitWidth + 18
                        Layout.preferredHeight: 24
                        radius: 12
                        color: stopMouse.containsMouse ? "#7f1d1d" : "transparent"
                        border.color: "#7f1d1d"
                        border.width: 1
                        Text {
                            id: stopText
                            anchors.centerIn: parent
                            text: "󰓛  Stop"
                            color: stopMouse.containsMouse ? "#fafaf9" : "#f87171"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: stopMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.stop()
                        }
                    }
                }
            }
        }
    }
}
