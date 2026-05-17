// Quick Actions overflow panel. Bar chevron opens a centered modal with
// two sections: stateful toggles up top (with explicit on/off state),
// then a 3-column grid of one-shot actions below.
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
    property bool idleOn: true   // best-guess; refreshed from `pgrep hypridle`
    signal navigateNext()
    signal navigatePrev()

    // ============ Toggle definitions (on/off state visible) ============
    // `state` lambdas return a bool; `toggle()` flips it.
    readonly property var toggles: [
        {
            glyph:    "󰂛", offGlyph: "󰂚",
            label:    "Do Not Disturb",
            accent:   Theme.accent.orange,
            on:       notifs.dnd,
            description: notifs.dnd ? "Notifications muted" : "Notifications enabled",
            action:   "dnd",
        },
        {
            glyph:    "󰒲", offGlyph: "󰒳",
            label:    "Stay Awake",
            accent:   Theme.accent.purple,
            on:       !actions.idleOn,
            description: actions.idleOn ? "Idle sleep enabled" : "Idle sleep disabled",
            action:   "idle",
        },
    ]

    // ============ One-shot actions ============
    readonly property var oneShots: [
        { glyph: "󰂚", label: "Notifications", accent: Theme.accent.blue, action: "notifs" },
        { glyph: "󰅍", label: "Clipboard",     accent: Theme.accent.slate, action: "clipboard" },
        { glyph: "", label: "Screenshot",    accent: "#60a5fa", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",        accent: Theme.accent.red, cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"] },
        { glyph: "󰈊", label: "Color picker",  accent: "#e879f9", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰋩", label: "Immich sync",   accent: "#f59e0b", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/immich-sync.sh", "--now"] },
        { glyph: "󰝚", label: "Jellyfin sync", accent: "#818cf8", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/jellyfin-music-sync.sh"] },
    ]

    // Single flat index across both sections for keyboard nav:
    // 0..toggles.length-1  → toggles
    // toggles.length..end  → one-shots
    property int selectedIndex: 0
    readonly property int totalItems: toggles.length + oneShots.length

    Layout.fillHeight: true
    implicitWidth: 32

    Text {
        anchors.centerIn: parent
        text: "󰍝"
        color: actions.popupOpen ? Theme.accent.blue : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.xl
        rotation: actions.popupOpen ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: actions.popupOpen = !actions.popupOpen
    }

    function activate(idx) {
        if (idx < 0 || idx >= totalItems) return;
        let entry;
        let isToggle = false;
        if (idx < toggles.length) {
            entry = toggles[idx];
            isToggle = true;
        } else {
            entry = oneShots[idx - toggles.length];
        }
        if (entry.action === "dnd") {
            notifs.dnd = !notifs.dnd;
        } else if (entry.action === "idle") {
            idleToggleProc.startDetached();
        } else if (entry.action === "notifs") {
            actions.popupOpen = false;
            notifs.openCenter();
        } else if (entry.action === "clipboard") {
            actions.popupOpen = false;
            clipboard.openMenu();
        } else if (entry.cmd) {
            actions.popupOpen = false;
            runProc.command = entry.cmd;
            runProc.startDetached();
        }
        // Toggle actions keep the panel open so the user can see the state flip.
    }
    function openAt(idx) {
        popupOpen = true;
        selectedIndex = idx < 0 ? totalItems - 1 : Math.min(idx, totalItems - 1);
    }
    function cycle(delta) {
        if (totalItems <= 0) return;
        selectedIndex = (selectedIndex + delta + totalItems) % totalItems;
    }
    onPopupOpenChanged: if (popupOpen) {
        selectedIndex = 0;
        idleCheckProc.running = true;
    }

    Process { id: runProc; command: [] }
    Process {
        id: idleToggleProc
        command: ["sh", "-c",
            "source ~/.config/scripts/lib/notify.sh && " +
            "if pgrep -x hypridle >/dev/null; then " +
            "  pkill hypridle && notify low hypridle caffeine-on 'Stay Awake' 'Idle disabled'; " +
            "else " +
            "  hypridle & disown && notify low hypridle caffeine-off 'Sleep Mode' 'Idle enabled'; " +
            "fi"]
        running: false
        onExited: idleCheckProc.running = true
    }
    Process {
        id: idleCheckProc
        command: ["sh", "-c", "pgrep -x hypridle >/dev/null && echo 1 || echo 0"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: actions.idleOn = text.trim() === "1"
        }
    }
    Timer {
        running: actions.popupOpen
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: idleCheckProc.running = true
    }

    PopupWindow {
        id: actionsPopup
        anchor.window: actions.parentBar
        anchor.rect.x: (actions.parentBar.width - implicitWidth) / 2
        anchor.rect.y: (actions.parentBar.screen.height - implicitHeight) / 2
        implicitWidth: 420
        implicitHeight: panel.implicitHeight + 28
        visible: actions.popupOpen
        color: "transparent"

        SproutBg { anchors.fill: parent; fillColor: Theme.bg; borderColor: Theme.border; showTail: false }

        FocusScope {
            anchors.fill: parent
            focus: actions.popupOpen
            scale: actions.popupOpen ? 1.0 : 0.95
            opacity: actions.popupOpen ? 1.0 : 0.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) { actions.popupOpen = false; e.accepted = true; }
                else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    actions.navigateNext(); e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    actions.navigatePrev(); e.accepted = true;
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L || e.key === Qt.Key_Tab) {
                    actions.cycle(e.modifiers & Qt.ShiftModifier ? -1 : 1); e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    actions.cycle(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    actions.cycle(3); e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    actions.cycle(-3); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    actions.activate(actions.selectedIndex); e.accepted = true;
                }
            }

            ColumnLayout {
                id: panel
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: Theme.spacing.lg
                }
                spacing: Theme.spacing.lg

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: actions.pinned
                        onToggled: actions.pinned = !actions.pinned
                    }
                    Text {
                        text: "Quick actions"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                }

                // Toggle row: full-width pills with explicit on/off state
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm
                    Repeater {
                        model: actions.toggles
                        delegate: ToggleRow {
                            required property var modelData
                            required property int index
                            entry: modelData
                            highlighted: actions.selectedIndex === index
                            Layout.fillWidth: true
                            onPicked: actions.activate(index)
                            onHovered: actions.selectedIndex = index
                        }
                    }
                }

                // Section divider
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Actions grid: 3-column tiles, larger than before
                GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Theme.spacing.sm
                    rowSpacing: Theme.spacing.sm
                    Repeater {
                        model: actions.oneShots
                        delegate: ActionTile {
                            required property var modelData
                            required property int index
                            entry: modelData
                            highlighted: actions.selectedIndex === (index + actions.toggles.length)
                            Layout.fillWidth: true
                            onPicked: actions.activate(index + actions.toggles.length)
                            onHovered: actions.selectedIndex = index + actions.toggles.length
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

    // Full-width toggle pill — leading icon (tinted square), label + description,
    // trailing on/off switch indicator.
    component ToggleRow: Rectangle {
        id: row
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        implicitHeight: 54
        radius: 10
        readonly property color accent: row.entry ? row.entry.accent : Theme.muted
        readonly property bool on: row.entry ? !!row.entry.on : false
        color: row.on
            ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
            : (rowMa.containsMouse ? Theme.bgHover : "#1a1716")
        border.color: row.on ? accent : (row.highlighted ? Theme.mutedDeep : Theme.borderSubtle)
        border.width: row.on ? 2 : 1
        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.lg

            // Icon square
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                color: Qt.rgba(row.accent.r, row.accent.g, row.accent.b, row.on ? 0.20 : 0.08)
                Text {
                    anchors.centerIn: parent
                    text: row.on
                        ? (row.entry ? row.entry.glyph    : "")
                        : (row.entry ? row.entry.offGlyph : "")
                    color: row.on ? row.accent : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                }
            }

            // Title + description
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Text {
                    text: row.entry ? row.entry.label : ""
                    color: row.on ? Theme.fg : Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: row.on
                }
                Text {
                    Layout.fillWidth: true
                    text: row.entry ? row.entry.description : ""
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
            }

            // Track-style switch indicator
            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                radius: 10
                color: row.on ? row.accent : Theme.borderSubtle
                border.color: row.on ? row.accent : Theme.border
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                Rectangle {
                    width: 14
                    height: 14
                    radius: 7
                    color: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                    x: row.on ? parent.width - width - 3 : 3
                    Behavior on x { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                }
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.picked()
            onContainsMouseChanged: if (containsMouse) row.hovered()
        }
    }

    // Grid action tile — colored icon at top, label below.
    component ActionTile: Rectangle {
        id: tile
        property var entry
        property bool highlighted: false
        signal picked()
        signal hovered()
        readonly property color accent: tile.entry ? tile.entry.accent : Theme.fg
        implicitHeight: Theme.height.tile
        radius: 10
        color: tile.highlighted
            ? Qt.rgba(accent.r, accent.g, accent.b, 0.12)
            : (tileMa.containsMouse ? Theme.bgHover : "#1a1716")
        border.color: tile.highlighted ? accent : Theme.borderSubtle
        border.width: tile.highlighted ? 2 : 1
        scale: tile.highlighted ? 1.03 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Theme.spacing.xs
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 8
                color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: tile.entry ? tile.entry.glyph : ""
                    color: tile.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: tile.width - 12
                text: tile.entry ? tile.entry.label : ""
                color: tile.highlighted ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: tile.highlighted
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.picked()
            onContainsMouseChanged: if (containsMouse) tile.hovered()
        }
    }
}
