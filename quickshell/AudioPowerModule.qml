// Combined Sound + Power popup: tab strip at top with Sound / Power tabs.
// Owns the bar speaker icon. The battery icon in the bar opens this popup
// with the Power tab pre-selected via openAt("power").
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: ap
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override set by openTab(name, from). Fallback: own icon.
    property Item flyoutAnchor: null
    property Item _openAnchor: null
    property string activeTab: "sound"
    signal navigateNext()
    signal navigatePrev()

    // ===== Sound state =====
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
    readonly property int outCount: outputDevices.length
    readonly property int inCount: inputDevices.length
    // Sound-tab navigation index (matches old SoundModule).
    property int sndIndex: 0
    readonly property int sndStopCount: outCount + inCount + 2
    readonly property int outSelectedIndex: sndIndex >= 1 && sndIndex <= outCount ? sndIndex - 1 : -1
    readonly property int inSelectedIndex: sndIndex >= outCount + 2 ? sndIndex - outCount - 2 : -1

    // The section the sound-tab cursor is currently in: output (sink) for
    // indices 0..outCount, input (source) beyond that. Left/Right adjust this
    // node's volume so the arrows feel the same as the Power tab's sliders.
    readonly property var sndActiveNode: sndIndex >= outCount + 1 ? source : sink
    function adjustVolume(delta) {
        const node = sndActiveNode;
        if (!node || !node.audio) return;
        node.audio.volume = Math.max(0, Math.min(1, node.audio.volume + delta));
    }
    function toggleSndMute() {
        const node = sndActiveNode;
        if (node && node.audio) node.audio.muted = !node.audio.muted;
    }
    function activateOutput(i) {
        if (i < 0 || i >= outputDevices.length) return;
        Pipewire.preferredDefaultAudioSink = outputDevices[i];
    }
    function activateInput(i) {
        if (i < 0 || i >= inputDevices.length) return;
        Pipewire.preferredDefaultAudioSource = inputDevices[i];
    }
    function activateSndIndex() {
        if (sndIndex === 0) {
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
        } else if (sndIndex <= outCount) {
            activateOutput(sndIndex - 1);
        } else if (sndIndex === outCount + 1) {
            if (source && source.audio) source.audio.muted = !source.audio.muted;
        } else {
            activateInput(sndIndex - outCount - 2);
        }
    }
    function cycleSnd(delta) {
        const n = sndStopCount;
        if (n > 0) sndIndex = (sndIndex + delta + n) % n;
    }

    // ===== Power state =====
    readonly property var profiles: [PowerProfile.Performance, PowerProfile.Balanced, PowerProfile.PowerSaver]
    // Session actions (Sleep / Reboot / Shutdown). This is the shell's power
    // menu — the `powermenu` global shortcut opens this tab.
    readonly property var sessionActions: [
        { glyph: "󰒲", label: "Sleep",    accent: Theme.accent.purple, cmd: ["systemctl", "suspend"] },
        { glyph: "󰜉", label: "Reboot",   accent: Theme.accent.orange, cmd: ["systemctl", "reboot"] },
        { glyph: "󰐥", label: "Shutdown", accent: Theme.accent.red,    cmd: ["systemctl", "poweroff"] },
    ]
    // pwrIndex stops: 0..2 profiles, 3 = screen slider, 4 = kb slider,
    // 5..7 session actions (Sleep / Reboot / Shutdown).
    property int pwrIndex: 0
    property real screenLevel: 0.5
    property real kbLevel: 0
    property int kbMax: 2

    function activateProfile(i) {
        if (i < 0 || i >= profiles.length) return;
        PowerProfiles.profile = profiles[i];
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
    function runSession(i) {
        const a = sessionActions[i];
        if (!a) return;
        sessionProc.command = a.cmd;
        sessionProc.startDetached();
        popupOpen = false;
    }
    function cyclePwr(delta) { pwrIndex = (pwrIndex + delta + 8) % 8; }
    function activatePwr() {
        if (pwrIndex <= 2) activateProfile(pwrIndex);
        else if (pwrIndex >= 5) runSession(pwrIndex - 5);
    }

    // ===== Tab + popup control =====
    // Toggle between the two tabs (Sound ↔ Power).
    function cycleActiveTab() { setTab(activeTab === "sound" ? "power" : "sound"); }
    function setTab(name) {
        if (activeTab === name) return;
        activeTab = name;
        if (name === "sound") {
            const idx = outputDevices.indexOf(sink);
            sndIndex = idx >= 0 ? idx + 1 : 0;
        } else if (name === "power") {
            const i = profiles.indexOf(PowerProfiles.profile);
            pwrIndex = i >= 0 ? i : 0;
            refreshBrightness();
        }
    }
    function openAt(tab) {
        if (tab) setTab(tab);
        popupOpen = true;
    }
    // Toggle the popup; if it's already on this tab, close it. Otherwise
    // switch to the tab and open. Called from the per-tab bar icons.
    // `from` (optional) re-anchors the flyout under the bar item that opened
    // it (battery satellite icon, overflow rows) so the tail points at what
    // was actually clicked. Omitted → default anchor.
    function openTab(name, from) {
        _openAnchor = from ?? null;
        if (popupOpen && activeTab === name) { popupOpen = false; }
        else { setTab(name); popupOpen = true; }
    }

    onPopupOpenChanged: if (popupOpen) {
        if (activeTab === "sound") {
            const idx = outputDevices.indexOf(sink);
            sndIndex = idx >= 0 ? idx + 1 : 0;
        } else {
            const i = profiles.indexOf(PowerProfiles.profile);
            pwrIndex = i >= 0 ? i : 0;
            refreshBrightness();
        }
    }

    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 16

    // ===== Bar speaker rendering (sound) =====
    PwObjectTracker { objects: [ap.sink, ap.source] }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            text: {
                if (!ap.sink || !ap.sink.audio) return "󰕾";
                if (ap.sink.audio.muted) return "󰖁";
                const v = ap.sink.audio.volume;
                if (v < 0.34) return "󰕿";
                if (v < 0.67) return "󰖀";
                return "󰕾";
            }
            color: ap.sink && ap.sink.audio && ap.sink.audio.muted ? Theme.mutedDeep : "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            text: {
                if (!ap.sink || !ap.sink.audio) return "";
                if (ap.sink.audio.muted) return "muted";
                return Math.round(ap.sink.audio.volume * 100) + "%";
            }
            color: ap.sink && ap.sink.audio && ap.sink.audio.muted ? Theme.mutedDeep : "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (e.button === Qt.RightButton) {
                if (ap.sink && ap.sink.audio) ap.sink.audio.muted = !ap.sink.audio.muted;
                return;
            }
            ap.openTab("sound");
        }
        onWheel: (e) => {
            if (!ap.sink || !ap.sink.audio) return;
            ap.sink.audio.volume = Math.max(0, Math.min(1,
                ap.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
        }
    }

    // ===== Power-related processes =====
    Process { id: setScreenProc; command: [] }
    Process { id: setKbProc; command: [] }
    Process { id: sessionProc; command: [] }
    Process {
        id: getScreenProc
        command: ["sh", "-c", "echo $(brightnessctl get) $(brightnessctl max)"]
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.trim().split(/\s+/);
                const cur = parseInt(parts[0]); const max = parseInt(parts[1]);
                if (!isNaN(cur) && !isNaN(max) && max > 0) ap.screenLevel = cur / max;
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
                    ap.kbMax = max;
                    ap.kbLevel = max > 0 ? cur / max : 0;
                }
            }
        }
    }
    Timer {
        interval: 4000
        running: ap.popupOpen && ap.activeTab === "power"
        repeat: true
        onTriggered: ap.refreshBrightness()
    }

    // ===== Popup =====
    HoverHandler { id: apHover }
    BarTooltip {
        bar: ap.parentBar
        target: ap
        text: "Audio & Power · Super+S"
        active: apHover.hovered && !ap.popupOpen
    }

    BarFlyout {
        id: apPopup
        parentBar: ap.parentBar
        anchorItem: ap._openAnchor ?? ap.flyoutAnchor ?? ap
        open: ap.popupOpen
        cardWidth: settingsStore.flyoutSize("audiopower", "w", 380)
        // Fixed height sized for the larger tab content so the popup surface
        // doesn't resize when switching tabs (which causes visible jitter).
        cardHeight: settingsStore.flyoutSize("audiopower", "h", 480)
        pinned: ap.pinned
        onDismissed: ap.popupOpen = false
        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (e.key === Qt.Key_Escape) { ap.popupOpen = false; e.accepted = true; }
            else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                ap.navigateNext(); e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                ap.navigatePrev(); e.accepted = true;
            } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                // Tab / Shift+Tab switch tabs (only two, so either direction).
                ap.cycleActiveTab(); e.accepted = true;
            } else if ((e.modifiers & Qt.ShiftModifier)
                    && (e.key === Qt.Key_Right || e.key === Qt.Key_L
                     || e.key === Qt.Key_Left  || e.key === Qt.Key_H)) {
                // Shift+←/→ also switches tabs (consistent with Connectivity);
                // checked before the plain arrows that adjust volume.
                ap.cycleActiveTab(); e.accepted = true;
            } else if (ap.activeTab === "sound") {
                // Up/Down move between rows (mute toggles + devices);
                // Left/Right (and +/-) adjust the selected section's volume.
                if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    ap.cycleSnd(1); e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    ap.cycleSnd(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L
                        || e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                    ap.adjustVolume(0.05); e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H
                        || e.key === Qt.Key_Minus) {
                    ap.adjustVolume(-0.05); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    ap.activateSndIndex(); e.accepted = true;
                } else if (e.key === Qt.Key_M) {
                    ap.toggleSndMute(); e.accepted = true;
                }
            } else if (ap.activeTab === "power") {
                if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    ap.cyclePwr(1); e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    ap.cyclePwr(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                    if (ap.pwrIndex === 3) ap.setScreen(ap.screenLevel + 0.05);
                    else if (ap.pwrIndex === 4) ap.setKb(ap.kbLevel + 1 / Math.max(1, ap.kbMax));
                    else ap.cyclePwr(1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    if (ap.pwrIndex === 3) ap.setScreen(ap.screenLevel - 0.05);
                    else if (ap.pwrIndex === 4) ap.setKb(ap.kbLevel - 1 / Math.max(1, ap.kbMax));
                    else ap.cyclePwr(-1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    ap.activatePwr(); e.accepted = true;
                }
            }
        }

        ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                Text {
                    Layout.fillWidth: true
                    text: "Audio & Power"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                // ===== Header: pin + tab strip =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: ap.pinned
                        onToggled: ap.pinned = !ap.pinned
                    }
                    TabStrip {
                        Layout.fillWidth: true
                        activeId: ap.activeTab
                        onPicked: (id) => ap.setTab(id)
                        tabs: [
                            { glyph: "󰕾", label: "Sound", accent: Theme.accent.blue, id: "sound" },
                            { glyph: "⏻", label: "Power", accent: Theme.accent.red,  id: "power" }
                        ]
                    }
                }

                // ===== Tab content =====
                // Fill the rest of the popup so panes always render against
                // the same envelope — switching tabs no longer resizes anything.
                Loader {
                    id: paneLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    active: ap.popupOpen
                    opacity: 0
                    transformOrigin: Item.Top
                    sourceComponent: !ap.popupOpen ? null
                                   : ap.activeTab === "power" ? powerPane
                                   : soundPane
                    onLoaded: paneInAnim.restart()
                    ParallelAnimation {
                        id: paneInAnim
                        NumberAnimation { target: paneLoader; property: "opacity"; from: 0.0; to: 1.0; duration: Theme.duration.normal; easing.type: Theme.easing.standard }
                        NumberAnimation { target: paneLoader; property: "scale"; from: 0.97; to: 1.0; duration: Theme.duration.normal; easing.type: Theme.easing.standard }
                    }
                }

                // Keyboard hint footer
                Text {
                    Layout.fillWidth: true
                    text: "Tab tabs · ↑↓ move · ←→ adjust · ↵ select"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.65
                }

                Component {
                    id: soundPane
                    Flickable {
                        id: sndFlick
                        clip: true
                        contentWidth: width
                        contentHeight: sndCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ThinScrollBar {}
                        ColumnLayout {
                            id: sndCol
                            width: sndFlick.width
                            spacing: Theme.spacing.md
                            AudioSection {
                                Layout.fillWidth: true
                                title: "OUTPUT"
                                node: ap.sink
                                isSink: true
                                selectedIndex: ap.outSelectedIndex !== undefined ? ap.outSelectedIndex : -1
                                toggleHighlighted: ap.sndIndex === 0
                                sliderActive: ap.sndIndex <= ap.outCount
                                onDeviceHovered: (idx) => ap.sndIndex = idx + 1
                                onToggleHovered: ap.sndIndex = 0
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                            AudioSection {
                                Layout.fillWidth: true
                                title: "INPUT"
                                node: ap.source
                                isSink: false
                                selectedIndex: ap.inSelectedIndex !== undefined ? ap.inSelectedIndex : -1
                                toggleHighlighted: ap.sndIndex === ap.outCount + 1
                                sliderActive: ap.sndIndex >= ap.outCount + 1
                                onDeviceHovered: (idx) => ap.sndIndex = ap.outCount + 2 + idx
                                onToggleHovered: ap.sndIndex = ap.outCount + 1
                            }
                        }
                    }
                }

                Component {
                    id: powerPane
                    ColumnLayout {
                        spacing: Theme.spacing.lg
                        Text {
                            text: "POWER PROFILE"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        ProfileSelector {
                            Layout.fillWidth: true
                            Layout.topMargin: -8
                            profiles: ap.profiles
                            activeIndex: Math.max(0, ap.profiles.indexOf(PowerProfiles.profile))
                            highlightedIndex: ap.pwrIndex
                            onPicked: (i) => ap.activateProfile(i)
                            onHovered: (i) => ap.pwrIndex = i
                        }

                        Text {
                            text: "BACKLIGHT"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: -8
                            spacing: Theme.spacing.md
                            BrightnessRow {
                                Layout.fillWidth: true
                                glyph: "󰃞"
                                label: "Screen"
                                value: ap.screenLevel
                                highlighted: ap.pwrIndex === 3
                                onMoved: (v) => ap.setScreen(v)
                                onHovered: ap.pwrIndex = 3
                            }
                            BrightnessRow {
                                Layout.fillWidth: true
                                glyph: "󰌌"
                                label: "Keyboard"
                                value: ap.kbLevel
                                highlighted: ap.pwrIndex === 4
                                onMoved: (v) => ap.setKb(v)
                                onHovered: ap.pwrIndex = 4
                            }
                        }

                        Text {
                            text: "SESSION"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            font.letterSpacing: 1
                            font.bold: true
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: -8
                            spacing: Theme.spacing.sm
                            Repeater {
                                model: ap.sessionActions
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    readonly property bool hl: ap.pwrIndex === 5 + index
                                    Layout.fillWidth: true
                                    implicitHeight: 60
                                    radius: 10
                                    color: hl ? Qt.rgba(modelData.accent.r, modelData.accent.g, modelData.accent.b, 0.12)
                                              : Theme.bgHover
                                    border.color: hl ? modelData.accent : Theme.borderSubtle
                                    border.width: 1
                                    scale: stMa.pressed ? 0.94 : (hl ? 1.04 : 1.0)
                                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                                    Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.glyph
                                            color: modelData.accent
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.lg
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: modelData.label
                                            color: hl ? Theme.fg : Theme.fgMuted
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.xs
                                            font.bold: hl
                                        }
                                    }
                                    MouseArea {
                                        id: stMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ap.runSession(index)
                                        onContainsMouseChanged: if (containsMouse) ap.pwrIndex = 5 + index
                                    }
                                }
                            }
                        }
                        // Push content to the top; let the rest stay empty.
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
