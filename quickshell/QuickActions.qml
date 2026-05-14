// Windows-style overflow tray: an "expand" arrow that opens a grid of action chips.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: actions
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    signal navigateNext()
    signal navigatePrev()

    readonly property var entries: [
        { glyph: "󰂚", label: "Notifs",  accent: "#3b82f6", action: "notifs" },
        { glyph: "󰂛", label: "DnD",      accent: "#f97316", action: "dnd" },
        { glyph: "󰈊", label: "Color",   accent: "#e879f9", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰅍", label: "Clipboard", accent: "#94a3b8", action: "clipboard" },
        { glyph: "", label: "Screenshot", accent: "#60a5fa", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",   accent: "#ef4444", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"] },
        { glyph: "󰋩", label: "Immich",   accent: "#f59e0b", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/immich-sync.sh", "--now"] },
        { glyph: "󰝚", label: "Jellyfin", accent: "#818cf8", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/jellyfin-music-sync.sh"] },
        { glyph: "󰖂", label: "Trayscale", accent: "#22c55e", cmd: ["flatpak", "run", "dev.deedles.Trayscale"] },
        { glyph: "󰒲", label: "Idle",     accent: "#a8a29e", cmd: ["sh", "-c", "if pgrep -x hypridle >/dev/null; then pkill hypridle && notify-send -u low -i caffeine-on 'Stay Awake' 'Idle disabled'; else hypridle & disown && notify-send -u low -i caffeine-off 'Sleep Mode' 'Idle enabled'; fi"] },
    ]
    property int selectedIndex: 0

    Layout.fillHeight: true
    implicitWidth: 30

    Text {
        anchors.centerIn: parent
        text: "󰍝"  // nf-md-chevron-up; rotates 180° to chevron-down when open
        color: actions.popupOpen ? "#3b82f6" : "#d6d3d1"
        font.family: "FiraCode Nerd Font"
        font.pixelSize: 16
        rotation: actions.popupOpen ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: actions.popupOpen = !actions.popupOpen
    }

    function activate(i) {
        if (i < 0 || i >= entries.length) return;
        const e = entries[i];
        actions.popupOpen = false;
        if (e.action === "notifs") {
            notifs.openCenter();
        } else if (e.action === "dnd") {
            notifs.dnd = !notifs.dnd;
        } else if (e.action === "clipboard") {
            clipboard.openMenu();
        } else if (e.cmd) {
            runProc.command = e.cmd;
            runProc.startDetached();
        }
    }
    function openAt(idx) {
        popupOpen = true;
        selectedIndex = idx < 0 ? entries.length - 1 : Math.min(idx, entries.length - 1);
    }
    function cycleTab(delta) {
        const n = entries.length;
        if (n <= 0) return;
        selectedIndex = (selectedIndex + delta + n) % n;
    }
    onPopupOpenChanged: if (popupOpen) selectedIndex = 0

    Process { id: runProc; command: [] }

    PopupWindow {
        id: actionsPopup
        anchor.window: actions.parentBar
        anchor.item: actions
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        implicitWidth: 320
        implicitHeight: 220
        visible: actions.popupOpen
        color: "transparent"

        SproutBg { anchors.fill: parent; fillColor: "#292524"; borderColor: "#78716c"; tailX: width / 2 }
        Item {
            anchors.fill: parent
            focus: actions.popupOpen
            // Open/close animation
            scale: actions.popupOpen ? 1.0 : 0.92
            opacity: actions.popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                const n = actions.entries.length;
                if (e.key === Qt.Key_Escape) { actions.popupOpen = false; e.accepted = true; }
                else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    actions.navigateNext(); e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    actions.navigatePrev(); e.accepted = true;
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Tab) {
                    actions.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    actions.cycleTab(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    actions.cycleTab(4); e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    actions.cycleTab(-4); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    actions.activate(actions.selectedIndex); e.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    PinButton {
                        pinned: actions.pinned
                        onToggled: actions.pinned = !actions.pinned
                    }
                    Text {
                        text: "Quick actions"
                        color: "#f5f5f4"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: 6
                    rowSpacing: 6
                    Repeater {
                        model: actions.entries
                        delegate: ActionChip {
                            required property var modelData
                            required property int index
                            entry: modelData
                            highlighted: actions.selectedIndex === index
                            Layout.fillWidth: true
                            onPicked: actions.activate(index)
                            onHovered: actions.selectedIndex = index
                            // Staggered fade-in
                            opacity: actions.popupOpen ? 1.0 : 0.0
                            scale: actions.popupOpen ? 1.0 : 0.85
                            Behavior on opacity {
                                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                            }
                            Behavior on scale {
                                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: actions.popupOpen && !actions.pinned
        windows: [actionsPopup]
        onCleared: actions.popupOpen = false
    }

    component ActionChip: Rectangle {
        id: chip
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 64
        radius: 8
        color: chip.highlighted ? "#3b3531" : (chipMa.containsMouse ? "#262220" : "#1f1c1a")
        border.color: chip.highlighted ? (chip.entry ? chip.entry.accent : "#fafaf9") : "#3a3633"
        border.width: chip.highlighted ? 2 : 1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 3
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: chip.entry ? chip.entry.glyph : ""
                color: chip.entry ? chip.entry.accent : "#f5f5f4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 18
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: chip.entry ? chip.entry.label : ""
                color: "#e7e5e4"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 9
                font.bold: chip.highlighted
            }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
            onContainsMouseChanged: if (containsMouse) chip.hovered()
        }
    }
}
