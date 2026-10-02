// Clipboard history selector flyout: a search bar over a card listing cliphist
// entries (with thumbnails for images and swatches for hex colors).
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0
    property var items: []
    // Default anchor set from the bar (the Quick Actions chevron); openers
    // can pass their own item via toggle(from)/openMenu(from) so the flyout
    // hangs under whatever was actually clicked (QA tile, promoted icon).
    property var anchorBar: null
    property var anchorItem: null
    property Item _openAnchor: null

    readonly property string thumbDir: "/tmp/cliphist-thumbs"

    readonly property var filtered: {
        const q = root.query.toLowerCase();
        if (!q) return root.items;
        return root.items.filter(i => i.preview.toLowerCase().includes(q));
    }

    // Popup height follows the list (up to what the screen allows), so there
    // is no dead space under the last row; the footer stays pinned below it.
    readonly property real fitHeight: Math.max(340, Math.min(
        anchorBar && anchorBar.screen ? Math.min(anchorBar.screen.height - 160, 700) : 620,
        contentCol.implicitHeight))

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

    function toggle(from) {
        if (open) close();
        else openMenu(from);
    }
    function openMenu(from) {
        _openAnchor = from ?? null;
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

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root._openAnchor ?? root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("clipboard", "w", 560)
        cardHeight: settingsStore.flyoutSize("clipboard", "h", root.fitHeight)
        onDismissed: root.close()
        onKeyPressed: (e) => {
            const n = root.filtered.length;
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (e.key === Qt.Key_Down) {
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
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                Text {
                    Layout.fillWidth: true
                    text: "Clipboard"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                }
                LauncherChipButton {
                    visible: root.items.length > 0
                    danger: true
                    glyph: "󰩺"
                    text: "Delete all"
                    onClicked: root.deleteAll()
                }
            }

            LauncherSearchBar {
                Layout.fillWidth: true
                text: root.query
                glyph: "󰅍"
                placeholder: "Search clipboard history"
                countText: root.filtered.length > 0
                    ? root.filtered.length + (root.filtered.length === 1 ? " item" : " items") : ""
                onCleared: { root.query = ""; root.selectedIndex = 0; }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: listBox.height + 2
                radius: 10 * Theme.radiusScale
                color: Theme.bg
                border.color: Theme.border
                border.width: 1
                clip: true

                Flickable {
                    id: results
                    anchors.fill: parent
                    anchors.margins: 1
                    contentWidth: width
                    contentHeight: listBox.height
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    ScrollBar.vertical: ThinScrollBar {}

                    NumberAnimation {
                        id: scrollAnim
                        target: results
                        property: "contentY"
                        duration: Theme.duration.normal
                        easing.type: Theme.easing.standard
                    }

                    Item {
                        id: listBox
                        readonly property int pad: Theme.spacing.md
                        width: results.width
                        height: root.filtered.length === 0 ? 230 : resultsCol.implicitHeight + pad * 2

                        LauncherSelection {
                            id: selection
                            inset: listBox.pad
                            offsetY: listBox.pad
                        }

                        ColumnLayout {
                            id: resultsCol
                            x: listBox.pad
                            y: listBox.pad
                            width: parent.width - listBox.pad * 2
                            spacing: 2
                            onImplicitHeightChanged: Qt.callLater(contentCol.syncSelection)

                            LauncherSectionHeader {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacing.md
                                Layout.rightMargin: Theme.spacing.md
                                Layout.topMargin: Theme.spacing.xs
                                visible: root.filtered.length > 0
                                title: "HISTORY"
                                count: root.filtered.length
                            }

                            Repeater {
                                id: rowsRepeater
                                model: root.filtered.slice(0, 100)
                                onItemAdded: Qt.callLater(contentCol.syncSelection)
                                delegate: ClipItemRow {
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
                        }

                        LauncherEmptyState {
                            anchors.centerIn: parent
                            visible: root.filtered.length === 0
                            glyph: root.items.length === 0 ? "󰅍" : "󰍉"
                            title: root.items.length === 0 ? "Clipboard is empty" : "No matches"
                            subtitle: root.items.length === 0 ? "Copied text, colours and images show up here"
                                : "Nothing matches \u201c" + root.query + "\u201d"
                        }
                    }
                }
            }

            LauncherFooter {
                Layout.fillWidth: true
                hints: [
                    { key: "\u2191\u2193", label: "navigate" },
                    { key: "\u21b5", label: "copy" },
                    { key: "Ctrl+D", label: "delete" },
                    { key: "Ctrl+Shift+D", label: "delete all" },
                    { key: "Esc", label: "close" }
                ]
            }

            Connections {
                target: root
                function onSelectedIndexChanged() { Qt.callLater(contentCol.syncSelection) }
            }

            // Point the selection plate at the highlighted row and keep that
            // row inside the viewport.
            function syncSelection() {
                const item = rowsRepeater.itemAt(root.selectedIndex);
                selection.target = item;
                if (!item) return;
                const top = item.y + listBox.pad;
                const bot = top + item.height;
                const pad = 8;
                const viewTop = results.contentY;
                const viewBot = viewTop + results.height;
                const maxY = Math.max(0, results.contentHeight - results.height);
                let to = viewTop;
                if (root.selectedIndex === 0) to = 0;
                else if (top < viewTop + pad) to = Math.max(0, top - pad);
                else if (bot > viewBot - pad) to = Math.min(maxY, bot - results.height + pad);
                if (to === viewTop) return;
                scrollAnim.stop();
                scrollAnim.to = to;
                scrollAnim.start();
            }
        }
    }
}
