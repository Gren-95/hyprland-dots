// Alt+Tab window switcher (Mission-Control-ish): grid of large thumbnails,
// type-to-filter, keyboard-first navigation.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

Scope {
    id: root

    property bool open: false
    property var allWindows: []
    property string query: ""
    property int selectedIndex: 0
    property int snapshotToken: 0
    readonly property string thumbDir: "/tmp/qsthumbs"
    readonly property real tileW: 260
    readonly property real tileH: 180

    readonly property var filtered: {
        const q = root.query.toLowerCase();
        if (!q) return root.allWindows;
        return root.allWindows.filter(w =>
            (w.title || "").toLowerCase().includes(q) ||
            (w.klass || "").toLowerCase().includes(q) ||
            (w.workspace || "").toLowerCase().includes(q)
        );
    }

    function openForward()  { _step(1) }
    function openBackward() { _step(-1) }
    function _step(direction) {
        _refresh(() => {
            if (root.allWindows.length === 0) return;
            root.query = "";
            let idx = root.allWindows.findIndex(w => w.focused);
            if (idx < 0) idx = 0;
            root.selectedIndex = ((idx + direction) % root.allWindows.length + root.allWindows.length) % root.allWindows.length;
            // Snapshot first while screen is clean
            snapProc._openAfter = true;
            snapProc.running = true;
        });
    }
    function cycle(dir) {
        const n = root.filtered.length;
        if (n === 0) return;
        root.selectedIndex = (root.selectedIndex + dir + n) % n;
    }
    function jumpTo(idx) { if (idx >= 0 && idx < root.filtered.length) root.selectedIndex = idx; }
    function commit() {
        const w = root.filtered[root.selectedIndex];
        if (w) {
            dispatchProc.command = ["hyprctl", "dispatch", "focuswindow", "address:" + w.address];
            dispatchProc.startDetached();
        }
        close();
    }
    function close() { open = false }
    function _refresh(cb) { listProc._cb = cb || null; listProc.running = true; }

    Process {
        id: listProc
        property var _cb: null
        command: ["hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { return; }
                const f = raw.filter(c => c.mapped && !c.hidden && c.workspace && c.workspace.id >= 0);
                f.sort((a, b) => (a.focusHistoryID || 0) - (b.focusHistoryID || 0));
                root.allWindows = f.map(c => ({
                    address: c.address,
                    title: c.title || "(untitled)",
                    klass: c.class || c.initialClass || "",
                    workspace: c.workspace.name || ("#" + c.workspace.id),
                    workspaceId: c.workspace.id,
                    x: (c.at && c.at[0]) || 0,
                    y: (c.at && c.at[1]) || 0,
                    w: (c.size && c.size[0]) || 0,
                    h: (c.size && c.size[1]) || 0,
                    focused: (c.focusHistoryID || 0) === 0,
                }));
                if (listProc._cb) { listProc._cb(); listProc._cb = null; }
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
        for (const w of root.allWindows) {
            if (!w.address || w.w <= 0 || w.h <= 0) continue;
            const path = root.thumbDir + "/" + w.address + ".png";
            const geo = w.x + "," + w.y + " " + w.w + "x" + w.h;
            s += "grim -g '" + geo + "' '" + path + "' >/dev/null 2>&1 & ";
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
                opacity: 0.55
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Item {
                anchors.fill: parent
                focus: root.open
                Keys.onPressed: (e) => {
                    if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                    else if (e.key === Qt.Key_Tab) {
                        root.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
                    } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        root.cycle(1); e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        root.cycle(-1); e.accepted = true;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        root.cycle(grid.columns); e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        root.cycle(-grid.columns); e.accepted = true;
                    } else if (e.key === Qt.Key_Home) {
                        root.selectedIndex = 0; e.accepted = true;
                    } else if (e.key === Qt.Key_End) {
                        root.selectedIndex = Math.max(0, root.filtered.length - 1); e.accepted = true;
                    } else if (e.modifiers === Qt.NoModifier && e.key === Qt.Key_Backspace) {
                        root.query = root.query.slice(0, -1);
                        root.selectedIndex = 0;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.commit(); e.accepted = true;
                    } else if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32 && (e.modifiers & Qt.ControlModifier) === 0) {
                        root.query += e.text;
                        root.selectedIndex = 0;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 48
                    spacing: 18

                    // Search bar / counter
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        radius: 10
                        color: "#1c1917"
                        border.color: "#3a3633"
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10
                            Text {
                                text: "󰈞"
                                color: "#a8a29e"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 18
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.query || "Type to filter…"
                                color: root.query ? "#fafaf9" : "#57534e"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.filtered.length + " / " + root.allWindows.length
                                color: "#78716c"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 11
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
                            columns: Math.max(1, Math.floor((gridFlick.width - 24) / (root.tileW + 16)))
                            columnSpacing: 16
                            rowSpacing: 16

                            Repeater {
                                model: root.filtered
                                delegate: WinTile {
                                    required property var modelData
                                    required property int index
                                    entry: modelData
                                    highlighted: root.selectedIndex === index
                                    indexLabel: index + 1
                                    snapshotToken: root.snapshotToken
                                    thumbDir: root.thumbDir
                                    onPicked: { root.selectedIndex = index; root.commit(); }
                                    onHovered: root.selectedIndex = index
                                }
                            }
                        }

                        Text {
                            visible: root.filtered.length === 0
                            anchors.centerIn: parent
                            text: root.allWindows.length === 0 ? "No open windows" : "No matches"
                            color: "#57534e"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 13
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Tab cycle  •  arrows / hjkl navigate  •  Enter focus  •  Esc cancel"
                        color: "#57534e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 10
                    }
                }

                // Auto-scroll selected tile into view
                Connections {
                    target: root
                    function onSelectedIndexChanged() {
                        if (grid.columns <= 0) return;
                        const row = Math.floor(root.selectedIndex / grid.columns);
                        const rowH = root.tileH + 38 + grid.rowSpacing;
                        const top = row * rowH;
                        const bottom = top + rowH;
                        if (top < gridFlick.contentY) gridFlick.contentY = top;
                        else if (bottom > gridFlick.contentY + gridFlick.height) {
                            const max = Math.max(0, gridFlick.contentHeight - gridFlick.height);
                            gridFlick.contentY = Math.min(max, bottom - gridFlick.height);
                        }
                    }
                }
            }
        }
    }

    component WinTile: Rectangle {
        id: tile
        property var entry
        property bool highlighted: false
        property int indexLabel: 0
        property int snapshotToken: 0
        property string thumbDir: ""
        signal picked()
        signal hovered()

        implicitWidth: root.tileW
        implicitHeight: root.tileH + 38
        radius: 12
        color: tile.highlighted ? "#332e2b" : "#231f1d"
        border.color: tile.highlighted ? "#a78bfa" : "#3a3633"
        border.width: tile.highlighted ? 2 : 1
        scale: tile.highlighted ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140 } }

        Rectangle {
            id: thumb
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 6
            }
            height: root.tileH
            radius: 8
            color: "#0c0a09"
            border.color: "#3a3633"
            border.width: 1
            clip: true

            Image {
                id: thumbImg
                anchors.fill: parent
                anchors.margins: 1
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                source: tile.entry && tile.thumbDir
                    ? "file://" + tile.thumbDir + "/" + tile.entry.address + ".png?t=" + tile.snapshotToken
                    : ""
                visible: status === Image.Ready
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: 72
                visible: thumbImg.status !== Image.Ready
                source: tile.entry ? Quickshell.iconPath(tile.entry.klass.toLowerCase(), "application-x-executable") : ""
                asynchronous: true
            }
            Rectangle {
                visible: tile.indexLabel >= 1 && tile.indexLabel <= 9
                anchors { top: parent.top; left: parent.left; margins: 6 }
                implicitWidth: 20
                implicitHeight: 20
                radius: 10
                color: tile.highlighted ? "#a78bfa" : "#0a0a0a99"
                Text {
                    anchors.centerIn: parent
                    text: tile.indexLabel
                    color: tile.highlighted ? "#0a0a0a" : "#d6d3d1"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
            // Workspace badge
            Rectangle {
                anchors { top: parent.top; right: parent.right; margins: 6 }
                implicitWidth: wsLabel.implicitWidth + 10
                implicitHeight: 18
                radius: 4
                color: "#0a0a0a99"
                Text {
                    id: wsLabel
                    anchors.centerIn: parent
                    text: tile.entry ? tile.entry.workspace : ""
                    color: "#d6d3d1"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }
            }
        }

        RowLayout {
            anchors {
                bottom: parent.bottom
                left: parent.left
                right: parent.right
                margins: 8
                bottomMargin: 6
            }
            spacing: 8
            IconImage {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                source: tile.entry ? Quickshell.iconPath(tile.entry.klass.toLowerCase(), "application-x-executable") : ""
                asynchronous: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tile.entry ? tile.entry.title : ""
                    color: tile.highlighted ? "#fafaf9" : "#d6d3d1"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.bold: tile.highlighted
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: tile.entry ? tile.entry.klass : ""
                    color: "#78716c"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
            onContainsMouseChanged: if (containsMouse) tile.hovered()
        }
    }
}
