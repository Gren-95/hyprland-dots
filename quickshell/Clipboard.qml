// Clipboard history selector styled like Spotlight: full-screen dim backdrop,
// centered search card listing cliphist entries (with thumbnails for images
// and swatches for hex colors).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0
    property var items: []

    readonly property string thumbDir: "/tmp/cliphist-thumbs"

    readonly property var filtered: {
        const q = root.query.toLowerCase();
        if (!q) return root.items;
        return root.items.filter(i => i.preview.toLowerCase().includes(q));
    }

    readonly property int rowSpacing: 2
    function _rowHeight(item) { return item && item.isImage ? 76 : 44; }
    function _rowYAt(idx) {
        let y = 0;
        for (let i = 0; i < idx && i < filtered.length; i++) {
            y += _rowHeight(filtered[i]) + rowSpacing;
        }
        return y;
    }
    signal scrollRequested(int top, int bottom)
    onSelectedIndexChanged: {
        if (selectedIndex < 0 || selectedIndex >= filtered.length) return;
        const top = _rowYAt(selectedIndex);
        const bottom = top + _rowHeight(filtered[selectedIndex]);
        scrollRequested(top, bottom);
    }

    function _parseEntry(line) {
        const tab = line.indexOf("\t");
        const id = tab < 0 ? line : line.slice(0, tab);
        const preview = tab < 0 ? line : line.slice(tab + 1);
        const m = preview.match(/^\[\[\s*binary data\s+([^\s]+\s+[^\s]+)\s+(png|jpe?g|gif|bmp|webp|tiff|svg)(?:\s+(\d+x\d+))?\s*\]\]$/i);
        if (m) {
            return {
                id: id,
                preview: preview,
                raw: line,
                isImage: true,
                ext: m[2].toLowerCase().replace("jpeg", "jpg"),
                size: m[1],
                dims: m[3] || "",
            };
        }
        const color = preview.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/);
        return {
            id: id,
            preview: preview,
            raw: line,
            isImage: false,
            isColor: !!color,
            color: color ? preview : "",
        };
    }

    function toggle() {
        if (open) close();
        else openMenu();
    }
    function openMenu() {
        query = "";
        selectedIndex = 0;
        items = [];
        listProc.running = true;
        open = true;
    }
    function close() { open = false; }

    function activate(i) {
        const item = filtered[i];
        if (!item) return;
        copyProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "_", item.raw];
        copyProc.startDetached();
        close();
    }
    function deleteEntry(i) {
        const item = filtered[i];
        if (!item) return;
        delProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "_", item.raw];
        delProc.startDetached();
        root.items = root.items.filter(x => x.id !== item.id);
        if (root.selectedIndex >= filtered.length) root.selectedIndex = Math.max(0, filtered.length - 1);
    }
    function deleteAll() {
        wipeProc.command = ["sh", "-c", "cliphist wipe && rm -rf \"$1\"", "_", root.thumbDir];
        wipeProc.startDetached();
        root.items = [];
        root.selectedIndex = 0;
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.length > 0);
                root.items = lines.map(root._parseEntry);
            }
        }
    }
    Process { id: copyProc; command: [] }
    Process { id: delProc; command: [] }
    Process { id: wipeProc; command: [] }

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
                opacity: 0.45
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(parent.height * 0.18)
                width: 720
                height: Math.min(620, headerCol.implicitHeight + resultsCol.implicitHeight + 28)
                radius: 14
                color: "#292524"
                border.color: "#78716c"
                border.width: 1
                focus: root.open
                Keys.onPressed: (e) => {
                    const n = root.filtered.length;
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        root.close(); e.accepted = true;
                    } else if (e.key === Qt.Key_Down) {
                        if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_PageDown) {
                        if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 8);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_PageUp) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 8);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex); e.accepted = true;
                    } else if (ctrl && (e.modifiers & Qt.ShiftModifier) && (e.key === Qt.Key_D || e.key === Qt.Key_Delete)) {
                        root.deleteAll(); e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_D || e.key === Qt.Key_Delete)) {
                        root.deleteEntry(root.selectedIndex); e.accepted = true;
                    } else if (e.key === Qt.Key_Backspace) {
                        root.query = root.query.slice(0, -1);
                        root.selectedIndex = 0;
                        e.accepted = true;
                    } else if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32) {
                        root.query += e.text;
                        root.selectedIndex = 0;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: headerCol
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: 14
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Text {
                            text: "󰅍"
                            color: "#a8a29e"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 28
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.query || "Clipboard history"
                            color: root.query ? "#fafaf9" : "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 22
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.filtered.length + " items"
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#44403c" }
                }

                Flickable {
                    id: results
                    anchors {
                        top: headerCol.bottom
                        left: parent.left
                        right: parent.right
                        bottom: footer.top
                        topMargin: 6
                        leftMargin: 8
                        rightMargin: 8
                    }
                    contentHeight: resultsCol.implicitHeight
                    clip: true
                    Connections {
                        target: root
                        function onScrollRequested(top, bottom) {
                            const visTop = results.contentY;
                            const visBottom = results.contentY + results.height;
                            let newY = results.contentY;
                            if (top < visTop) newY = top;
                            else if (bottom > visBottom) newY = bottom - results.height;
                            const max = Math.max(0, results.contentHeight - results.height);
                            results.contentY = Math.max(0, Math.min(max, newY));
                        }
                    }
                    ColumnLayout {
                        id: resultsCol
                        width: parent.width
                        spacing: 2

                        Repeater {
                            model: root.filtered.slice(0, 100)
                            delegate: ClipRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                highlighted: root.selectedIndex === index
                                thumbDir: root.thumbDir
                                Layout.fillWidth: true
                                onPicked: root.activate(index)
                                onHovered: root.selectedIndex = index
                                onRemoved: root.deleteEntry(index)
                            }
                        }

                        Text {
                            visible: root.filtered.length === 0
                            text: root.items.length === 0 ? "Clipboard is empty" : "No matches"
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 13
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 24
                        }
                    }
                }

                Rectangle {
                    id: footer
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 28
                    color: "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14
                        Text {
                            text: "↵ Copy"
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                        }
                        Text {
                            text: "Ctrl+D Delete"
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                        }
                        Text {
                            text: "Esc Close"
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            id: wipeBtn
                            implicitWidth: wipeText.implicitWidth + 16
                            implicitHeight: 20
                            radius: 4
                            color: wipeMouse.containsMouse ? "#7f1d1d" : "transparent"
                            border.color: "#7f1d1d"
                            border.width: 1
                            Text {
                                id: wipeText
                                anchors.centerIn: parent
                                text: "󰩺  Delete all"
                                color: wipeMouse.containsMouse ? "#fafaf9" : "#f87171"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 10
                            }
                            MouseArea {
                                id: wipeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.deleteAll()
                            }
                        }
                    }
                }
            }
        }
    }

    component ClipRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        property string thumbDir: "/tmp/cliphist-thumbs"
        signal picked()
        signal hovered()
        signal removed()
        implicitHeight: row.entry && row.entry.isImage ? 76 : 44
        radius: 8
        color: row.highlighted ? "#3b3531" : (hover.containsMouse ? "#262220" : "transparent")

        readonly property string thumbPath: row.entry && row.entry.isImage
            ? row.thumbDir + "/" + row.entry.id + "." + row.entry.ext
            : ""
        property bool thumbReady: false

        Process {
            id: thumbProc
            running: false
            command: row.entry && row.entry.isImage
                ? ["sh", "-c",
                   "mkdir -p \"$1\" && if [ ! -s \"$1/$2.$3\" ]; then printf '%s\\n' \"$4\" | cliphist decode > \"$1/$2.$3\"; fi",
                   "_", row.thumbDir, row.entry.id, row.entry.ext, row.entry.raw]
                : []
            onExited: row.thumbReady = true
        }
        Component.onCompleted: {
            if (row.entry && row.entry.isImage) thumbProc.running = true;
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12
            Text {
                text: row.entry ? row.entry.id : ""
                color: "#78716c"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
            }

            // Image thumbnail
            Rectangle {
                visible: row.entry && row.entry.isImage
                Layout.preferredWidth: 84
                Layout.preferredHeight: 60
                radius: 4
                color: "#1c1917"
                border.color: "#44403c"
                border.width: 1
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: row.thumbReady && row.thumbPath ? "file://" + row.thumbPath : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                }
            }

            // Color swatch
            Rectangle {
                visible: row.entry && row.entry.isColor
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                radius: 4
                color: row.entry && row.entry.isColor ? row.entry.color : "transparent"
                border.color: "#78716c"
                border.width: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.preview : ""
                    color: "#fafaf9"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 13
                    font.bold: row.highlighted
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    maximumLineCount: 1
                }
                Text {
                    Layout.fillWidth: true
                    visible: row.entry && row.entry.isImage
                    text: row.entry && row.entry.isImage
                        ? (row.entry.dims ? row.entry.dims + "  •  " + row.entry.size : row.entry.size)
                        : ""
                    color: "#a8a29e"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
            Text {
                visible: row.highlighted
                text: "↵"
                color: "#78716c"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.MiddleButton) row.removed();
                else row.picked();
            }
            onContainsMouseChanged: if (containsMouse) row.hovered()
        }
    }
}
