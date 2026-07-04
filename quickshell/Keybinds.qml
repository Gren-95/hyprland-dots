// Searchable keybind viewer — parses `hyprctl binds -j` live, groups by category.
// Spotlight-style centered overlay; Esc closes, type to filter, ↑/↓ to navigate.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0
    property var entries: []
    // Default anchor set from the bar (the Quick Actions chevron); openers
    // can pass their own item via toggle(from)/openMenu(from) so the flyout
    // hangs under whatever was actually clicked (QA tile, promoted icon).
    property var anchorBar: null
    property var anchorItem: null
    property Item _openAnchor: null

    function toggle(from) {
        if (open) close();
        else openMenu(from);
    }
    function openMenu(from) {
        _openAnchor = from ?? null;
        query = "";
        selectedIndex = 0;
        if (entries.length === 0) refresh();
        open = true;
    }
    function close() { open = false; }
    function refresh() { bindsProc.running = true; }

    // Modmask bits as exposed by Hyprland.
    readonly property var modBits: ({ 1: "Shift", 2: "Caps", 4: "Ctrl", 8: "Alt", 16: "Mod2", 32: "Mod3", 64: "Super", 128: "Mod5" })

    function _formatMods(mask) {
        const out = [];
        for (const bit in modBits) {
            if ((mask & bit) !== 0) out.push(modBits[bit]);
        }
        return out;
    }
    function _prettyKey(key) {
        if (!key) return "";
        // Strip XF86 prefix, replace common keysyms
        return key
            .replace(/^XF86/, "")
            .replace(/^Audio/, "")
            .replace(/^Mon/, "")
            .replace(/^Kbd/, "Kbd ")
            .replace(/Raise/, "+")
            .replace(/Lower/, "-")
            .replace(/^Print$/, "PrtSc");
    }
    function _classify(disp, arg) {
        const a = (arg || "").toLowerCase();
        const d = (disp || "").toLowerCase();
        if (d === "exec") {
            if (/wpctl|pactl|playerctl/.test(a)) return "audio";
            if (/brightnessctl|backlight/.test(a)) return "brightness";
            if (/grim|slurp|swappy|screenshot|hyprshot|wf-recorder|screenrecord/.test(a)) return "capture";
            if (/wl-copy|cliphist|wofi|rofi/.test(a)) return "clipboard";
            if (/systemctl|loginctl|powermenu|hyprctl dispatch exit/.test(a)) return "power";
            if (/firefox|kitty|nautilus|hyprpicker/.test(a)) return "apps";
            if (/quickshell/.test(a)) return "shell";
        }
        if (d === "global") return "shell";
        if (/workspace|movetoworkspace/.test(d)) return "workspace";
        if (/movewindow|movefocus|swapwindow|resizeactive|togglefloating|fullscreen|killactive|togglesplit|pseudo/.test(d)) return "window";
        return "other";
    }
    function _catIcon(c) {
        switch (c) {
            case "audio":      return "󰕾";
            case "brightness": return "󰃟";
            case "capture":    return "󰄀";
            case "clipboard":  return "󰅍";
            case "power":      return "󰐥";
            case "apps":       return "󰣆";
            case "shell":      return "󰘧";
            case "workspace":  return "󰍹";
            case "window":     return "󰖯";
            default:           return "󰒓";
        }
    }
    function _catColor(c) {
        switch (c) {
            case "audio":      return "#60a5fa";
            case "brightness": return Theme.accent.yellow;
            case "capture":    return Theme.accent.green;
            case "clipboard":  return Theme.accent.slate;
            case "power":      return Theme.accent.red;
            case "apps":       return Theme.accent.orange;
            case "shell":      return Theme.accent.purple;
            case "workspace":  return Theme.accent.pink;
            case "window":     return Theme.accent.teal;
            default:           return Theme.mutedDeep;
        }
    }
    function _action(bind) {
        if (bind.dispatcher === "exec") return bind.arg;
        if (bind.dispatcher === "global") return "→ " + bind.arg;
        return bind.dispatcher + (bind.arg ? " " + bind.arg : "");
    }

    readonly property var filtered: {
        const q = root.query.toLowerCase();
        if (!q) return root.entries;
        return root.entries.filter(e =>
            e.combo.toLowerCase().includes(q) ||
            e.action.toLowerCase().includes(q) ||
            e.category.toLowerCase().includes(q)
        );
    }

    Process {
        id: bindsProc
        command: ["hyprctl", "binds", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let raw;
                try { raw = JSON.parse(text); } catch (e) { console.warn("[Keybinds] parse fail", e); return; }
                const out = [];
                for (const b of raw) {
                    if (!b.key) continue;
                    if (b.keycode > 0 && !b.key) continue;
                    const mods = root._formatMods(b.modmask);
                    const key = root._prettyKey(b.key);
                    const parts = mods.concat([key]);
                    const action = root._action(b);
                    const cat = root._classify(b.dispatcher, b.arg);
                    out.push({
                        parts: parts,
                        combo: parts.join("+"),
                        action: action,
                        dispatcher: b.dispatcher,
                        category: cat,
                        catIcon: root._catIcon(cat),
                        catColor: root._catColor(cat),
                        description: b.description || "",
                    });
                }
                // Sort: category asc, then combo asc
                out.sort((a, b) => {
                    if (a.category !== b.category) return a.category.localeCompare(b.category);
                    return a.combo.localeCompare(b.combo);
                });
                root.entries = out;
            }
        }
    }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root._openAnchor ?? root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("keybinds", "w", 640)
        cardHeight: settingsStore.flyoutSize("keybinds", "h", 620)
        onDismissed: root.close()
        onKeyPressed: (e) => {
            const n = root.filtered.length;
            if (e.key === Qt.Key_Down) {
                if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up) {
                root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                e.accepted = true;
            } else if (e.key === Qt.Key_PageDown) {
                if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 10);
                e.accepted = true;
            } else if (e.key === Qt.Key_PageUp) {
                root.selectedIndex = Math.max(0, root.selectedIndex - 10);
                e.accepted = true;
            } else if (e.key === Qt.Key_F5) {
                root.refresh(); e.accepted = true;
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
        Item {
                anchors.fill: parent
                ColumnLayout {
                    id: headerCol
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.margins: Theme.spacing.lg
                    spacing: Theme.spacing.md

                    Text {
                        Layout.fillWidth: true
                        text: "Keybinds"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.lg
                        Text {
                            text: "󰌌"
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.hero
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.query || "Search keybinds"
                            color: root.query ? Theme.fg : Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xxl
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.filtered.length + " / " + root.entries.length
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                }

                Flickable {
                    id: results
                    anchors {
                        top: headerCol.bottom
                        left: parent.left
                        right: parent.right
                        bottom: footer.top
                        topMargin: 4
                        leftMargin: 8
                        rightMargin: 8
                    }
                    contentHeight: resultsCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: resultsCol
                        width: parent.width
                        spacing: 0

                        Text {
                            Layout.leftMargin: 6
                            Layout.topMargin: 2
                            Layout.bottomMargin: 4
                            visible: root.filtered.length > 0
                            text: "KEYBINDS"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }

                        Repeater {
                            model: root.filtered
                            delegate: BindRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                highlighted: root.selectedIndex === index
                                Layout.fillWidth: true
                                onHovered: root.selectedIndex = index
                            }
                        }

                        Text {
                            visible: root.entries.length === 0
                            text: "Loading binds…"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.md
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 24
                        }
                        Text {
                            visible: root.entries.length > 0 && root.filtered.length === 0
                            text: "No matches"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.md
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 24
                        }
                    }

                    // Auto-scroll selected row into view
                    Connections {
                        target: root
                        function onSelectedIndexChanged() {
                            const rowH = 40;
                            const top = root.selectedIndex * rowH;
                            const bottom = top + rowH;
                            if (top < results.contentY) results.contentY = top;
                            else if (bottom > results.contentY + results.height) {
                                const max = Math.max(0, results.contentHeight - results.height);
                                results.contentY = Math.min(max, bottom - results.height);
                            }
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
                        spacing: Theme.spacing.lg
                        Text { text: "↑↓ Navigate"; color: Theme.mutedDeep; font.family: Theme.font; font.pixelSize: Theme.fontSize.sm }
                        Text { text: "F5 Refresh"; color: Theme.mutedDeep; font.family: Theme.font; font.pixelSize: Theme.fontSize.sm }
                        Text { text: "Esc Close"; color: Theme.mutedDeep; font.family: Theme.font; font.pixelSize: Theme.fontSize.sm }
                        Item { Layout.fillWidth: true }
                    }
                }
        }
    }

    component BindRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        signal hovered()
        implicitHeight: 40
        radius: 6
        color: row.highlighted ? Theme.bgActive : (hover.containsMouse ? Theme.bgHover : "transparent")

        // Left accent strip — only visible when highlighted
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 3
            radius: 2
            color: row.entry ? row.entry.catColor : "transparent"
            opacity: row.highlighted ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.md

            // Category icon (symbolic, monochrome-tinted)
            Text {
                Layout.preferredWidth: 18
                Layout.alignment: Qt.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                text: row.entry ? row.entry.catIcon : ""
                color: row.entry ? row.entry.catColor : Theme.mutedDeep
                opacity: row.highlighted ? 1.0 : 0.75
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
            }

            // Unified kbd pill: one rounded outline, segments inside separated by hairlines
            Rectangle {
                id: kbdPill
                Layout.preferredWidth: Math.min(240, kbdRow.implicitWidth)
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                radius: 5
                color: row.highlighted ? Theme.bg : "#1a1715"
                border.color: row.highlighted ? Theme.disabled : Theme.border
                border.width: 1
                clip: true

                Row {
                    id: kbdRow
                    anchors.fill: parent
                    Repeater {
                        model: row.entry ? row.entry.parts : []
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: Math.max(28, keyText.implicitWidth + 14)
                            height: kbdPill.height
                            Rectangle {
                                visible: index > 0
                                width: 1
                                height: parent.height
                                anchors.left: parent.left
                                color: row.highlighted ? Theme.border : Theme.borderSubtle
                            }
                            Text {
                                id: keyText
                                anchors.centerIn: parent
                                text: modelData
                                color: row.highlighted ? Theme.fg : Theme.fgMuted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                                font.bold: row.highlighted
                            }
                        }
                    }
                }
            }

            // Action description
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: row.entry ? row.entry.action : ""
                color: row.highlighted ? Theme.fgMuted : "#8d8985"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) row.hovered()
        }
    }
}
