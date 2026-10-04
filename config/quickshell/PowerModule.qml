// Power popup: battery card, power profile, backlight and the session
// actions. It has no bar icon of its own; the battery icon in shell.qml opens
// it. Sound lives in SoundModule.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Services.UPower

Item {
    id: ap
    implicitWidth: 0
    implicitHeight: 0
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override set by toggleOpen(from).
    property Item flyoutAnchor: null
    property Item _openAnchor: null
    signal navigateNext()
    signal navigatePrev()

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
    // brightnessctl invocation for the screen (dev "") or a named device.
    function brightnessCmd(dev, args) {
        return ["brightnessctl"].concat(dev ? ["--device=" + dev] : [], args);
    }
    function setScreen(v) {
        const pct = Math.round(Math.max(0, Math.min(1, v)) * 100);
        screenLevel = pct / 100;
        setBrightnessProc.command = brightnessCmd("", ["set", pct + "%"]);
        setBrightnessProc.startDetached();
    }
    function setKb(v) {
        if (!Backlight.kbDev) return;
        const raw = Math.round(Math.max(0, Math.min(1, v)) * kbMax);
        kbLevel = kbMax > 0 ? raw / kbMax : 0;
        setBrightnessProc.command = brightnessCmd(Backlight.kbDev, ["set", String(raw)]);
        setBrightnessProc.startDetached();
    }
    function refreshBrightness() {
        getScreenProc.running = false; getScreenProc.running = true;
        if (Backlight.kbDev) { getKbProc.running = false; getKbProc.running = true; }
    }
    function runSession(i) {
        const a = sessionActions[i];
        if (!a) return;
        sessionProc.command = a.cmd;
        sessionProc.startDetached();
        popupOpen = false;
    }
    // Up/Down step through the stops, skipping the keyboard slider when this
    // machine has no keyboard backlight.
    function cyclePwr(delta) {
        let next = (pwrIndex + delta + 8) % 8;
        if (next === 4 && Backlight.kbDev === "") next = (next + delta + 8) % 8;
        pwrIndex = next;
    }
    function activatePwr() {
        if (pwrIndex <= 2) activateProfile(pwrIndex);
        else if (pwrIndex >= 5) runSession(pwrIndex - 5);
    }



    // Popup height follows the content (up to what the screen allows), so
    // there is never empty space under the last control.
    readonly property real fitHeight: Math.min(
        parentBar && parentBar.screen ? parentBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)

    // ===== Popup control =====
    function toggleOpen(from) {
        _openAnchor = from ?? null;
        popupOpen = !popupOpen;
    }
    function openAt() {
        _openAnchor = null;   // ring hops open at the module's own anchor
        popupOpen = true;
    }
    onPopupOpenChanged: if (popupOpen) {
        const i = profiles.indexOf(PowerProfiles.profile);
        pwrIndex = i >= 0 ? i : 0;
        refreshBrightness();
    }

    // ===== Power-related processes =====
    // startDetached() snapshots the command, so screen and keyboard writes
    // can share one Process object.
    Process { id: setBrightnessProc; command: [] }
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
        command: ["sh", "-c", "d=--device=" + Backlight.kbDev + "; echo $(brightnessctl $d get) $(brightnessctl $d max)"]
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
        running: ap.popupOpen
        repeat: true
        onTriggered: ap.refreshBrightness()
    }


    // ===== Popup =====
    BarFlyout {
        id: pwrPopup
        parentBar: ap.parentBar
        anchorItem: ap._openAnchor ?? ap.flyoutAnchor ?? ap
        open: ap.popupOpen
        cardWidth: settingsStore.flyoutSize("power", "w", 460)
        cardHeight: settingsStore.flyoutSize("power", "h", ap.fitHeight)
        pinned: ap.pinned
        onDismissed: ap.popupOpen = false
        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                ap.navigateNext(); e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                ap.navigatePrev(); e.accepted = true;
            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
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

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: ap.pinned
                    onToggled: ap.pinned = !ap.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "Power"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                // Balances the pin button so the title stays centered.
                Item { implicitWidth: 22; implicitHeight: 22 }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: col.implicitHeight
                clip: true
                contentWidth: width
                contentHeight: col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {
                    policy: flick.contentHeight > flick.height + 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: col
                    width: flick.width - Theme.spacing.md
                    spacing: Theme.spacing.lg

                    BatteryCard { Layout.fillWidth: true }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: profileCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: profileCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.lg
                            Text {
                                text: "POWER PROFILE"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                                font.letterSpacing: 1
                                font.bold: true
                            }
                            ProfileSelector {
                                Layout.fillWidth: true
                                profiles: ap.profiles
                                activeIndex: Math.max(0, ap.profiles.indexOf(PowerProfiles.profile))
                                highlightedIndex: ap.pwrIndex <= 2 ? ap.pwrIndex : -1
                                onPicked: (i) => ap.activateProfile(i)
                                onHovered: (i) => ap.pwrIndex = i
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: lightCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: lightCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.lg
                            Text {
                                text: "BACKLIGHT"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                                font.letterSpacing: 1
                                font.bold: true
                            }
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
                                visible: Backlight.kbDev !== ""
                                glyph: "󰌌"
                                label: "Keyboard"
                                value: ap.kbLevel
                                highlighted: ap.pwrIndex === 4
                                onMoved: (v) => ap.setKb(v)
                                onHovered: ap.pwrIndex = 4
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.md
                        Repeater {
                            model: ap.sessionActions
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool hl: ap.pwrIndex === 5 + index
                                readonly property bool danger: modelData.label === "Shutdown"
                                Layout.fillWidth: true
                                implicitHeight: 78
                                radius: 10 * Theme.radiusScale
                                color: hl || stMa.containsMouse ? Theme.alpha(modelData.accent, 0.14) : Theme.bg
                                border.color: hl ? modelData.accent
                                    : danger ? Theme.alpha(modelData.accent, 0.5) : Theme.border
                                border.width: hl ? 2 : 1
                                scale: stMa.pressed ? 0.94 : (hl ? 1.03 : 1.0)
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
                                        font.pixelSize: Theme.fontSize.xxl
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        color: hl || danger ? modelData.accent : Theme.fgMuted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.sm
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
                }
            }

            Text {
                Layout.fillWidth: true
                text: "↑↓ move · ←→ adjust · ↵ select"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
