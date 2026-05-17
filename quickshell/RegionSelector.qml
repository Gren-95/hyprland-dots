// Quickshell-native region picker — replaces slurp for screenshot region
// selection. Full-screen overlay per monitor; click-drag to select, live
// dimensions readout; Esc cancels; releasing the mouse with a non-trivial
// selection invokes screenshot.sh with the resulting "X,Y WxH" string.
//
// Bound to Super+Shift+S via a GlobalShortcut in shell.qml.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool active: false
    // Selection in global Hyprland coordinates (across all monitors).
    property real startX: 0
    property real startY: 0
    property real curX: 0
    property real curY: 0
    property bool dragging: false

    readonly property real selX:  Math.min(startX, curX)
    readonly property real selY:  Math.min(startY, curY)
    readonly property real selW:  Math.abs(curX - startX)
    readonly property real selH:  Math.abs(curY - startY)

    function start() {
        startX = 0; startY = 0; curX = 0; curY = 0;
        dragging = false;
        active = true;
    }
    function cancel() { active = false; dragging = false; }
    function commit() {
        if (selW < 5 || selH < 5) { cancel(); return; }
        const region = Math.round(selX) + "," + Math.round(selY) + " "
                     + Math.round(selW) + "x" + Math.round(selH);
        captureProc.command = ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh", region];
        captureProc.running = true;
        cancel();
    }

    // Capture stdout (the saved path) so we can hand it to the
    // ScreenshotActions modal once the file is on disk.
    Process {
        id: captureProc
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim();
                if (path) screenshotActions.show(path);
            }
        }
    }

    // One overlay per screen. Each translates local mouse coords to global
    // Hyprland coords using its screen.x / screen.y offset.
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: root.active
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.None

            readonly property int ox: modelData.x
            readonly property int oy: modelData.y

            // Dim everything except the selection rectangle. We draw 4
            // dim rects (top/left/right/bottom of selection) instead of
            // one full-screen dim with a "cutout" because QML has no
            // composite-subtract primitive.
            Rectangle {
                // Top dim
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: Math.max(0, root.selY - overlay.oy)
                color: "#80000000"
                visible: root.dragging
            }
            Rectangle {
                // Bottom dim
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Math.max(0, (overlay.height + overlay.oy) - (root.selY + root.selH))
                color: "#80000000"
                visible: root.dragging
            }
            Rectangle {
                // Left dim
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: Math.max(0, root.selX - overlay.ox)
                color: "#80000000"
                visible: root.dragging
            }
            Rectangle {
                // Right dim
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: Math.max(0, (overlay.width + overlay.ox) - (root.selX + root.selW))
                color: "#80000000"
                visible: root.dragging
            }
            // Idle dim (whole screen) before drag starts.
            Rectangle {
                anchors.fill: parent
                color: "#66000000"
                visible: !root.dragging
            }

            // Selection outline.
            Rectangle {
                visible: root.dragging
                x: root.selX - overlay.ox
                y: root.selY - overlay.oy
                width: root.selW
                height: root.selH
                color: "transparent"
                border.color: "#3b82f6"
                border.width: 2
            }

            // Dimensions tooltip — anchored just below the selection,
            // flipped above if it would clip off-screen.
            Rectangle {
                visible: root.dragging && root.selW > 0
                x: Math.min(overlay.width - implicitWidth - 6,
                            Math.max(6, (root.selX - overlay.ox) + root.selW - implicitWidth))
                y: {
                    const below = (root.selY - overlay.oy) + root.selH + 6;
                    return below + implicitHeight < overlay.height
                        ? below
                        : (root.selY - overlay.oy) - implicitHeight - 6;
                }
                implicitWidth: dimText.implicitWidth + 14
                implicitHeight: dimText.implicitHeight + 8
                radius: 6
                color: "#dd000000"
                border.color: "#3b82f6"
                border.width: 1
                Text {
                    id: dimText
                    anchors.centerIn: parent
                    text: Math.round(root.selW) + " × " + Math.round(root.selH)
                    color: "#f5f5f4"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: true
                }
            }

            // Hint text shown before drag begins.
            Text {
                visible: !root.dragging
                anchors.centerIn: parent
                text: "Click and drag to select region · Esc to cancel"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
                font.bold: true
            }

            FocusScope {
                anchors.fill: parent
                focus: root.active
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.cancel(); e.accepted = true; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.commit(); e.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: (e) => {
                        if (e.button === Qt.RightButton) { root.cancel(); return; }
                        root.startX = e.x + overlay.ox;
                        root.startY = e.y + overlay.oy;
                        root.curX = root.startX;
                        root.curY = root.startY;
                        root.dragging = true;
                    }
                    onPositionChanged: (e) => {
                        if (root.dragging) {
                            root.curX = e.x + overlay.ox;
                            root.curY = e.y + overlay.oy;
                        }
                    }
                    onReleased: { if (root.dragging) root.commit(); }
                }
            }
        }
    }
}
