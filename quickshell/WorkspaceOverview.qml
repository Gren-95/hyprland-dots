// Workspace overview: top drawer strip of workspace cards with window
// thumbnails (via grim for visible windows, app icons for windows on hidden
// workspaces). 1-9 jump, h/l/←/→ navigate, Enter activate, Esc cancel.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property var workspaces: []
    property int activeWs: 0
    property int focusedIndex: 0
    property real monW: 1920
    property real monH: 1200
    property var visibleWsIds: []
    property int snapshotToken: 0
    readonly property string thumbDir: "/tmp/qsthumbs"
    readonly property real cardWidth: 320

    // Super+Tab cycling: opens overlay on first press, cycles on each subsequent
    // Super+Tab. The held-Super tracker commits on Super release.
    function cycleOrOpen(direction) {
        if (open) { cycle(direction); return; }
        refresh(() => {
            const n = root.workspaces.length;
            if (n === 0) return;
            const idx = root.workspaces.findIndex(w => w.id === root.activeWs);
            root.focusedIndex = ((idx + direction) % n + n) % n;
            snapProc._openAfter = true;
            snapshot();
        });
    }
    function commitIfOpen() { if (open) activate(focusedIndex); }
    function close() { open = false }
    function activate(idx) {
        const ws = root.workspaces[idx];
        if (ws) {
            Hypr.dispatch("workspace", String(ws.id));
        }
        close();
    }
    function activateById(wsId) {
        const idx = root.workspaces.findIndex(w => w.id === wsId);
        if (idx >= 0) activate(idx);
    }
    function cycle(dir) {
        const n = root.workspaces.length;
        if (n === 0) return;
        root.focusedIndex = (root.focusedIndex + dir + n) % n;
    }
    function refresh(cb) { gatherProc._cb = cb || null; gatherProc.running = true; }
    function snapshot() { snapProc.running = true }

    Process {
        id: gatherProc
        property var _cb: null
        command: ["sh", "-c", "echo '['; hyprctl monitors -j; echo ','; hyprctl workspaces -j; echo ','; hyprctl clients -j; echo ']'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { return; }
                const monitors = raw[0] || [];
                const wss = raw[1] || [];
                const clients = raw[2] || [];

                const mon = monitors.find(m => m.focused) || monitors[0];
                if (mon) {
                    root.monW = mon.width;
                    root.monH = mon.height;
                    root.activeWs = mon.activeWorkspace ? mon.activeWorkspace.id : 0;
                }
                const visIds = monitors
                    .filter(m => m.activeWorkspace)
                    .map(m => m.activeWorkspace.id);
                root.visibleWsIds = visIds;

                wss.sort((a, b) => a.id - b.id);
                root.workspaces = wss.filter(w => w.id > 0).map(w => ({
                    id: w.id,
                    name: w.name || ("#" + w.id),
                    windowCount: w.windows,
                    isVisible: visIds.indexOf(w.id) !== -1,
                    windows: clients
                        .filter(c => c.workspace && c.workspace.id === w.id && c.mapped && !c.hidden)
                        .map(c => ({
                            address: c.address,
                            title: c.title || "",
                            klass: c.class || c.initialClass || "",
                            x: (c.at && c.at[0]) || 0,
                            y: (c.at && c.at[1]) || 0,
                            w: (c.size && c.size[0]) || 100,
                            h: (c.size && c.size[1]) || 100,
                            focused: (c.focusHistoryID || 0) === 0,
                            wsVisible: visIds.indexOf(c.workspace.id) !== -1,
                        })),
                }));
                if (gatherProc._cb) { gatherProc._cb(); gatherProc._cb = null; }
            }
        }
    }

    Process {
        id: snapProc
        property bool _openAfter: false
        running: false
        command: ["sh", "-c", root._snapScript()]
        onExited: {
            if (_openAfter) {
                _openAfter = false;
                root.snapshotToken += 1;
                root.open = true;
            }
        }
    }
    function _snapScript() {
        let s = "mkdir -p " + root.thumbDir + "; ";
        for (const ws of root.workspaces) {
            if (!ws.isVisible) continue;
            for (const w of ws.windows) {
                if (!w.address || w.w <= 0 || w.h <= 0) continue;
                const path = root.thumbDir + "/" + w.address + ".png";
                const geo = w.x + "," + w.y + " " + w.w + "x" + w.h;
                s += "grim -g '" + geo + "' '" + path + "' >/dev/null 2>&1 & ";
            }
        }
        s += "wait";
        return s;
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"

            // Top drawer: full-width strip of workspace cards hanging under
            // the bar (Task-View style), replacing the fullscreen grid.
            anchors { top: true; left: true; right: true }
            margins { top: 36 }
            implicitHeight: drawer.implicitHeight
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Click-away close (the old fullscreen backdrop is gone).
            HyprlandFocusGrab {
                active: root.open
                windows: [win]
                onCleared: root.close()
            }

            Rectangle {
                id: drawer
                anchors.fill: parent
                implicitHeight: drawerCol.implicitHeight + 2 * Theme.spacing.lg
                color: Theme.bgAlt
                focus: root.open
                scale: root.open ? 1.0 : 0.96
                opacity: root.open ? 1.0 : 0.0
                transformOrigin: Item.Top
                Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

                // Bottom hairline matching the bar's.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.mutedDeep
                }

                Keys.onPressed: (e) => {
                    const n = root.workspaces.length;
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                    else if (e.key === Qt.Key_Tab) {
                        root.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
                    } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L
                            || e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        root.cycle(1); e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H
                            || e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        root.cycle(-1); e.accepted = true;
                    } else if (e.key === Qt.Key_Home) {
                        root.focusedIndex = 0; e.accepted = true;
                    } else if (e.key === Qt.Key_End) {
                        root.focusedIndex = Math.max(0, n - 1); e.accepted = true;
                    } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                        // Jump to that workspace id (or that visible index if id doesn't exist)
                        const target = e.key - Qt.Key_0;
                        const wsIdx = root.workspaces.findIndex(w => w.id === target);
                        if (wsIdx >= 0) {
                            root.focusedIndex = wsIdx;
                            root.activate(wsIdx);
                        }
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                        root.activate(root.focusedIndex); e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: drawerCol
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: Theme.spacing.lg
                    spacing: Theme.spacing.md

                    // Slim header row: title on the left, hint on the right.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.md
                        Text {
                            text: "󰍹"
                            color: Theme.accent.purple
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xl
                        }
                        Text {
                            text: "Workspaces"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                            font.bold: true
                        }
                        Text {
                            text: root.workspaces.length + " active"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "1-9 jump  •  ←/h →/l navigate  •  Enter switch  •  Esc cancel"
                            color: Theme.disabled
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }

                    // Horizontal card strip; scrolls when workspaces overflow,
                    // centers when they don't.
                    Flickable {
                        id: stripFlick
                        Layout.fillWidth: true
                        Layout.preferredHeight: strip.implicitHeight
                        contentWidth: Math.max(width, strip.implicitWidth)
                        contentHeight: strip.implicitHeight
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        RowLayout {
                            id: strip
                            x: Math.max(0, (stripFlick.width - implicitWidth) / 2)
                            spacing: Theme.spacing.xl
                            Repeater {
                                model: root.workspaces
                                delegate: WsCard {
                                    required property var modelData
                                    required property int index
                                    workspace: modelData
                                    highlighted: root.focusedIndex === index
                                    isActive: modelData.id === root.activeWs
                                    monW: root.monW
                                    monH: root.monH
                                    snapshotToken: root.snapshotToken
                                    thumbDir: root.thumbDir
                                    onPicked: root.activate(index)
                                    onHovered: root.focusedIndex = index
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component WsCard: Rectangle {
        id: ws
        property var workspace
        property bool highlighted: false
        property bool isActive: false
        property real monW: 1920
        property real monH: 1200
        property int snapshotToken: 0
        property string thumbDir: ""
        signal picked()
        signal hovered()

        readonly property real previewH: root.cardWidth * (monH / monW)
        implicitWidth: root.cardWidth
        implicitHeight: previewH + 38
        radius: 12
        color: ws.highlighted ? Theme.bgActive : Theme.bg
        border.color: ws.highlighted ? Theme.accent.purple : (ws.isActive ? Theme.accent.blue : Theme.border)
        border.width: (ws.highlighted || ws.isActive) ? 2 : 1
        scale: ws.highlighted ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

        // Workspace ID badge
        Rectangle {
            anchors {
                top: parent.top
                left: parent.left
                margins: 6
            }
            implicitWidth: 22
            implicitHeight: 22
            radius: 11
            color: ws.isActive ? Theme.accent.blue : (ws.highlighted ? Theme.accent.purple : Theme.border)
            z: 5
            Text {
                anchors.centerIn: parent
                text: ws.workspace ? ws.workspace.name.replace(/^#/, "") : ""
                color: (ws.isActive || ws.highlighted) ? "#0a0a0a" : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: true
            }
        }

        Rectangle {
            id: previewArea
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 6
            }
            height: ws.previewH - 12
            radius: 6
            color: "#0c0a09"
            border.color: Theme.border
            border.width: 1
            clip: true

            Repeater {
                model: ws.workspace ? ws.workspace.windows : []
                delegate: Item {
                    required property var modelData
                    readonly property real sx: previewArea.width / Math.max(1, ws.monW)
                    readonly property real sy: previewArea.height / Math.max(1, ws.monH)
                    x: modelData.x * sx
                    y: modelData.y * sy
                    width: Math.max(8, modelData.w * sx)
                    height: Math.max(6, modelData.h * sy)

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: modelData.focused ? "#1e293b" : Theme.bg
                        border.color: modelData.focused ? Theme.accent.blue : Theme.border
                        border.width: 1
                        clip: true

                        // Window thumbnail
                        Image {
                            id: winThumb
                            anchors.fill: parent
                            anchors.margins: 1
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            source: modelData.wsVisible && ws.thumbDir
                                ? "file://" + ws.thumbDir + "/" + modelData.address + ".png?t=" + ws.snapshotToken
                                : ""
                            visible: status === Image.Ready
                            opacity: modelData.focused ? 1.0 : 0.7
                        }

                        // Icon fallback for off-screen workspaces
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: Math.min(parent.width * 0.5, parent.height * 0.6, 32)
                            visible: winThumb.status !== Image.Ready
                            source: modelData.klass
                                ? Quickshell.iconPath(modelData.klass.toLowerCase(), "application-x-executable")
                                : ""
                            asynchronous: true
                            opacity: modelData.focused ? 1.0 : 0.75
                        }

                        // Class label in corner
                        Rectangle {
                            anchors {
                                bottom: parent.bottom
                                left: parent.left
                                margins: 2
                            }
                            visible: parent.width > 60
                            implicitWidth: lbl.implicitWidth + 6
                            implicitHeight: lbl.implicitHeight + 2
                            radius: 2
                            color: "#000000aa"
                            Text {
                                id: lbl
                                anchors.centerIn: parent
                                text: modelData.klass
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: 8
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Text {
                visible: ws.workspace && ws.workspace.windows.length === 0
                anchors.centerIn: parent
                text: "empty"
                color: Theme.border
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
        }

        // Footer: window count + active marker
        RowLayout {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: 8
                bottomMargin: 7
            }
            spacing: Theme.spacing.sm

            Text {
                visible: ws.isActive
                text: "●"
                color: Theme.accent.blue
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
            }
            Text {
                Layout.fillWidth: true
                text: ws.workspace
                    ? ws.workspace.windowCount + (ws.workspace.windowCount === 1 ? " window" : " windows")
                    : ""
                color: ws.highlighted ? Theme.fg : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: ws.highlighted
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ws.picked()
            onContainsMouseChanged: if (containsMouse) ws.hovered()
        }
    }
}
