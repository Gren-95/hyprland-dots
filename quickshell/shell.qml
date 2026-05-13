//@ pragma UseQApplication

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Scope {
    Notifications { id: notifs }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            margins { top: 4; left: 4; right: 4 }
            implicitHeight: 36
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#44403c"
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (e) => {
                        const dir = e.angleDelta.y > 0 ? "e+1" : "e-1";
                        Hyprland.dispatch("workspace " + dir);
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 0

                    // ============ LEFT ============
                    BarIcon {
                        glyph: "󰀻"
                        pixelSize: 18
                        tooltip: "Open app menu"
                        onClicked: ppmenu.startDetached()
                        Process { id: ppmenu; command: ["rofi", "-show", "drun", "-show-icons", "-theme",
                            Quickshell.env("HOME") + "/.config/rofi/launcher.rasi"] }
                    }
                    BarSep {}

                    RowLayout {
                        spacing: 8
                        Repeater {
                            model: Hyprland.workspaces
                            delegate: Text {
                                required property var modelData
                                text: workspaceGlyph(modelData.id)
                                color: modelData.active ? "#f5f5f4" : "#78716c"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 16
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Hyprland.dispatch("workspace " + modelData.id)
                                    onWheel: (e) => Hyprland.dispatch(
                                        "workspace " + (e.angleDelta.y > 0 ? "e+1" : "e-1"))
                                }
                            }
                        }
                    }

                    Item { width: 8 }
                    Text {
                        Layout.maximumWidth: 400
                        elide: Text.ElideRight
                        text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
                        color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 13
                    }

                    Item { Layout.fillWidth: true }

                    // ============ CENTER ============
                    Text {
                        text: "  " + Qt.formatDate(clockTimer.now, "ddd, dd MMM")
                        color: "#a8a29e"
                        font { family: "FiraCode Nerd Font"; pixelSize: 13 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: calProc.startDetached() }
                    }
                    Item { width: 8 }
                    Text {
                        text: Qt.formatTime(clockTimer.now, "HH:mm")
                        color: "#f5f5f4"
                        font { family: "FiraCode Nerd Font"; pixelSize: 14; bold: true }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: calProc.startDetached() }
                    }
                    Process { id: calProc; command: ["gnome-calendar"] }
                    Timer {
                        id: clockTimer
                        property date now: new Date()
                        interval: 1000; running: true; repeat: true
                        onTriggered: now = new Date()
                    }

                    Item { Layout.fillWidth: true }

                    // ============ RIGHT ============
                    RowLayout {
                        spacing: 10
                        Repeater {
                            model: SystemTray.items
                            delegate: TrayItem { required property SystemTrayItem modelData; item: modelData }
                        }
                    }

                    // Trayscale (delegates to existing script)
                    BarScript {
                        scriptName: "trayscale-status.sh"
                        intervalMs: 5000
                        onClickArg: "click"
                        onMiddleClickArg: "toggle"
                        onScrollUpArg: "scroll-up"
                        onScrollDownArg: "scroll-down"
                    }
                    BarSep {}

                    BluetoothModule { parentBar: bar }
                    BarSep {}

                    SoundModule { parentBar: bar }
                    BarSep {}

                    PowerProfileModule { parentBar: bar }
                    BarSep {}

                    // Battery
                    BarIcon {
                        readonly property var dev: UPower.displayDevice
                        readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
                        readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
                            || dev.state === UPowerDeviceState.FullyCharged)
                        readonly property bool plugged: dev && !UPower.onBattery
                        glyph: {
                            if (charging) return "󰂄";
                            if (plugged) return "󰂏";
                            const icons = ["󰂎","󰁺","󰁾","󰂀","󰁹"];
                            return icons[Math.min(4, Math.floor(pct / 21))];
                        }
                        label: pct + "%"
                        color: {
                            if (charging || plugged) return "#22c55e";
                            if (pct <= 20) return "#ef4444";
                            return "#eab308";
                        }
                        tooltip: {
                            if (!dev) return "";
                            if (charging && dev.timeToFull > 0)
                                return Math.round(dev.timeToFull / 60) + " min to full";
                            if (dev.timeToEmpty > 0)
                                return Math.round(dev.timeToEmpty / 60) + " min left";
                            return "";
                        }
                        onWheel: (up) => {
                            brightProc.command = ["swayosd-client", "--brightness", up ? "raise" : "lower"];
                            brightProc.startDetached();
                        }
                        Process { id: brightProc; command: [] }
                    }

                    // WayVNC (only when running)
                    BarConditional {
                        intervalMs: 3000
                        checkCmd: ["pgrep", "-x", "wayvnc"]
                        glyph: "󰢹"
                        color: "#f97316"
                        tooltip: "WayVNC active — click to stop"
                        onClickCmd: ["pkill", "wayvnc"]
                    }

                    // Microphone (only when unmuted)
                    BarIcon {
                        readonly property var src: Pipewire.defaultAudioSource
                        visible: src && src.audio && !src.audio.muted
                        glyph: "󰍬"
                        color: "#f97316"
                        onClicked: {
                            if (src && src.audio) src.audio.muted = true;
                        }
                        PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
                    }

                    NotifBell { parentBar: bar }
                    BarSep {}

                    PowerMenuModule { parentBar: bar }
                }
            }
        }
    }

    function workspaceGlyph(id) {
        const m = {1:"",2:"",3:"",4:"",5:"",6:"",7:"",8:"",9:""};
        return m[id] || "";
    }

    // ====== Inline reusable components ======
    component BarSep: Text {
        text: "│"
        color: "#57534e"
        font.family: "FiraCode Nerd Font"
        font.pixelSize: 14
        Layout.leftMargin: 6
        Layout.rightMargin: 6
    }

    component BarIcon: Item {
        id: bi
        property string glyph: ""
        property string label: ""
        property string tooltip: ""
        property color color: "#f5f5f4"
        property int pixelSize: 14
        signal clicked()
        signal wheel(bool up)
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 12
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: bi.glyph
                color: bi.color
                font.family: "FiraCode Nerd Font"
                font.pixelSize: bi.pixelSize
            }
            Text {
                visible: bi.label !== ""
                text: bi.label
                color: bi.color
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 13
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: bi.clicked()
            onWheel: (e) => bi.wheel(e.angleDelta.y > 0)
        }
    }

    component BarScript: Item {
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
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 14
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
                case "disconnected":return "#78716c";
                case "immich":      return "#f59e0b";
                case "jellyfin":    return "#818cf8";
                case "dnd":         return "#f97316";
                case "idle-on":     return "#22c55e";
                case "idle-off":    return "#78716c";
                case "colorpicker": return "#e879f9";
                case "clipboard":   return "#94a3b8";
                default:            return "#f5f5f4";
            }
        }
    }

    component BarConditional: Item {
        id: bc
        property int intervalMs: 3000
        property var checkCmd: []
        property string glyph: ""
        property color color: "#f5f5f4"
        property string tooltip: ""
        property var onClickCmd: null
        property bool _present: false
        Layout.fillHeight: true
        visible: _present
        implicitWidth: visible ? (label.implicitWidth + 16) : 0
        Text {
            id: label
            anchors.centerIn: parent
            text: bc.glyph
            color: bc.color
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: {
                if (bc.onClickCmd) {
                    const p = Qt.createQmlObject(
                        "import Quickshell.Io; Process {}", bc);
                    p.command = bc.onClickCmd;
                    p.startDetached();
                }
            }
        }
        Process {
            id: probe
            command: bc.checkCmd
            running: false
            onExited: (code) => bc._present = (code === 0)
        }
        Timer {
            interval: bc.intervalMs; running: true; repeat: true; triggeredOnStart: true
            onTriggered: { if (!probe.running) probe.running = true; }
        }
    }

    component NotifBell: Item {
        id: bell
        property var parentBar
        property int selectedIndex: 0
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 14

        Connections {
            target: notifs
            function onCenterOpenChanged() { if (notifs.centerOpen) bell.selectedIndex = 0 }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: notifs.dnd ? "󰂛"
                    : (notifs.unreadCount > 0 ? "󰂞" : "󰂚")
                color: notifs.dnd ? "#f97316" : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Rectangle {
                visible: notifs.unreadCount > 0 && !notifs.dnd
                implicitWidth: cnt.implicitWidth + 8
                implicitHeight: 14
                radius: 7
                color: "#ef4444"
                Text {
                    id: cnt
                    anchors.centerIn: parent
                    text: String(notifs.unreadCount)
                    color: "#f5f5f4"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) {
                    notifs.dnd = !notifs.dnd;
                } else {
                    notifs.toggleCenter();
                }
            }
        }

        PopupWindow {
            id: centerPop
            anchor.window: bell.parentBar
            anchor.item: bell
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 2
            implicitWidth: 380
            implicitHeight: Math.min(560, centerCol.implicitHeight + 24)
            visible: notifs.centerOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#78716c"
                border.width: 1
                focus: notifs.centerOpen
                Keys.onPressed: (e) => {
                    const n = notifs.historyList.length;
                    if (e.key === Qt.Key_Escape) {
                        notifs.closeCenter();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_D && (e.modifiers & Qt.ControlModifier)) {
                        notifs.dnd = !notifs.dnd;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
                        notifs.clearHistory();
                        e.accepted = true;
                    } else if (n === 0) {
                        return;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        bell.selectedIndex = (bell.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        bell.selectedIndex = (bell.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                        const entry = notifs.historyList[bell.selectedIndex];
                        if (entry) notifs.dismissHistoryEntry(entry.id);
                        if (bell.selectedIndex >= notifs.historyList.length)
                            bell.selectedIndex = Math.max(0, notifs.historyList.length - 1);
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: centerCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "󰂚  Notifications"
                            color: "#f5f5f4"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        BtToggle {
                            label: notifs.dnd ? "DnD on" : "DnD off"
                            active: !!(notifs.dnd)
                            onClicked: notifs.dnd = !notifs.dnd
                        }
                        BtToggle {
                            label: "Clear"
                            active: false
                            onClicked: notifs.clearHistory()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: "#44403c"
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: notifs.historyList.length === 0
                        text: "No notifications"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: notifs.historyList.length > 0
                        Repeater {
                            model: notifs.historyList
                            delegate: HistoryRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                highlighted: bell.selectedIndex === index
                                Layout.fillWidth: true
                                onDismiss: notifs.dismissHistoryEntry(modelData.id)
                                onHovered: bell.selectedIndex = index
                            }
                        }
                    }
                }
            }
        }

        HyprlandFocusGrab {
            active: notifs.centerOpen
            windows: [centerPop]
            onCleared: notifs.closeCenter()
        }
    }

    component HistoryRow: Rectangle {
        id: hrow
        property var entry
        property bool highlighted: false
        signal dismiss()
        signal hovered()
        implicitHeight: hcol.implicitHeight + 16
        radius: 6
        color: hrow.highlighted ? "#3b3531" : (hoverArea.containsMouse ? "#292524" : "transparent")

        ColumnLayout {
            id: hcol
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                IconImage {
                    visible: hrow.entry && (hrow.entry.image || hrow.entry.appIcon)
                    source: hrow.entry ? (hrow.entry.image || hrow.entry.appIcon) : ""
                    implicitSize: 16
                }
                Text {
                    Layout.fillWidth: true
                    text: hrow.entry ? (hrow.entry.summary || hrow.entry.appName) : ""
                    color: "#f5f5f4"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: hrow.entry ? Qt.formatTime(hrow.entry.time, "HH:mm") : ""
                    color: "#a8a29e"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                }
                Rectangle {
                    implicitWidth: 18; implicitHeight: 18; radius: 9
                    color: xMouse.containsMouse ? "#44403c" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: "#a8a29e"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 14
                    }
                    MouseArea {
                        id: xMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hrow.dismiss()
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                visible: hrow.entry && hrow.entry.body !== ""
                text: hrow.entry ? hrow.entry.body : ""
                color: "#d6d3d1"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: {} // future: invoke notification
            onContainsMouseChanged: if (containsMouse) hrow.hovered()
        }
    }

    component PowerMenuModule: Item {
        id: pm
        property var parentBar
        property bool popupOpen: false
        property int selectedIndex: 0
        readonly property var entries: [
            { glyph: "󰌾", color: "#a8a29e", label: "Lock",     cmd: ["loginctl", "lock-session"] },
            { glyph: "󰤄", color: "#60a5fa", label: "Suspend",  cmd: ["systemctl", "suspend"] },
            { glyph: "󰍃", color: "#eab308", label: "Logout",   cmd: ["hyprctl", "dispatch", "exit"] },
            { glyph: "󰜉", color: "#f97316", label: "Reboot",   cmd: ["systemctl", "reboot"] },
            { glyph: "⏻",  color: "#ef4444", label: "Shutdown", cmd: ["systemctl", "poweroff"] },
        ]
        Layout.fillHeight: true
        implicitWidth: 32

        onPopupOpenChanged: if (popupOpen) selectedIndex = 0

        function activate(i) {
            if (i < 0 || i >= entries.length) return;
            pmCmd.command = entries[i].cmd;
            pmCmd.startDetached();
            popupOpen = false;
        }

        Text {
            anchors.centerIn: parent
            text: "⏻"
            color: "#ef4444"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 16
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: pm.popupOpen = !pm.popupOpen
        }

        PopupWindow {
            id: pmPopup
            anchor.window: pm.parentBar
            anchor.item: pm
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 2
            implicitWidth: 220
            implicitHeight: pmCol.implicitHeight + 16
            visible: pm.popupOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#78716c"
                border.width: 1
                focus: pm.popupOpen
                Keys.onPressed: (e) => {
                    const n = pm.entries.length;
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        pm.selectedIndex = (pm.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        pm.selectedIndex = (pm.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        pm.activate(pm.selectedIndex);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Escape) {
                        pm.popupOpen = false;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: pmCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Repeater {
                        model: pm.entries
                        delegate: PowerMenuRow {
                            required property var modelData
                            required property int index
                            entry: modelData
                            selected: pm.selectedIndex === index
                            Layout.fillWidth: true
                            onPicked: pm.activate(index)
                            onHovered: pm.selectedIndex = index
                        }
                    }
                }
            }
        }

        Process { id: pmCmd; command: [] }

        HyprlandFocusGrab {
            active: pm.popupOpen
            windows: [pmPopup]
            onCleared: pm.popupOpen = false
        }
    }

    component PowerMenuRow: Rectangle {
        id: pmrow
        property var entry
        property bool selected: false
        signal picked()
        signal hovered()
        implicitHeight: 32
        radius: 6
        color: pmrow.selected ? "#3b3531" : (rowMa.containsMouse ? "#292524" : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Text {
                text: pmrow.entry ? pmrow.entry.glyph : ""
                color: pmrow.entry ? pmrow.entry.color : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                text: pmrow.entry ? pmrow.entry.label : ""
                color: "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pmrow.picked()
            onContainsMouseChanged: if (containsMouse) pmrow.hovered()
        }
    }

    component SoundModule: Item {
        id: snd
        property var parentBar
        property bool popupOpen: false
        property int selectedIndex: 0
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource
        readonly property var outputDevices: {
            if (!Pipewire.nodes) return [];
            return (Pipewire.nodes.values || []).filter(n => n.isSink && !n.isStream && n.audio);
        }
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 16

        onPopupOpenChanged: if (popupOpen) {
            const idx = outputDevices.indexOf(sink);
            selectedIndex = idx >= 0 ? idx : 0;
        }

        function adjustVolume(delta) {
            if (!sink || !sink.audio) return;
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
        }
        function activateOutput(i) {
            const list = outputDevices;
            if (i < 0 || i >= list.length) return;
            Pipewire.preferredDefaultAudioSink = list[i];
        }

        PwObjectTracker { objects: [snd.sink, snd.source] }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: {
                    if (!snd.sink || !snd.sink.audio) return "󰕾";
                    if (snd.sink.audio.muted) return "󰖁";
                    const v = snd.sink.audio.volume;
                    if (v < 0.34) return "󰕿";
                    if (v < 0.67) return "󰖀";
                    return "󰕾";
                }
                color: snd.sink && snd.sink.audio && snd.sink.audio.muted ? "#78716c" : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Text {
                text: {
                    if (!snd.sink || !snd.sink.audio) return "";
                    if (snd.sink.audio.muted) return "muted";
                    return Math.round(snd.sink.audio.volume * 100) + "%";
                }
                color: snd.sink && snd.sink.audio && snd.sink.audio.muted ? "#78716c" : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 13
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) {
                    if (snd.sink && snd.sink.audio) snd.sink.audio.muted = !snd.sink.audio.muted;
                } else {
                    snd.popupOpen = !snd.popupOpen;
                }
            }
            onWheel: (e) => {
                if (!snd.sink || !snd.sink.audio) return;
                snd.sink.audio.volume = Math.max(0, Math.min(1,
                    snd.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
            }
        }

        PopupWindow {
            id: sndPopup
            anchor.window: snd.parentBar
            anchor.item: snd
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 2
            implicitWidth: 320
            implicitHeight: sndCol.implicitHeight + 24
            visible: snd.popupOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#78716c"
                border.width: 1
                focus: snd.popupOpen
                Keys.onPressed: (e) => {
                    const n = snd.outputDevices.length;
                    if (e.key === Qt.Key_Escape) {
                        snd.popupOpen = false;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_M) {
                        if (snd.sink && snd.sink.audio) snd.sink.audio.muted = !snd.sink.audio.muted;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Right || e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                        snd.adjustVolume(0.05);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_Minus) {
                        snd.adjustVolume(-0.05);
                        e.accepted = true;
                    } else if (n > 0 && (e.key === Qt.Key_Down || e.key === Qt.Key_J)) {
                        snd.selectedIndex = (snd.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (n > 0 && (e.key === Qt.Key_Up || e.key === Qt.Key_K)) {
                        snd.selectedIndex = (snd.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (n > 0 && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) {
                        snd.activateOutput(snd.selectedIndex);
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: sndCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    AudioSection {
                        Layout.fillWidth: true
                        title: "󰕾  Output"
                        node: snd.sink
                        isSink: true
                        selectedIndex: snd.selectedIndex
                        onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                        onDeviceHovered: (idx) => snd.selectedIndex = idx
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#44403c" }

                    AudioSection {
                        Layout.fillWidth: true
                        title: "󰍬  Input"
                        node: snd.source
                        isSink: false
                        onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                    }
                }
            }
        }

        Process { id: pavuProc; command: ["pavucontrol"] }

        HyprlandFocusGrab {
            active: snd.popupOpen
            windows: [sndPopup]
            onCleared: snd.popupOpen = false
        }
    }

    component AudioSection: ColumnLayout {
        id: section
        property string title: ""
        property var node
        property bool isSink: true
        property int selectedIndex: -1
        signal launchMixer()
        signal deviceHovered(int idx)
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: section.title
                color: "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 13
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            BtToggle {
                label: section.node && section.node.audio && section.node.audio.muted ? "Muted" : "On"
                active: !!(section.node && section.node.audio && !section.node.audio.muted)
                onClicked: {
                    if (section.node && section.node.audio)
                        section.node.audio.muted = !section.node.audio.muted;
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: !!(section.node && section.node.audio)
            VolumeSlider {
                Layout.fillWidth: true
                value: section.node && section.node.audio ? section.node.audio.volume : 0
                onMoved: {
                    if (section.node && section.node.audio) section.node.audio.volume = value;
                }
            }
            Text {
                text: section.node && section.node.audio
                    ? Math.round(section.node.audio.volume * 100) + "%" : ""
                color: "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
                model: {
                    if (!Pipewire.nodes) return [];
                    const all = Pipewire.nodes.values || [];
                    return all.filter(n => n.isSink === section.isSink && !n.isStream && n.audio);
                }
                delegate: AudioDeviceRow {
                    required property var modelData
                    required property int index
                    node: modelData
                    isActive: section.node === modelData
                    highlighted: section.selectedIndex === index
                    Layout.fillWidth: true
                    onPicked: {
                        if (section.isSink) Pipewire.preferredDefaultAudioSink = modelData;
                        else Pipewire.preferredDefaultAudioSource = modelData;
                    }
                    onHovered: section.deviceHovered(index)
                }
            }
        }
    }

    component VolumeSlider: Rectangle {
        id: vs
        property real value: 0
        signal moved()
        implicitHeight: 8
        radius: 4
        color: "#292524"
        border.color: "#44403c"
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: Math.max(0, Math.min(parent.width - 2, (parent.width - 2) * vs.value))
            radius: 4
            color: "#60a5fa"
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            preventStealing: true
            onPressed: (e) => { vs.value = Math.max(0, Math.min(1, e.x / vs.width)); vs.moved(); }
            onPositionChanged: (e) => {
                if (pressed) {
                    vs.value = Math.max(0, Math.min(1, e.x / vs.width));
                    vs.moved();
                }
            }
        }
    }

    component AudioDeviceRow: Rectangle {
        id: arow
        property var node
        property bool isActive: false
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 26
        radius: 4
        color: arow.highlighted ? "#3b3531"
             : arow.isActive ? "#231f1d"
             : (rowMa.containsMouse ? "#292524" : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 6
            Text {
                text: arow.isActive ? "●" : "○"
                color: arow.isActive ? "#60a5fa" : "#78716c"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
            }
            Text {
                Layout.fillWidth: true
                text: arow.node ? (arow.node.nickname || arow.node.description || arow.node.name || "") : ""
                color: "#f5f5f4"
                elide: Text.ElideRight
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
                font.bold: arow.isActive
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: arow.picked()
            onContainsMouseChanged: if (containsMouse) arow.hovered()
        }
    }

    component PowerProfileModule: Item {
        id: pp
        property var parentBar
        property bool popupOpen: false
        property int selectedIndex: 0
        readonly property var profiles: [PowerProfile.Performance, PowerProfile.Balanced, PowerProfile.PowerSaver]
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 16

        onPopupOpenChanged: {
            if (popupOpen) {
                const idx = profiles.indexOf(PowerProfiles.profile);
                selectedIndex = idx >= 0 ? idx : 0;
            }
        }

        function activate(i) {
            if (i < 0 || i >= profiles.length) return;
            PowerProfiles.profile = profiles[i];
            popupOpen = false;
        }

        function profileGlyph(p) {
            switch (p) {
                case PowerProfile.Performance: return "󱐋";
                case PowerProfile.Balanced:    return "󰾅";
                default:                       return "󱟦";
            }
        }
        function profileColor(p) {
            switch (p) {
                case PowerProfile.Performance: return "#ef4444";
                case PowerProfile.Balanced:    return "#eab308";
                default:                       return "#22c55e";
            }
        }
        function profileLabel(p) {
            switch (p) {
                case PowerProfile.Performance: return "Performance";
                case PowerProfile.Balanced:    return "Balanced";
                default:                       return "Power Saver";
            }
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 4
            Text {
                text: pp.profileGlyph(PowerProfiles.profile)
                color: pp.profileColor(PowerProfiles.profile)
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton
            onClicked: pp.popupOpen = !pp.popupOpen
            onWheel: (e) => {
                kbdBl.command = ["brightnessctl", "--device=dell::kbd_backlight",
                    "set", e.angleDelta.y > 0 ? "+1" : "1-"];
                kbdBl.startDetached();
            }
        }

        Process { id: kbdBl; command: [] }

        PopupWindow {
            id: ppPopup
            anchor.window: pp.parentBar
            anchor.rect.x: pp.mapToItem(pp.parentBar.contentItem, 0, 0).x + pp.width - implicitWidth
            anchor.rect.y: pp.parentBar.height + 2
            implicitWidth: 220
            implicitHeight: ppCol.implicitHeight + 16
            visible: pp.popupOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#78716c"
                border.width: 1
                focus: pp.popupOpen
                Keys.onPressed: (e) => {
                    const n = pp.profiles.length;
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        pp.selectedIndex = (pp.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        pp.selectedIndex = (pp.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        pp.activate(pp.selectedIndex);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Escape) {
                        pp.popupOpen = false;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: ppCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    Repeater {
                        model: pp.profiles
                        delegate: PowerProfileRow {
                            required property var modelData
                            required property int index
                            profile: modelData
                            highlighted: pp.selectedIndex === index
                            Layout.fillWidth: true
                            onPicked: pp.activate(index)
                            onHovered: pp.selectedIndex = index
                        }
                    }
                }
            }
        }

        HyprlandFocusGrab {
            active: pp.popupOpen
            windows: [ppPopup]
            onCleared: pp.popupOpen = false
        }
    }

    component PowerProfileRow: Rectangle {
        id: prow
        property int profile
        property bool highlighted: false
        signal picked()
        signal hovered()
        readonly property bool active: PowerProfiles.profile === profile
        implicitHeight: 32
        radius: 6
        color: prow.highlighted ? "#3b3531"
             : prow.active ? "#292524"
             : (rowMa.containsMouse ? "#231f1d" : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 10
            Text {
                text: {
                    switch (prow.profile) {
                        case PowerProfile.Performance: return "󱐋";
                        case PowerProfile.Balanced:    return "󰾅";
                        default:                       return "󱟦";
                    }
                }
                color: {
                    switch (prow.profile) {
                        case PowerProfile.Performance: return "#ef4444";
                        case PowerProfile.Balanced:    return "#eab308";
                        default:                       return "#22c55e";
                    }
                }
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                text: {
                    switch (prow.profile) {
                        case PowerProfile.Performance: return "Performance";
                        case PowerProfile.Balanced:    return "Balanced";
                        default:                       return "Power Saver";
                    }
                }
                color: "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
                font.bold: prow.active
            }
            Text {
                visible: prow.active
                text: "✓"
                color: "#22c55e"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: prow.picked()
            onContainsMouseChanged: if (containsMouse) prow.hovered()
        }
    }

    component BluetoothModule: Item {
        id: bt
        property var parentBar
        property bool popupOpen: false
        property int selectedIndex: 0
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool powered: adapter && adapter.enabled
        readonly property var connectedDevices: {
            const list = [];
            if (!Bluetooth.devices) return list;
            for (let i = 0; i < Bluetooth.devices.values.length; i++) {
                const d = Bluetooth.devices.values[i];
                if (d.connected) list.push(d);
            }
            return list;
        }
        readonly property var visibleDevices: {
            const all = (Bluetooth.devices ? Bluetooth.devices.values : []) || [];
            return all.filter(d => d.paired || d.connected).sort((a, b) => {
                if (a.connected !== b.connected) return a.connected ? -1 : 1;
                return (a.name || "").localeCompare(b.name || "");
            });
        }

        onPopupOpenChanged: if (popupOpen) selectedIndex = 0

        function activateDevice(i) {
            if (i < 0 || i >= visibleDevices.length) return;
            const d = visibleDevices[i];
            if (d.connected) d.disconnect();
            else d.connect();
        }

        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 16

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: !bt.powered ? "󰂲" : (bt.connectedDevices.length ? "󰂱" : "󰂯")
                color: !bt.powered ? "#78716c" : "#60a5fa"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Text {
                visible: bt.powered && bt.connectedDevices.length > 0
                text: bt.connectedDevices.length
                color: "#60a5fa"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 13
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (e.button === Qt.RightButton) {
                    if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled;
                } else {
                    bt.popupOpen = !bt.popupOpen;
                }
            }
        }

        PopupWindow {
            id: popup
            anchor.window: bt.parentBar
            anchor.rect.x: bt.mapToItem(bt.parentBar.contentItem, 0, 0).x + bt.width - implicitWidth
            anchor.rect.y: bt.parentBar.height
            implicitWidth: 300
            implicitHeight: contentCol.implicitHeight + 24
            visible: bt.popupOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#44403c"
                border.width: 1
                focus: bt.popupOpen
                Keys.onPressed: (e) => {
                    const n = bt.visibleDevices.length;
                    if (e.key === Qt.Key_Escape) {
                        bt.popupOpen = false;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_B && (e.modifiers & Qt.ControlModifier)) {
                        if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_S && (e.modifiers & Qt.ControlModifier)) {
                        if (bt.adapter) bt.adapter.discovering = !bt.adapter.discovering;
                        e.accepted = true;
                    } else if (n === 0) {
                        return;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        bt.selectedIndex = (bt.selectedIndex + 1) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        bt.selectedIndex = (bt.selectedIndex - 1 + n) % n;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        bt.activateDevice(bt.selectedIndex);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                        const d = bt.visibleDevices[bt.selectedIndex];
                        if (d) d.forget();
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: contentCol
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "󰂯  Bluetooth"
                            color: "#f5f5f4"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 14
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        BtToggle {
                            label: bt.powered ? "On" : "Off"
                            active: bt.powered
                            onClicked: { if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: "#44403c"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: bt.powered
                        spacing: 8
                        Text {
                            text: bt.adapter && bt.adapter.discovering ? "Scanning…" : "Devices"
                            color: "#a8a29e"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 12
                        }
                        Item { Layout.fillWidth: true }
                        BtToggle {
                            label: bt.adapter && bt.adapter.discovering ? "Stop" : "Scan"
                            active: bt.adapter && bt.adapter.discovering
                            onClicked: {
                                if (!bt.adapter) return;
                                bt.adapter.discovering = !bt.adapter.discovering;
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: bt.powered && deviceRepeater.count === 0
                        text: "No known devices"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !bt.powered
                        text: "Bluetooth is off"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        visible: bt.powered
                        Repeater {
                            id: deviceRepeater
                            model: bt.visibleDevices
                            delegate: BtDeviceRow {
                                required property var modelData
                                required property int index
                                device: modelData
                                highlighted: bt.selectedIndex === index
                                onHovered: bt.selectedIndex = index
                            }
                        }
                    }
                }
            }
        }

        HyprlandFocusGrab {
            active: bt.popupOpen
            windows: [popup]
            onCleared: bt.popupOpen = false
        }
    }

    component BtToggle: Rectangle {
        id: tg
        property string label: ""
        property bool active: false
        signal clicked()
        implicitWidth: lbl.implicitWidth + 16
        implicitHeight: 22
        radius: 11
        color: tg.active ? "#1d4ed8" : "#292524"
        border.color: tg.active ? "#3b82f6" : "#44403c"
        border.width: 1
        Text {
            id: lbl
            anchors.centerIn: parent
            text: tg.label
            color: "#f5f5f4"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.bold: tg.active
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: tg.clicked()
        }
    }

    component BtDeviceRow: Rectangle {
        id: dr
        property var device
        property bool highlighted: false
        signal hovered()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 6
        color: dr.highlighted ? "#3b3531" : (hover.containsMouse ? "#292524" : "transparent")

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8
            Text {
                text: dr.device && dr.device.connected ? "󰂱" : "󰂯"
                color: dr.device && dr.device.connected ? "#60a5fa" : "#78716c"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 14
            }
            Text {
                Layout.fillWidth: true
                text: dr.device ? (dr.device.name || dr.device.deviceName || dr.device.address) : ""
                color: "#f5f5f4"
                elide: Text.ElideRight
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
            }
            Text {
                visible: dr.device && dr.device.batteryAvailable
                text: dr.device ? Math.round(dr.device.battery * 100) + "%" : ""
                color: "#a8a29e"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
            }
            Text {
                visible: dr.device && dr.device.pairing
                text: "pairing…"
                color: "#eab308"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 11
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (e) => {
                if (!dr.device) return;
                if (e.button === Qt.RightButton) {
                    dr.device.forget();
                    return;
                }
                if (dr.device.connected) dr.device.disconnect();
                else dr.device.connect();
            }
            onContainsMouseChanged: if (containsMouse) dr.hovered()
        }
    }

    component TrayItem: Item {
        id: tray
        property SystemTrayItem item
        Layout.fillHeight: true
        implicitWidth: 28

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 4
            color: hoverArea.containsMouse ? "#292524" : "transparent"
            opacity: tray.item && tray.item.status === Status.Passive ? 0.5 : 1.0
        }

        IconImage {
            anchors.centerIn: parent
            implicitSize: 18
            source: tray.item ? tray.item.icon : ""
            asynchronous: true
        }

        QsMenuAnchor {
            id: menuAnchor
            anchor.window: bar
            anchor.item: tray
            anchor.edges: Edges.Bottom
            menu: tray.item ? tray.item.menu : null
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: (e) => {
                if (!tray.item) return;
                if (e.button === Qt.LeftButton) {
                    if (tray.item.onlyMenu) menuAnchor.open();
                    else tray.item.activate();
                } else if (e.button === Qt.MiddleButton) {
                    tray.item.secondaryActivate();
                } else if (e.button === Qt.RightButton) {
                    if (tray.item.hasMenu) menuAnchor.open();
                }
            }
            onWheel: (e) => {
                if (!tray.item) return;
                if (e.angleDelta.y !== 0) tray.item.scroll(e.angleDelta.y, false);
                if (e.angleDelta.x !== 0) tray.item.scroll(e.angleDelta.x, true);
            }
        }
    }
}
