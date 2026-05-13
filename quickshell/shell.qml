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

                    BluetoothModule {
                        id: btMod
                        parentBar: bar
                        onNavigateNext: { popupOpen = false; sndMod.openAt(0) }
                        onNavigatePrev: { popupOpen = false; sysMod.openAt(-1) }
                    }
                    BarSep {}

                    SoundModule {
                        id: sndMod
                        parentBar: bar
                        onNavigateNext: { popupOpen = false; bellMod.openAt(0) }
                        onNavigatePrev: { popupOpen = false; btMod.openAt(-1) }
                    }

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

                    NotifBell {
                        id: bellMod
                        parentBar: bar
                        onNavigateNext: sysMod.openAt(0)
                        onNavigatePrev: { notifs.closeCenter(); sndMod.openAt(-1) }
                    }
                    BarSep {}

                    SystemModule {
                        id: sysMod
                        parentBar: bar
                        onNavigateNext: { popupOpen = false; btMod.openAt(0) }
                        onNavigatePrev: { popupOpen = false; bellMod.openAt(-1) }
                    }
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
        // tabIndex: 0 = DnD button, 1 = Clear button, 2+ = history[tabIndex-2]
        property int tabIndex: 0
        readonly property int tabStopCount: 2 + notifs.historyList.length
        readonly property int selectedIndex: bell.tabIndex >= 2 ? bell.tabIndex - 2 : -1
        signal navigateNext()
        signal navigatePrev()
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 14

        function cycleTab(delta) {
            const n = bell.tabStopCount;
            if (n <= 0) return;
            bell.tabIndex = (bell.tabIndex + delta + n) % n;
        }
        function openAt(idx) {
            notifs.openCenter();
            const n = bell.tabStopCount;
            bell.tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
        }

        Connections {
            target: notifs
            function onCenterOpenChanged() { if (notifs.centerOpen) bell.tabIndex = 0 }
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
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        notifs.closeCenter();
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        bell.navigateNext();
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        bell.navigatePrev();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        bell.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        bell.cycleTab(-1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (bell.tabIndex === 0) notifs.dnd = !notifs.dnd;
                        else if (bell.tabIndex === 1) notifs.clearHistory();
                        else {
                            const entry = notifs.historyList[bell.selectedIndex];
                            if (entry) notifs.dismissHistoryEntry(entry.id);
                        }
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        if (n > 0) bell.tabIndex = bell.tabIndex < 2 ? 2 :
                            (bell.selectedIndex + 1 < n ? bell.tabIndex + 1 : 2);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        if (n > 0) bell.tabIndex = bell.tabIndex < 2 ? 2 :
                            (bell.selectedIndex > 0 ? bell.tabIndex - 1 : 1 + n);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                        if (n > 0 && bell.selectedIndex >= 0) {
                            const entry = notifs.historyList[bell.selectedIndex];
                            if (entry) notifs.dismissHistoryEntry(entry.id);
                            if (bell.selectedIndex >= notifs.historyList.length)
                                bell.tabIndex = Math.max(1, 1 + notifs.historyList.length);
                        }
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
                            highlighted: bell.tabIndex === 0
                            onClicked: { bell.tabIndex = 0; notifs.dnd = !notifs.dnd }
                        }
                        BtToggle {
                            label: "Clear"
                            active: false
                            highlighted: bell.tabIndex === 1
                            onClicked: { bell.tabIndex = 1; notifs.clearHistory() }
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
                                onHovered: bell.tabIndex = index + 2
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

    component SystemModule: Item {
        id: sys
        property var parentBar
        property bool popupOpen: false
        signal navigateNext()
        signal navigatePrev()

        // Sections (in tab order):
        //   0..2     : Power profile (Performance/Balanced/PowerSaver)
        //   3        : Screen brightness slider
        //   4        : Keyboard backlight slider
        //   5..9     : Power actions (Lock/Suspend/Logout/Reboot/Shutdown)
        property int tabIndex: 0
        readonly property var profiles: [PowerProfile.Performance, PowerProfile.Balanced, PowerProfile.PowerSaver]
        readonly property var actions: [
            { glyph: "󰌾", color: "#a8a29e", label: "Lock",     cmd: ["loginctl", "lock-session"] },
            { glyph: "󰤄", color: "#60a5fa", label: "Suspend",  cmd: ["systemctl", "suspend"] },
            { glyph: "󰍃", color: "#eab308", label: "Logout",   cmd: ["hyprctl", "dispatch", "exit"] },
            { glyph: "󰜉", color: "#f97316", label: "Reboot",   cmd: ["systemctl", "reboot"] },
            { glyph: "⏻",  color: "#ef4444", label: "Shutdown", cmd: ["systemctl", "poweroff"] },
        ]

        // Brightness state
        property real screenLevel: 0.5
        property real kbLevel: 0
        property int kbMax: 2

        Layout.fillHeight: true
        implicitWidth: 32

        function activateProfile(i) {
            if (i < 0 || i >= profiles.length) return;
            PowerProfiles.profile = profiles[i];
        }
        function activateAction(i) {
            if (i < 0 || i >= actions.length) return;
            actionProc.command = actions[i].cmd;
            actionProc.startDetached();
            popupOpen = false;
        }
        function setScreen(v) {
            const pct = Math.round(Math.max(0, Math.min(1, v)) * 100);
            screenLevel = pct / 100;
            setScreenProc.command = ["brightnessctl", "set", pct + "%"];
            setScreenProc.startDetached();
        }
        function setKb(v) {
            const raw = Math.round(Math.max(0, Math.min(1, v)) * kbMax);
            kbLevel = kbMax > 0 ? raw / kbMax : 0;
            setKbProc.command = ["brightnessctl", "--device=dell::kbd_backlight", "set", String(raw)];
            setKbProc.startDetached();
        }
        function refreshBrightness() {
            getScreenProc.running = false; getScreenProc.running = true;
            getKbProc.running = false; getKbProc.running = true;
        }
        function activateTab() {
            if (tabIndex <= 2) activateProfile(tabIndex);
            else if (tabIndex === 3) {}  // slider: use ←/→
            else if (tabIndex === 4) {}
            else activateAction(tabIndex - 5);
        }
        function cycleTab(delta) {
            const n = 10;
            tabIndex = (tabIndex + delta + n) % n;
        }
        function openAt(idx) {
            popupOpen = true;
            tabIndex = idx < 0 ? 9 : Math.min(idx, 9);
            refreshBrightness();
        }
        onPopupOpenChanged: if (popupOpen) {
            const i = profiles.indexOf(PowerProfiles.profile);
            tabIndex = i >= 0 ? i : 0;
            refreshBrightness();
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
            onClicked: sys.popupOpen = !sys.popupOpen
        }

        Process { id: actionProc; command: [] }
        Process { id: setScreenProc; command: [] }
        Process { id: setKbProc; command: [] }
        Process {
            id: getScreenProc
            command: ["sh", "-c", "echo $(brightnessctl get) $(brightnessctl max)"]
            running: false
            stdout: SplitParser {
                onRead: (line) => {
                    const parts = line.trim().split(/\s+/);
                    const cur = parseInt(parts[0]); const max = parseInt(parts[1]);
                    if (!isNaN(cur) && !isNaN(max) && max > 0) sys.screenLevel = cur / max;
                }
            }
        }
        Process {
            id: getKbProc
            command: ["sh", "-c", "echo $(brightnessctl --device=dell::kbd_backlight get) $(brightnessctl --device=dell::kbd_backlight max)"]
            running: false
            stdout: SplitParser {
                onRead: (line) => {
                    const parts = line.trim().split(/\s+/);
                    const cur = parseInt(parts[0]); const max = parseInt(parts[1]);
                    if (!isNaN(cur) && !isNaN(max)) {
                        sys.kbMax = max;
                        sys.kbLevel = max > 0 ? cur / max : 0;
                    }
                }
            }
        }
        Timer {
            interval: 4000
            running: sys.popupOpen
            repeat: true
            onTriggered: sys.refreshBrightness()
        }

        PopupWindow {
            id: sysPopup
            anchor.window: sys.parentBar
            anchor.rect.x: sys.parentBar.width - implicitWidth - 8
            anchor.rect.y: sys.parentBar.height + 2
            implicitWidth: 340
            implicitHeight: sysCol.implicitHeight + 28
            visible: sys.popupOpen
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: "#1c1917"
                radius: 8
                border.color: "#78716c"
                border.width: 1
                focus: sys.popupOpen
                Keys.onPressed: (e) => {
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        sys.popupOpen = false;
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        sys.navigateNext();
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        sys.navigatePrev();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        sys.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        sys.cycleTab(-1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        if (sys.tabIndex === 3) sys.setScreen(sys.screenLevel + 0.05);
                        else if (sys.tabIndex === 4) sys.setKb(sys.kbLevel + 1 / Math.max(1, sys.kbMax));
                        else sys.cycleTab(1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        if (sys.tabIndex === 3) sys.setScreen(sys.screenLevel - 0.05);
                        else if (sys.tabIndex === 4) sys.setKb(sys.kbLevel - 1 / Math.max(1, sys.kbMax));
                        else sys.cycleTab(-1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        sys.activateTab();
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: sysCol
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    Text {
                        text: "POWER PROFILE"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: -8
                        spacing: 6
                        Repeater {
                            model: sys.profiles
                            delegate: ProfileChip {
                                required property var modelData
                                required property int index
                                profile: modelData
                                highlighted: sys.tabIndex === index
                                Layout.fillWidth: true
                                onPicked: sys.activateProfile(index)
                                onHovered: sys.tabIndex = index
                            }
                        }
                    }

                    Text {
                        text: "BACKLIGHT"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: -8
                        spacing: 8
                        BrightnessRow {
                            Layout.fillWidth: true
                            glyph: "󰃞"
                            label: "Screen"
                            value: sys.screenLevel
                            highlighted: sys.tabIndex === 3
                            onMoved: (v) => sys.setScreen(v)
                            onHovered: sys.tabIndex = 3
                        }
                        BrightnessRow {
                            Layout.fillWidth: true
                            glyph: "󰌌"
                            label: "Keyboard"
                            value: sys.kbLevel
                            highlighted: sys.tabIndex === 4
                            onMoved: (v) => sys.setKb(v)
                            onHovered: sys.tabIndex = 4
                        }
                    }

                    Text {
                        text: "SYSTEM"
                        color: "#78716c"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 9
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: -8
                        spacing: 2
                        Repeater {
                            model: sys.actions
                            delegate: PowerMenuRow {
                                required property var modelData
                                required property int index
                                entry: modelData
                                selected: sys.tabIndex === index + 5
                                Layout.fillWidth: true
                                onPicked: sys.activateAction(index)
                                onHovered: sys.tabIndex = index + 5
                            }
                        }
                    }
                }
            }
        }

        HyprlandFocusGrab {
            active: sys.popupOpen
            windows: [sysPopup]
            onCleared: sys.popupOpen = false
        }
    }

    component ProfileChip: Rectangle {
        id: pc
        property int profile
        property bool highlighted: false
        signal picked()
        signal hovered()
        readonly property bool active: PowerProfiles.profile === profile
        readonly property color accent: pc.profile === PowerProfile.Performance ? "#ef4444"
            : pc.profile === PowerProfile.Balanced ? "#eab308" : "#22c55e"
        implicitHeight: 62
        radius: 8
        color: pc.active ? Qt.rgba(pc.accent.r, pc.accent.g, pc.accent.b, 0.18)
             : (pcMa.containsMouse ? "#292524" : "#1f1c1a")
        border.color: pc.highlighted ? "#fafaf9" : (pc.active ? pc.accent : "#3a3633")
        border.width: pc.highlighted ? 2 : 1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 3
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pc.profile === PowerProfile.Performance ? "󱐋"
                    : pc.profile === PowerProfile.Balanced ? "󰾅" : "󱟦"
                color: pc.accent
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 20
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pc.profile === PowerProfile.Performance ? "Perf"
                    : pc.profile === PowerProfile.Balanced ? "Balanced" : "Save"
                color: pc.active ? "#fafaf9" : "#a8a29e"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
                font.bold: pc.active
            }
        }
        MouseArea {
            id: pcMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pc.picked()
            onContainsMouseChanged: if (containsMouse) pc.hovered()
        }
    }

    component BrightnessRow: RowLayout {
        id: br
        property string glyph: ""
        property string label: ""
        property real value: 0
        property bool highlighted: false
        signal moved(real v)
        signal hovered()
        spacing: 10
        Text {
            text: br.glyph
            color: br.highlighted ? "#fafaf9" : "#d6d3d1"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 16
            Layout.preferredWidth: 20
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            text: br.label
            color: br.highlighted ? "#fafaf9" : "#a8a29e"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.bold: br.highlighted
            Layout.preferredWidth: 70
        }
        VolumeSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 12
            value: br.value
            border.color: br.highlighted ? "#fafaf9" : "#44403c"
            border.width: br.highlighted ? 2 : 1
            onMoved: br.moved(value)
            HoverHandler { onHoveredChanged: if (hovered) br.hovered() }
        }
        Text {
            text: Math.round(br.value * 100) + "%"
            color: br.highlighted ? "#fafaf9" : "#d6d3d1"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.bold: br.highlighted
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
        }
    }

    component PowerMenuModule: Item {
        id: pm
        property var parentBar
        property bool popupOpen: false
        property int selectedIndex: 0
        signal navigateNext()
        signal navigatePrev()
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
        function openAt(idx) {
            popupOpen = true;
            const n = entries.length;
            selectedIndex = idx < 0 ? n - 1 : Math.min(idx, n - 1);
        }
        function cycleIndex(delta) {
            const n = entries.length;
            if (n <= 0) return;
            selectedIndex = (selectedIndex + delta + n) % n;
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
            anchor.rect.x: pm.parentBar.width - implicitWidth - 8
            anchor.rect.y: pm.parentBar.height + 2
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
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        pm.navigateNext();
                        e.accepted = true;
                        return;
                    }
                    if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        pm.navigatePrev();
                        e.accepted = true;
                        return;
                    }
                    const fwd = e.key === Qt.Key_Down || e.key === Qt.Key_J
                        || e.key === Qt.Key_Right || e.key === Qt.Key_L
                        || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier));
                    const back = e.key === Qt.Key_Up || e.key === Qt.Key_K
                        || e.key === Qt.Key_Left || e.key === Qt.Key_H
                        || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier));
                    if (fwd) {
                        pm.cycleIndex(1);
                        e.accepted = true;
                    } else if (back) {
                        pm.cycleIndex(-1);
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
        implicitHeight: 34
        radius: 6
        color: pmrow.selected ? "#2d2724" : (rowMa.containsMouse ? "#262220" : "transparent")
        border.color: pmrow.selected ? (pmrow.entry ? pmrow.entry.color : "#fafaf9") : "transparent"
        border.width: pmrow.selected ? 1 : 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12
            Text {
                text: pmrow.entry ? pmrow.entry.glyph : ""
                color: pmrow.entry ? pmrow.entry.color : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 15
                Layout.preferredWidth: 18
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                Layout.fillWidth: true
                text: pmrow.entry ? pmrow.entry.label : ""
                color: pmrow.selected ? "#fafaf9" : "#e7e5e4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
                font.bold: pmrow.selected
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
        // Tab layout:
        //   0                       : output mute toggle
        //   1..outCount             : output device i = tabIndex - 1
        //   outCount+1              : input mute toggle
        //   outCount+2..tabStopCount: input device i = tabIndex - outCount - 2
        property int tabIndex: 0
        signal navigateNext()
        signal navigatePrev()
        readonly property int outCount: outputDevices.length
        readonly property int inCount: inputDevices.length
        readonly property int tabStopCount: outCount + inCount + 2
        readonly property int outSelectedIndex: tabIndex >= 1 && tabIndex <= outCount ? tabIndex - 1 : -1
        readonly property int inSelectedIndex: tabIndex >= outCount + 2 ? tabIndex - outCount - 2 : -1
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var source: Pipewire.defaultAudioSource
        readonly property var outputDevices: {
            if (!Pipewire.nodes) return [];
            return (Pipewire.nodes.values || []).filter(n => n.isSink && !n.isStream && n.audio);
        }
        readonly property var inputDevices: {
            if (!Pipewire.nodes) return [];
            return (Pipewire.nodes.values || []).filter(n => !n.isSink && !n.isStream && n.audio);
        }
        Layout.fillHeight: true
        implicitWidth: row.implicitWidth + 16

        onPopupOpenChanged: if (popupOpen) {
            const idx = outputDevices.indexOf(sink);
            tabIndex = idx >= 0 ? idx + 1 : 0;
        }

        function cycleTab(delta) {
            const n = tabStopCount;
            if (n <= 0) return;
            tabIndex = (tabIndex + delta + n) % n;
        }
        function openAt(idx) {
            popupOpen = true;
            const n = tabStopCount;
            tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
        }
        function adjustVolume(delta) {
            if (!sink || !sink.audio) return;
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
        }
        function activateOutput(i) {
            if (i < 0 || i >= outputDevices.length) return;
            Pipewire.preferredDefaultAudioSink = outputDevices[i];
        }
        function activateInput(i) {
            if (i < 0 || i >= inputDevices.length) return;
            Pipewire.preferredDefaultAudioSource = inputDevices[i];
        }
        function activateTabIndex() {
            if (tabIndex === 0) {
                if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
            } else if (tabIndex <= outCount) {
                activateOutput(tabIndex - 1);
            } else if (tabIndex === outCount + 1) {
                if (source && source.audio) source.audio.muted = !source.audio.muted;
            } else {
                activateInput(tabIndex - outCount - 2);
            }
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
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        snd.popupOpen = false;
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        snd.navigateNext();
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        snd.navigatePrev();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Down || e.key === Qt.Key_J
                             || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        snd.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K
                             || e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        snd.cycleTab(-1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        snd.activateTabIndex();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_M) {
                        if (snd.sink && snd.sink.audio) snd.sink.audio.muted = !snd.sink.audio.muted;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                        snd.adjustVolume(0.05);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Minus) {
                        snd.adjustVolume(-0.05);
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
                        selectedIndex: snd.outSelectedIndex !== undefined ? snd.outSelectedIndex : -1
                        toggleHighlighted: snd.tabIndex === 0
                        onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                        onDeviceHovered: (idx) => snd.tabIndex = idx + 1
                        onToggleHovered: snd.tabIndex = 0
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: "#44403c" }

                    AudioSection {
                        Layout.fillWidth: true
                        title: "󰍬  Input"
                        node: snd.source
                        isSink: false
                        selectedIndex: snd.inSelectedIndex !== undefined ? snd.inSelectedIndex : -1
                        toggleHighlighted: snd.tabIndex === snd.outCount + 1
                        onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                        onDeviceHovered: (idx) => snd.tabIndex = snd.outCount + 2 + idx
                        onToggleHovered: snd.tabIndex = snd.outCount + 1
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
        property bool toggleHighlighted: false
        signal launchMixer()
        signal deviceHovered(int idx)
        signal toggleHovered()
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
                highlighted: section.toggleHighlighted
                onClicked: {
                    section.toggleHovered();
                    if (section.node && section.node.audio)
                        section.node.audio.muted = !section.node.audio.muted;
                }
                HoverHandler { onHoveredChanged: if (hovered) section.toggleHovered() }
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
        implicitHeight: 10
        radius: height / 2
        color: "#1f1c1a"
        border.color: "#44403c"
        border.width: 1

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 1
            width: Math.max(0, Math.min(parent.width - 2, (parent.width - 2) * vs.value))
            radius: height / 2
            color: "#3b82f6"
        }

        Rectangle {
            id: thumb
            width: 14; height: 14
            radius: 7
            color: "#fafaf9"
            border.color: "#3b82f6"
            border.width: 2
            anchors.verticalCenter: parent.verticalCenter
            x: Math.max(-width / 2 + 1,
                Math.min(parent.width - width / 2 - 1,
                    (parent.width - 2) * vs.value - width / 2))
            visible: dragArea.containsMouse || dragArea.pressed
        }

        MouseArea {
            id: dragArea
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
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
        signal navigateNext()
        signal navigatePrev()
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
        function openAt(idx) {
            popupOpen = true;
            const n = profiles.length;
            selectedIndex = idx < 0 ? n - 1 : Math.min(idx, n - 1);
        }
        function cycleIndex(delta) {
            const n = profiles.length;
            if (n <= 0) return;
            selectedIndex = (selectedIndex + delta + n) % n;
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
            anchor.item: pp
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 2
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
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        pp.navigateNext();
                        e.accepted = true;
                        return;
                    }
                    if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        pp.navigatePrev();
                        e.accepted = true;
                        return;
                    }
                    const fwd = e.key === Qt.Key_Down || e.key === Qt.Key_J
                        || e.key === Qt.Key_Right || e.key === Qt.Key_L
                        || (e.key === Qt.Key_Tab && !(e.modifiers & Qt.ShiftModifier));
                    const back = e.key === Qt.Key_Up || e.key === Qt.Key_K
                        || e.key === Qt.Key_Left || e.key === Qt.Key_H
                        || (e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier));
                    if (fwd) {
                        pp.cycleIndex(1);
                        e.accepted = true;
                    } else if (back) {
                        pp.cycleIndex(-1);
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
        // tabIndex: 0 = Power toggle, 1 = Scan toggle, 2+ = device[tabIndex-2]
        property int tabIndex: 0
        signal navigateNext()
        signal navigatePrev()
        readonly property int tabStopCount: 2 + visibleDevices.length
        readonly property int selectedIndex: tabIndex >= 2 ? tabIndex - 2 : -1
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

        onPopupOpenChanged: if (popupOpen) tabIndex = 0

        function cycleTab(delta) {
            const n = tabStopCount;
            if (n <= 0) return;
            tabIndex = (tabIndex + delta + n) % n;
        }
        function openAt(idx) {
            popupOpen = true;
            const n = tabStopCount;
            tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
        }
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
            anchor.item: bt
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom | Edges.Left
            anchor.margins.top: 2
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
                    const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                    if (e.key === Qt.Key_Escape) {
                        bt.popupOpen = false;
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                        bt.navigateNext();
                        e.accepted = true;
                    } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                        bt.navigatePrev();
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        bt.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        bt.cycleTab(-1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (bt.tabIndex === 0 && bt.adapter) bt.adapter.enabled = !bt.adapter.enabled;
                        else if (bt.tabIndex === 1 && bt.adapter) bt.adapter.discovering = !bt.adapter.discovering;
                        else bt.activateDevice(bt.selectedIndex);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                        if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                            (bt.selectedIndex + 1 < n ? bt.tabIndex + 1 : 2);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                        if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                            (bt.selectedIndex > 0 ? bt.tabIndex - 1 : 1 + n);
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
                            highlighted: bt.tabIndex === 0
                            onClicked: { bt.tabIndex = 0; if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled }
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
                            highlighted: bt.tabIndex === 1
                            onClicked: {
                                bt.tabIndex = 1;
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
                                onHovered: bt.tabIndex = index + 2
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
        property bool highlighted: false
        signal clicked()
        implicitWidth: lbl.implicitWidth + 16
        implicitHeight: 22
        radius: 11
        color: tg.active ? "#1d4ed8" : "#292524"
        border.color: tg.highlighted ? "#fafaf9" : (tg.active ? "#3b82f6" : "#44403c")
        border.width: tg.highlighted ? 2 : 1
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
