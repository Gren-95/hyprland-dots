// Quick Actions overflow panel. Bar chevron opens a flyout hanging under it
// with two sections: stateful toggles up top (with explicit on/off state),
// then a 3-column grid of one-shot actions below.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

Item {
    id: actions
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override (overflow rows). Fallback: own chevron.
    property Item flyoutAnchor: null
    property Item _openAnchor: null
    readonly property var micSrc: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
    signal navigateNext()
    signal navigatePrev()

    // ============ Toggle definitions (on/off state visible) ============
    // `state` lambdas return a bool; `toggle()` flips it.
    // STATIC list — only the immutable bits live here. `on`/`description` are
    // computed per-row in ToggleRow (reactive), so toggling a state never
    // rebuilds this array and the Repeater never recreates its rows (which is
    // what made the panel jump/flicker on every toggle).
    readonly property var allToggles: [
        { glyph: "󰍬", offGlyph: "󰍭", label: "Microphone",     accent: Theme.accent.orange, action: "mic" },
        { glyph: "󰈈", offGlyph: "󰈉", label: "Activity icons", accent: Theme.accent.teal,   action: "activityicons" },
    ]

    // ============ One-shot actions ============
    // The cmd-only entries also carry an `action` key: it matches no branch
    // in activate() so they fall through to the cmd runner, and it doubles
    // as the visibility key for the Settings Bar tab.
    readonly property var allOneShots: [
        { glyph: "󰅍", label: "Clipboard",    accent: Theme.accent.slate, action: "clipboard" },
        { glyph: "󰹑", label: "Screenshot",   accent: Theme.accent.blueBright, action: "screenshot", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",       accent: Theme.accent.red, action: "record", cmd: ["bash", Quickshell.env("HOME") + "/.config/scripts/screenrecord.sh"] },
        { glyph: "󰈊", label: "Color picker", accent: "#e879f9", action: "colorpicker", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰋖", label: "Keybinds",     accent: Theme.accent.blue, action: "keybinds" },
        { glyph: "󰸉", label: "Wallpaper",    accent: Theme.accent.green, action: "wallpaper" },
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
    // Whether an action key belongs to the toggle family (drives bar-icon state color).
    function isToggleAction(key) { return allToggles.some(t => t.action === key); }

    // ============ Toggle state/description lookups ============
    // Read by the tray-tile delegates; every branch reads notifiable
    // properties, so the bindings stay reactive.
    function toggleState(action) {
        switch (action) {
        case "mic":       return actions.micSrc && actions.micSrc.audio ? !actions.micSrc.audio.muted : false;
        case "activityicons": return settingsStore.activityIconsVisible;
        }
        return false;
    }
    function toggleDesc(action) {
        switch (action) {
        case "mic":       return (actions.micSrc && actions.micSrc.audio && !actions.micSrc.audio.muted) ? "Microphone live" : "Microphone muted";
        case "activityicons": return settingsStore.activityIconsVisible ? "Camera/mic/sync icons shown" : "Hidden";
        }
        return "";
    }

    // Single flat index across the tray grid for keyboard nav:
    // 0..toggles.length-1  → toggles
    // toggles.length..end  → one-shots
    property int selectedIndex: 0

    // Bar modules wired from shell.qml ({id, glyph(), color(), label,
    // when?, open(anchor)}). Modules placed in "overflow" render as tiles
    // in this grid — Quick Actions IS the tray; the chevron only keeps
    // hidden tray apps. glyph()/color() thunks are called inside this
    // binding, so state (battery %, wifi strength) stays live.
    property var moduleEntries: []
    // Hidden tray apps render as a row above the grid — Quick Actions is
    // the single overflow surface. Menus are separate windows: while one
    // is open the flyout pins itself so the focus grab can't dismiss it.
    property int menusOpen: 0
    readonly property var overflowTray: {
        const list = (SystemTray.items && SystemTray.items.values) || [];
        return list.filter(t => settingsStore.trayPlacementOf(t.id || t.title) === "overflow");
    }
    readonly property var tuckedModules: moduleEntries
        .filter(e => settingsStore.placement(e.id) === "overflow" && (!e.when || e.when()))
        .map(e => ({ glyph: e.glyph(), label: e.label, accent: e.color(),
                     action: "__module_" + e.id, _open: e.open }))

    readonly property int totalItems: toggles.length + oneShots.length + tuckedModules.length
    readonly property int gridColumns: 4
    readonly property var gridItems: toggles.concat(oneShots).concat(tuckedModules)

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
        const entry = gridItems[idx];
        // Flyout-opening actions inherit the panel's own anchor, so the new
        // flyout appears exactly where the panel was hanging.
        runEntry(entry, actions._openAnchor ?? actions.flyoutAnchor ?? actions);
    }
    // Run an action by its key — used by the promoted bar icons, which
    // bypass the panel entirely and pass themselves as the anchor.
    function performAction(key, from) {
        const entry = allToggles.concat(allOneShots).find(t => t.action === key);
        if (entry) runEntry(entry, from ?? null);
    }
    function runEntry(entry, from) {
        // Tucked bar-module tile: close the panel and open the module's
        // flyout where the panel was.
        if (entry._open) {
            actions.popupOpen = false;
            entry._open(from);
            return;
        }
        if (entry.action === "mic") {
            if (actions.micSrc && actions.micSrc.audio)
                actions.micSrc.audio.muted = !actions.micSrc.audio.muted;
        } else if (entry.action === "activityicons") {
            settingsStore.activityIconsVisible = !settingsStore.activityIconsVisible;
        } else if (entry.action === "keybinds") {
            actions.popupOpen = false;
            keybinds.toggle(from);
        } else if (entry.action === "wallpaper") {
            actions.popupOpen = false;
            wallpaperPicker.toggle(from);
        } else if (entry.action === "clipboard") {
            actions.popupOpen = false;
            clipboard.openMenu(from);
        } else if (entry.cmd) {
            actions.popupOpen = false;
            runProc.command = entry.cmd;
            runProc.startDetached();
        }
        // Toggle actions keep the panel open so the user can see the state flip.
    }
    function openAt(idx) {
        _openAnchor = null;
        popupOpen = true;
        selectedIndex = idx < 0 ? totalItems - 1 : Math.min(idx, totalItems - 1);
    }
    function cycle(delta) {
        if (totalItems <= 0) return;
        selectedIndex = (selectedIndex + delta + totalItems) % totalItems;
    }
    onPopupOpenChanged: if (popupOpen) selectedIndex = 0

    Process { id: runProc; command: [] }

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
        pinned: actions.pinned || actions.menusOpen > 0
        cardWidth: settingsStore.flyoutSize("quickactions", "w", 420)
        cardHeight: panel.implicitHeight + 28
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
                actions.cycle(actions.gridColumns); e.accepted = true;
            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                actions.cycle(-actions.gridColumns); e.accepted = true;
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
                        pinned: actions.pinned || actions.menusOpen > 0
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

                // Hidden tray apps (placement "Tuck" in the Bar tab).
                RowLayout {
                    visible: actions.overflowTray.length > 0
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm
                    Repeater {
                        model: actions.overflowTray
                        delegate: TrayItem {
                            required property var modelData
                            item: modelData
                            anchorWindow: actions.parentBar
                            implicitHeight: 28
                            onMenuOpenChanged: actions.menusOpen += menuOpen ? 1 : -1
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // ===== Tray grid: every item as a compact state tile =====
                GridLayout {
                    Layout.fillWidth: true
                    columns: actions.gridColumns
                    columnSpacing: Theme.spacing.sm
                    rowSpacing: Theme.spacing.sm
                    Repeater {
                        model: actions.gridItems
                        delegate: TrayTile {
                            required property var modelData
                            required property int index
                            entry: modelData
                            isToggle: actions.isToggleAction(modelData.action)
                            on: isToggle && actions.toggleState(modelData.action)
                            highlighted: actions.selectedIndex === index
                            Layout.fillWidth: true
                            onPicked: actions.activate(index)
                            onHovered: actions.selectedIndex = index
                        }
                    }
                }

                // Status line for the highlighted item — replaces the old
                // per-row descriptions in a single quiet footer.
                Text {
                    Layout.fillWidth: true
                    readonly property var cur: actions.gridItems[actions.selectedIndex]
                    text: cur ? (actions.isToggleAction(cur.action) ? actions.toggleDesc(cur.action) : cur.label) : ""
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
            }
    }

    // Compact tray tile — glyph on top, label below. Toggles fill with
    // their accent while on; one-shots stay neutral until hover/highlight.
    component TrayTile: Rectangle {
        id: tile
        property var entry
        property bool isToggle: false
        property bool on: false
        property bool highlighted: false
        signal picked()
        signal hovered()
        readonly property color accent: (tile.entry && tile.entry.accent !== undefined)
            ? tile.entry.accent : Theme.fg
        implicitHeight: 64
        radius: 10 * Theme.radiusScale
        color: tile.on
            ? Qt.rgba(accent.r, accent.g, accent.b, 0.16)
            : tile.highlighted
                ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
                : (tileMa.containsMouse ? Theme.bgHover : Theme.bgInset)
        border.color: tile.on ? accent
                    : tile.highlighted ? Theme.mutedDeep
                    : Theme.borderSubtle
        border.width: tile.on ? 2 : 1
        scale: tileMa.pressed ? 0.95 : (tile.highlighted ? 1.03 : 1.0)
        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: tile.entry
                    ? (tile.isToggle && !tile.on ? (tile.entry.offGlyph || tile.entry.glyph) : tile.entry.glyph)
                    : ""
                color: tile.on ? tile.accent
                     : tile.highlighted || tileMa.containsMouse ? tile.accent
                     : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: tile.width - 10
                text: tile.entry ? tile.entry.label : ""
                color: tile.on || tile.highlighted ? Theme.fg : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: tile.on || tile.highlighted
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
