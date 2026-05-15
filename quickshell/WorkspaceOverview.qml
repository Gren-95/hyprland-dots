// Workspace overview: grid of workspace cards with window thumbnails (via grim
// for visible windows, app icons for windows on hidden workspaces).
// 1-9 jump, h/l/←/→ navigate, Enter activate, Esc cancel.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

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

    function toggle() {
        if (open) close();
        else openOverview();
    }
    function openOverview() {
        refresh(() => {
            const idx = root.workspaces.findIndex(w => w.id === root.activeWs);
            root.focusedIndex = Math.max(0, idx);
            // Snapshot first while the screen is still visible, then show the overlay.
            snapProc._openAfter = true;
            snapshot();
        });
    }
    function close() { open = false }
    function activate(idx) {
        const ws = root.workspaces[idx];
        if (ws) {
            dispatchProc.command = ["hyprctl", "dispatch", "workspace", String(ws.id)];
            dispatchProc.startDetached();
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

    Process { id: dispatchProc; command: [] }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: 0.7
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                anchors.fill: parent
                focus: root.open
                Keys.onPressed: (e) => {
                    const n = root.workspaces.length;
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                    else if (e.key === Qt.Key_Tab) {
                        root.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
                    } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        root.cycle(1); e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        root.cycle(-1); e.accepted = true;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        // Down a row in the grid
                        root.focusedIndex = Math.min(n - 1, root.focusedIndex + grid.columns);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        root.focusedIndex = Math.max(0, root.focusedIndex - grid.columns);
                        e.accepted = true;
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
                    anchors.fill: parent
                    anchors.margins: 56
                    spacing: 18

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 360
                        Layout.preferredHeight: 44
                        radius: 22
                        color: "#1c1917"
                        border.color: "#3a3633"
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            spacing: 10
                            Text {
                                text: "󰍹"
                                color: "#a78bfa"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 18
                            }
                            Text {
                                text: "Workspaces"
                                color: "#fafaf9"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root.workspaces.length + " active"
                                color: "#78716c"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                    }

                    Flickable {
                        id: gridFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: Math.max(height, grid.implicitHeight)
                        clip: true

                        GridLayout {
                            id: grid
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.max(0, (gridFlick.height - implicitHeight) / 2)
                            columns: Math.min(4, Math.max(1, root.workspaces.length))
                            columnSpacing: 20
                            rowSpacing: 20
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

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "1-9 jump  •  ←/h →/l navigate  •  Enter switch  •  Esc cancel"
                        color: "#57534e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
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
        color: ws.highlighted ? "#332e2b" : "#1c1917"
        border.color: ws.highlighted ? "#a78bfa" : (ws.isActive ? "#3b82f6" : "#3a3633")
        border.width: (ws.highlighted || ws.isActive) ? 2 : 1
        scale: ws.highlighted ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

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
            color: ws.isActive ? "#3b82f6" : (ws.highlighted ? "#a78bfa" : "#3a3633")
            z: 5
            Text {
                anchors.centerIn: parent
                text: ws.workspace ? ws.workspace.name.replace(/^#/, "") : ""
                color: (ws.isActive || ws.highlighted) ? "#0a0a0a" : "#d6d3d1"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
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
            border.color: "#3a3633"
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
                        color: modelData.focused ? "#1e293b" : "#1c1917"
                        border.color: modelData.focused ? "#3b82f6" : "#3a3633"
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
                                color: "#fafaf9"
                                font.family: "FiraCode Nerd Font"
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
                color: "#3a3633"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
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
            spacing: 6

            Text {
                visible: ws.isActive
                text: "●"
                color: "#3b82f6"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
            }
            Text {
                Layout.fillWidth: true
                text: ws.workspace
                    ? ws.workspace.windowCount + (ws.workspace.windowCount === 1 ? " window" : " windows")
                    : ""
                color: ws.highlighted ? "#fafaf9" : "#a8a29e"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
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
