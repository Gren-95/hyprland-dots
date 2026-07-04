// Quick Actions overflow panel. Bar chevron opens a flyout hanging under it
// with two sections: stateful toggles up top (with explicit on/off state),
// then a 3-column grid of one-shot actions below.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: actions
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override (overflow rows). Fallback: own chevron.
    property Item flyoutAnchor: null
    property Item _openAnchor: null
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
    // STATIC list — only the immutable bits live here. `on`/`description` are
    // computed per-row in ToggleRow (reactive), so toggling a state never
    // rebuilds this array and the Repeater never recreates its rows (which is
    // what made the panel jump/flicker on every toggle).
    readonly property var allToggles: [
        { glyph: "󰂛", offGlyph: "󰂚", label: "Do Not Disturb", accent: Theme.accent.orange, action: "dnd" },
        { glyph: "󰒲", offGlyph: "󰒳", label: "Stay Awake",     accent: Theme.accent.purple, action: "idle" },
        { glyph: "󰋩", offGlyph: "󰋩", label: "Immich sync",    accent: "#f59e0b",           action: "immich" },
        { glyph: "󰝚", offGlyph: "󰝚", label: "Jellyfin sync",  accent: "#818cf8",           action: "jellyfin" },
        { glyph: "󰢹", offGlyph: "󰢹", label: "Remote access",  accent: Theme.accent.orange, action: "wayvnc" },
        { glyph: "󰎈", offGlyph: "󰎈", label: "Media keys",     accent: Theme.accent.purple, action: "mediakeys" },
        { glyph: "󰈈", offGlyph: "󰈉", label: "Activity icons", accent: Theme.accent.teal,   action: "activityicons" },
    ]

    // ============ One-shot actions ============
    // The cmd-only entries also carry an `action` key: it matches no branch
    // in activate() so they fall through to the cmd runner, and it doubles
    // as the visibility key for the Settings Bar tab.
    readonly property var allOneShots: [
        { glyph: "󰅍", label: "Clipboard",    accent: Theme.accent.slate, action: "clipboard" },
        { glyph: "󰹑", label: "Screenshot",   accent: "#60a5fa", action: "screenshot", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",       accent: Theme.accent.red, action: "record", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"] },
        { glyph: "󰈊", label: "Color picker", accent: "#e879f9", action: "colorpicker", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰋖", label: "Keybinds",     accent: Theme.accent.blue, action: "keybinds" },
        { glyph: "󰸉", label: "Wallpaper",    accent: Theme.accent.green, action: "wallpaper" },
        { glyph: "󰒓", label: "Settings",     accent: Theme.accent.slate, action: "settings" },
    ]

    // What renders in the panel: entries placed in "overflow" (the default).
    // "bar" entries are promoted to their own BarIcons (rendered by
    // shell.qml from promotedItems); "hidden" entries appear nowhere.
    // Keyboard nav and activate() index into these filtered lists, so
    // placement changes keep selection and activation consistent.
    readonly property var toggles: allToggles.filter(t => settingsStore.qaPlacementOf(t.action) === "overflow")
    readonly property var oneShots: allOneShots.filter(t => settingsStore.qaPlacementOf(t.action) === "overflow")
    readonly property var promotedItems: allToggles.concat(allOneShots)
        .filter(t => settingsStore.qaPlacementOf(t.action) === "bar")
    // Promoted TOGGLES need daemon state even while the panel is closed
    // (their bar icons show on/off), so the probe keeps polling slowly.
    readonly property bool hasPromotedToggles: allToggles.some(t => settingsStore.qaPlacementOf(t.action) === "bar")
    // Whether an action key belongs to the toggle family (drives bar-icon state color).
    function isToggleAction(key) { return allToggles.some(t => t.action === key); }

    // ============ Toggle state/description lookups ============
    // Read by the SettingRow delegates; every branch reads notifiable
    // properties, so the bindings stay reactive.
    function toggleState(action) {
        switch (action) {
        case "dnd":       return notifService.dnd;
        case "idle":      return !actions.idleOn;
        case "immich":    return actions.immichOn;
        case "jellyfin":  return actions.jellyfinOn;
        case "wayvnc":    return actions.wayvncOn;
        case "mediakeys": return settingsStore.mediaKeysVisible;
        case "activityicons": return settingsStore.activityIconsVisible;
        }
        return false;
    }
    function toggleDesc(action) {
        switch (action) {
        case "dnd":       return notifService.dnd ? "Notifications muted" : "Notifications enabled";
        case "idle":      return actions.idleOn ? "Idle sleep enabled" : "Idle sleep disabled";
        case "immich":    return actions.immichOn ? "Uploading photos hourly" : "Background sync stopped";
        case "jellyfin":  return actions.jellyfinOn ? "Syncing music every 2h" : "Background sync stopped";
        case "wayvnc":    return actions.wayvncOn ? "WayVNC server running on :5900" : "Remote access stopped";
        case "mediakeys": return settingsStore.mediaKeysVisible ? "Prev / play / next in bar" : "Hidden";
        case "activityicons": return settingsStore.activityIconsVisible ? "Camera/mic/sync icons shown" : "Hidden";
        }
        return "";
    }

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
        const entry = idx < toggles.length ? toggles[idx] : oneShots[idx - toggles.length];
        runEntry(entry);
    }
    // Run an action by its key — used by the promoted bar icons, which
    // bypass the panel entirely.
    function performAction(key) {
        const entry = allToggles.concat(allOneShots).find(t => t.action === key);
        if (entry) runEntry(entry);
    }
    function runEntry(entry) {
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
            settingsStore.mediaKeysVisible = !settingsStore.mediaKeysVisible;
        } else if (entry.action === "activityicons") {
            settingsStore.activityIconsVisible = !settingsStore.activityIconsVisible;
        } else if (entry.action === "keybinds") {
            actions.popupOpen = false;
            keybinds.toggle();
        } else if (entry.action === "wallpaper") {
            actions.popupOpen = false;
            wallpaperPicker.toggle();
        } else if (entry.action === "clipboard") {
            actions.popupOpen = false;
            clipboard.openMenu();
        } else if (entry.action === "settings") {
            actions.popupOpen = false;
            settingsPanel.toggle();
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
            "if pgrep -x hypridle >/dev/null; then pkill hypridle; else hypridle & disown; fi"]
        running: false
        // No onExited: startDetached() forks the child off — onExited never
        // fires for detached processes. State reconciliation happens via the
        // clearInFlightTimer below.
    }
    // Immich + Jellyfin sync state is managed via cron entries; the
    // sync-toggle.sh helper installs/comments/uncomments the relevant crontab
    // lines. "On" = the cron line is uncommented. The bar status icons show
    // the resulting state, so no toggle notification is sent.
    Process {
        id: immichToggleProc
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/sync-toggle.sh", "toggle", "immich"]
        running: false
    }
    Process {
        id: wayvncToggleProc
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/wayvnc-toggle.sh"]
        running: false
    }
    Process {
        id: jellyfinToggleProc
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/sync-toggle.sh", "toggle", "jellyfin"]
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
        // Fast poll while the panel is open; slow background poll while any
        // toggle is promoted to a bar icon (its on/off state must stay live).
        running: (actions.popupOpen || actions.hasPromotedToggles) && !actions.toggleInFlight
        interval: actions.popupOpen ? 1500 : 10000
        repeat: true
        triggeredOnStart: true
        onTriggered: daemonCheckProc.running = true
    }

    HoverHandler { id: qaHover }
    BarTooltip {
        bar: actions.parentBar
        target: actions
        text: "Quick actions · Super+A"
        active: qaHover.hovered && !actions.popupOpen
    }

    BarFlyout {
        id: actionsPopup
        parentBar: actions.parentBar
        anchorItem: actions._openAnchor ?? actions.flyoutAnchor ?? actions
        open: actions.popupOpen
        pinned: actions.pinned
        cardWidth: settingsStore.flyoutSize("quickactions", "w", 420)
        cardHeight: panel.implicitHeight + 28
        fillColor: Theme.bg
        borderColor: Theme.border
        onDismissed: actions.popupOpen = false

        onKeyPressed: (e) => {
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
                        delegate: SettingRow {
                            required property var modelData
                            required property int index
                            glyph: modelData.glyph
                            offGlyph: modelData.offGlyph
                            accent: modelData.accent
                            label: modelData.label
                            on: actions.toggleState(modelData.action)
                            desc: actions.toggleDesc(modelData.action)
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
        scale: tileMa.pressed ? 0.95 : (tile.highlighted ? 1.03 : 1.0)
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
