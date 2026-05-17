import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.UPower

Item {
    id: sys
    property var parentBar
    property var triggerItem: null  // if set, popup anchors to this item; bar icon hidden
    property bool popupOpen: false
    property bool pinned: false
    signal navigateNext()
    signal navigatePrev()

    // Sections (in tab order):
    //   0..2     : Power profile (Performance/Balanced/PowerSaver)
    //   3        : Screen brightness slider
    //   4        : Keyboard backlight slider
    //   5..9     : Power actions (Lock/Suspend/Logout/Reboot/Shutdown)
    property int tabIndex: 0
    readonly property var profiles: [PowerProfile.Performance, PowerProfile.Balanced, PowerProfile.PowerSaver]

    // Brightness state
    property real screenLevel: 0.5
    property real kbLevel: 0
    property int kbMax: 2

    Layout.fillHeight: true
    implicitWidth: triggerItem ? 0 : 32

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
    function activateTab() {
        if (tabIndex <= 2) activateProfile(tabIndex);
        // tabIndex 3, 4 are the brightness sliders (handled with ←/→)
    }
    function cycleTab(delta) {
        const n = 5;
        tabIndex = (tabIndex + delta + n) % n;
    }
    function openAt(idx) {
        popupOpen = true;
        tabIndex = idx < 0 ? 4 : Math.min(idx, 4);
        refreshBrightness();
    }
    onPopupOpenChanged: if (popupOpen) {
        const i = profiles.indexOf(PowerProfiles.profile);
        tabIndex = i >= 0 ? i : 0;
        refreshBrightness();
    }

    Text {
        visible: !sys.triggerItem
        anchors.centerIn: parent
        text: "⏻"
        color: Theme.accent.red
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.lg
    }

    MouseArea {
        visible: !sys.triggerItem
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: sys.popupOpen = !sys.popupOpen
    }

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
        anchor.rect.x: (sys.parentBar.width - implicitWidth) / 2
        anchor.rect.y: (sys.parentBar.screen.height - implicitHeight) / 2
        implicitWidth: 340
        implicitHeight: sysCol.implicitHeight + 28
        visible: sys.popupOpen
        color: "transparent"

        SproutBg {
            anchors.fill: parent
            fillColor: Theme.bgAlt
            borderColor: Theme.mutedDeep
            showTail: false
        }
        Item {
            anchors.fill: parent
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
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.lg

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: sys.pinned
                        onToggled: sys.pinned = !sys.pinned
                    }
                    Item { Layout.fillWidth: true }
                }

                ProfileSelector {
                    Layout.fillWidth: true
                    Layout.topMargin: -4
                    profiles: sys.profiles
                    activeIndex: Math.max(0, sys.profiles.indexOf(PowerProfiles.profile))
                    highlightedIndex: sys.tabIndex
                    onPicked: (i) => sys.activateProfile(i)
                    onHovered: (i) => sys.tabIndex = i
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

            }
        }
    }

    HyprlandFocusGrab {
        active: sys.popupOpen && !sys.pinned
        windows: [sysPopup]
        onCleared: sys.popupOpen = false
    }
}
