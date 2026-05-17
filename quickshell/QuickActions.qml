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
    property bool idleOn: true       // best-guess; refreshed from `pgrep hypridle`
    property bool immichOn: false    // immich cron entry enabled
    property bool jellyfinOn: false  // jellyfin cron entry enabled
    property bool wayvncOn: false    // wayvnc daemon running
    // When a toggle is mid-flight (script not yet committed), skip the
    // periodic daemonCheck so its stale read doesn't briefly revert the
    // optimistic UI flip.
    property bool toggleInFlight: false
    signal navigateNext()
    signal navigatePrev()

    // ============ Toggle definitions (on/off state visible) ============
    // `state` lambdas return a bool; `toggle()` flips it.
    readonly property var toggles: [
        {
            glyph:    "󰂛", offGlyph: "󰂚",
            label:    "Do Not Disturb",
            accent:   Theme.accent.orange,
            on:       notifService.dnd,
            description: notifService.dnd ? "Notifications muted" : "Notifications enabled",
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
        {
            glyph:    "󰋩", offGlyph: "󰋩",
            label:    "Immich sync",
            accent:   "#f59e0b",
            on:       actions.immichOn,
            description: actions.immichOn ? "Uploading photos hourly" : "Background sync stopped",
            action:   "immich",
        },
        {
            glyph:    "󰝚", offGlyph: "󰝚",
            label:    "Jellyfin sync",
            accent:   "#818cf8",
            on:       actions.jellyfinOn,
            description: actions.jellyfinOn ? "Syncing music every 2h" : "Background sync stopped",
            action:   "jellyfin",
        },
        {
            glyph:    "󰢹", offGlyph: "󰢹",
            label:    "Remote access",
            accent:   Theme.accent.orange,
            on:       actions.wayvncOn,
            description: actions.wayvncOn ? "WayVNC server running on :5900" : "Remote access stopped",
            action:   "wayvnc",
        },
        {
            glyph:    "󰎈", offGlyph: "󰎈",
            label:    "Media keys",
            accent:   Theme.accent.purple,
            on:       Settings.mediaKeysVisible,
            description: Settings.mediaKeysVisible ? "Prev / play / next in bar" : "Hidden",
            action:   "mediakeys",
        },
    ]

    // ============ One-shot actions ============
    readonly property var oneShots: [
        { glyph: "󰅍", label: "Clipboard",    accent: Theme.accent.slate, action: "clipboard" },
        { glyph: "󰹑", label: "Screenshot",   accent: "#60a5fa", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",       accent: Theme.accent.red, cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"] },
        { glyph: "󰈊", label: "Color picker", accent: "#e879f9", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰋖", label: "Keybinds",     accent: Theme.accent.blue, action: "keybinds" },
        { glyph: "󰸉", label: "Wallpaper",    accent: Theme.accent.green, action: "wallpaper" },
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
            notifService.dnd = !notifService.dnd;
        } else if (entry.action === "idle") {
            // Optimistic: flip UI immediately; daemonCheck reconciles later.
            actions.idleOn = !actions.idleOn;
            actions.toggleInFlight = true;
            clearInFlightTimer.restart();
            idleToggleProc.startDetached();
        } else if (entry.action === "immich") {
            actions.immichOn = !actions.immichOn;
            actions.toggleInFlight = true;
            clearInFlightTimer.restart();
            immichToggleProc.startDetached();
        } else if (entry.action === "jellyfin") {
            actions.jellyfinOn = !actions.jellyfinOn;
            actions.toggleInFlight = true;
            clearInFlightTimer.restart();
            jellyfinToggleProc.startDetached();
        } else if (entry.action === "wayvnc") {
            actions.wayvncOn = !actions.wayvncOn;
            actions.toggleInFlight = true;
            clearInFlightTimer.restart();
            wayvncToggleProc.startDetached();
        } else if (entry.action === "mediakeys") {
            Settings.mediaKeysVisible = !Settings.mediaKeysVisible;
        } else if (entry.action === "keybinds") {
            actions.popupOpen = false;
            keybinds.toggle();
        } else if (entry.action === "wallpaper") {
            actions.popupOpen = false;
            wallpaperPicker.toggle();
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
        daemonCheckProc.running = true;
    }

    Process { id: runProc; command: [] }
    Process {
        id: idleToggleProc
        command: ["sh", "-c",
            "source ~/.config/scripts/lib/notify.sh && " +
            "if pgrep -x hypridle >/dev/null; then " +
            "  pkill hypridle && notify low hypridle system-suspend-inhibited 'Stay Awake' 'Idle disabled'; " +
            "else " +
            "  hypridle & disown && notify low hypridle system-suspend-uninhibited 'Sleep Mode' 'Idle enabled'; " +
            "fi"]
        running: false
        // No onExited: startDetached() forks the child off — onExited never
        // fires for detached processes. State reconciliation happens via the
        // clearInFlightTimer below.
    }
    // Immich + Jellyfin sync state is managed via cron entries; the
    // sync-toggle.sh helper installs/comments/uncomments the relevant
    // crontab lines. "On" = the cron line is uncommented. `toggle` emits
    // the resulting state ("0" or "1") so the notification can be sent
    // in the same shell invocation without a second crontab read.
    Process {
        id: immichToggleProc
        command: ["sh", "-c",
            "state=$(bash ~/.config/scripts/sync-toggle.sh toggle immich); " +
            "source ~/.config/scripts/lib/notify.sh; " +
            "[[ \"$state\" == \"1\" ]] " +
            "  && notify low immich-sync camera-photo 'Immich sync' 'Hourly schedule enabled' " +
            "  || notify low immich-sync camera-photo 'Immich sync' 'Schedule disabled'"]
        running: false
    }
    Process {
        id: wayvncToggleProc
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/wayvnc-toggle.sh"]
        running: false
    }
    Process {
        id: jellyfinToggleProc
        command: ["sh", "-c",
            "state=$(bash ~/.config/scripts/sync-toggle.sh toggle jellyfin); " +
            "source ~/.config/scripts/lib/notify.sh; " +
            "[[ \"$state\" == \"1\" ]] " +
            "  && notify low jellyfin-sync audio-x-generic 'Jellyfin sync' 'Schedule enabled (every 2h)' " +
            "  || notify low jellyfin-sync audio-x-generic 'Jellyfin sync' 'Schedule disabled'"]
        running: false
    }
    // Clears the in-flight flag a beat after the toggle starts so periodic
    // daemonCheck can resume and reconcile state. 800ms is enough for the
    // sync-toggle.sh write + a daemonCheck round-trip.
    Timer {
        id: clearInFlightTimer
        interval: 800
        repeat: false
        onTriggered: { actions.toggleInFlight = false; daemonCheckProc.running = true }
    }
    Process {
        // Combined probe: hypridle process + immich/jellyfin cron schedule state.
        // Output format: "idle=0|1 immich=0|1 jellyfin=0|1"
        id: daemonCheckProc
        command: ["sh", "-c",
            "printf 'idle=%s ' $(pgrep -x hypridle >/dev/null && echo 1 || echo 0); " +
            "printf 'wayvnc=%s ' $(pgrep -x wayvnc >/dev/null && echo 1 || echo 0); " +
            "bash ~/.config/scripts/sync-toggle.sh status all"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const kv of text.trim().split(/\s+/)) {
                    const [k, v] = kv.split("=");
                    m[k] = v === "1";
                }
                if (m.idle !== undefined)     actions.idleOn = m.idle;
                if (m.wayvnc !== undefined)   actions.wayvncOn = m.wayvnc;
                if (m.immich !== undefined)   actions.immichOn = m.immich;
                if (m.jellyfin !== undefined) actions.jellyfinOn = m.jellyfin;
            }
        }
    }
    Timer {
        running: actions.popupOpen && !actions.toggleInFlight
        interval: 1500
        repeat: true
        triggeredOnStart: true
        onTriggered: daemonCheckProc.running = true
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
                    // Toggles are a single column → step 1. Action grid is
                    // 3 columns → step 3. Branch on which section we're in.
                    actions.cycle(actions.selectedIndex < actions.toggles.length ? 1 : 3);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    actions.cycle(actions.selectedIndex < actions.toggles.length ? -1 : -3);
                    e.accepted = true;
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

                Text {
                    text: "TOGGLES"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.letterSpacing: 1
                    font.bold: true
                }

                // Toggle row: full-width pills with explicit on/off state
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
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

                Text {
                    text: "ACTIONS"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.letterSpacing: 1
                    font.bold: true
                }

                // Actions grid: 3-column tiles, larger than before
                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
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
