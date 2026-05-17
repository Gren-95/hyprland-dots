// Combined Sound + Power popup: tab strip at top with Sound / Power tabs.
// Owns the bar speaker icon. The battery icon in the bar opens this popup
// with the Power tab pre-selected via openAt("power").
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: ap
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
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
    // 0..2 profiles, 3 = screen slider, 4 = kb slider
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
    function cyclePwr(delta) { pwrIndex = (pwrIndex + delta + 5) % 5; }
    function activatePwr() { if (pwrIndex <= 2) activateProfile(pwrIndex); }

    // ===== Tab + popup control =====
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
            if (ap.popupOpen && ap.activeTab === "sound") {
                ap.popupOpen = false;
            } else {
                ap.setTab("sound");
                ap.popupOpen = true;
            }
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
    Process { id: pavuProc; command: ["pavucontrol"] }

    // ===== Popup =====
    PopupWindow {
        id: apPopup
        anchor.window: ap.parentBar
        anchor.rect.x: (ap.parentBar.width - implicitWidth) / 2
        anchor.rect.y: (ap.parentBar.screen.height - implicitHeight) / 2
        implicitWidth: 380
        // Fixed height sized for the larger tab content so the popup surface
        // doesn't resize when switching tabs (which causes visible jitter).
        implicitHeight: 480
        visible: ap.popupOpen
        color: "transparent"

        SproutBg {
            anchors.fill: parent
            fillColor: Theme.bgAlt
            borderColor: Theme.mutedDeep
            showTail: false
            scale: ap.popupOpen ? 1.0 : 0.94
            opacity: ap.popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Center
            Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        }
        FocusScope {
            anchors.fill: parent
            focus: ap.popupOpen
            scale: ap.popupOpen ? 1.0 : 0.94
            opacity: ap.popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Center
            Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) { ap.popupOpen = false; e.accepted = true; }
                else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    ap.navigateNext(); e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    ap.navigatePrev(); e.accepted = true;
                } else if (e.key === Qt.Key_Tab) {
                    ap.setTab(ap.activeTab === "sound" ? "power" : "sound");
                    e.accepted = true;
                } else if (ap.activeTab === "sound") {
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                        ap.cycleSnd(1); e.accepted = true;
                    } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K || e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                        ap.cycleSnd(-1); e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        ap.activateSndIndex(); e.accepted = true;
                    } else if (e.key === Qt.Key_M) {
                        if (ap.sink && ap.sink.audio) ap.sink.audio.muted = !ap.sink.audio.muted;
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                        ap.adjustVolume(0.05); e.accepted = true;
                    } else if (e.key === Qt.Key_Minus) {
                        ap.adjustVolume(-0.05); e.accepted = true;
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

                // ===== Header: pin + tab strip =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: ap.pinned
                        onToggled: ap.pinned = !ap.pinned
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.height.control
                        radius: 15
                        color: Theme.bgDeep
                        border.color: Theme.border
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 0
                            TabPill {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                glyph: "󰕾"
                                label: "Sound"
                                active: ap.activeTab === "sound"
                                accent: Theme.accent.blue
                                onPicked: ap.setTab("sound")
                            }
                            TabPill {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                glyph: "⏻"
                                label: "Power"
                                active: ap.activeTab === "power"
                                accent: Theme.accent.red
                                onPicked: ap.setTab("power")
                            }
                        }
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
                    sourceComponent: !ap.popupOpen ? null
                                   : ap.activeTab === "power" ? powerPane
                                   : soundPane
                }

                Component {
                    id: soundPane
                    ColumnLayout {
                        spacing: Theme.spacing.md
                        AudioSection {
                            Layout.fillWidth: true
                            title: "󰕾  Output"
                            node: ap.sink
                            isSink: true
                            selectedIndex: ap.outSelectedIndex !== undefined ? ap.outSelectedIndex : -1
                            toggleHighlighted: ap.sndIndex === 0
                            onLaunchMixer: { pavuProc.startDetached(); ap.popupOpen = false }
                            onDeviceHovered: (idx) => ap.sndIndex = idx + 1
                            onToggleHovered: ap.sndIndex = 0
                        }
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }
                        AudioSection {
                            Layout.fillWidth: true
                            title: "󰍬  Input"
                            node: ap.source
                            isSink: false
                            selectedIndex: ap.inSelectedIndex !== undefined ? ap.inSelectedIndex : -1
                            toggleHighlighted: ap.sndIndex === ap.outCount + 1
                            onLaunchMixer: { pavuProc.startDetached(); ap.popupOpen = false }
                            onDeviceHovered: (idx) => ap.sndIndex = ap.outCount + 2 + idx
                            onToggleHovered: ap.sndIndex = ap.outCount + 1
                        }
                        // Push content to the top; let the rest stay empty.
                        Item { Layout.fillHeight: true }
                    }
                }

                Component {
                    id: powerPane
                    ColumnLayout {
                        spacing: Theme.spacing.lg
                        ProfileSelector {
                            Layout.fillWidth: true
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
                        // Push content to the top; let the rest stay empty.
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: ap.popupOpen && !ap.pinned
        windows: [apPopup]
        onCleared: ap.popupOpen = false
    }
}
