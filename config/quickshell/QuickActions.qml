// Quick Actions overflow panel. Bar chevron opens a flyout with hidden tray
// apps up top and a 3-column grid of tiles below: stateful toggles (with
// explicit on/off state), one-shot actions and tucked bar modules.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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
        { glyph: "󰹑", label: "Screenshot",   accent: Theme.accent.blueBright, action: "screenshot", cmd: ["bash", Paths.scripts + "/screenshot.sh"] },
        { glyph: "󰕧", label: "Record",       accent: Theme.accent.red, action: "record", cmd: ["bash", Paths.scripts + "/screenrecord.sh"] },
        { glyph: "󰈊", label: "Color picker", accent: Theme.accent.pink, action: "colorpicker", cmd: ["hyprpicker", "-a"] },
        { glyph: "󰋖", label: "Keybinds",     accent: Theme.accent.blue, action: "keybinds" },
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
    readonly property int gridColumns: 3
    readonly property var gridItems: toggles.concat(oneShots).concat(tuckedModules)

    Layout.fillHeight: true
    implicitWidth: 40

    BarHover { hovered: chevronMa.containsMouse; active: actions.popupOpen }

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
        id: chevronMa
        anchors.fill: parent
        hoverEnabled: true
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

    // Popup height follows the content (up to what the screen allows), so
    // there is never empty space under the last control.
    readonly property real fitHeight: Math.min(
        parentBar && parentBar.screen ? parentBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)

    BarFlyout {
        id: actionsPopup
        parentBar: actions.parentBar
        anchorItem: actions._openAnchor ?? actions.flyoutAnchor ?? actions
        open: actions.popupOpen
        pinned: actions.pinned || actions.menusOpen > 0
        cardWidth: settingsStore.flyoutSize("quickactions", "w", 460)
        cardHeight: settingsStore.flyoutSize("quickactions", "h", actions.fitHeight)
        onDismissed: actions.popupOpen = false

        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
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
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: actions.pinned
                    onToggled: actions.pinned = !actions.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "Quick actions"
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

                    // Hidden tray apps (placement "Tuck" in the Bar tab).
                    Rectangle {
                        Layout.fillWidth: true
                        visible: actions.overflowTray.length > 0
                        implicitHeight: trayCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: trayCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.lg
                            Text {
                                text: "TRAY"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                                font.letterSpacing: 1
                                font.bold: true
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.sm
                                Repeater {
                                    model: actions.overflowTray
                                    delegate: TrayItem {
                                        required property var modelData
                                        item: modelData
                                        anchorWindow: actions.parentBar
                                        implicitWidth: 44
                                        implicitHeight: 44
                                        onMenuOpenChanged: actions.menusOpen += menuOpen ? 1 : -1
                                    }
                                }
                            }
                        }
                    }

                    // Every action as a state tile, with a status line for the
                    // highlighted one.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: gridCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: gridCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.lg
                            Text {
                                text: "ACTIONS"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                                font.letterSpacing: 1
                                font.bold: true
                            }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: actions.gridColumns
                                columnSpacing: Theme.spacing.md
                                rowSpacing: Theme.spacing.md
                                Repeater {
                                    model: actions.gridItems
                                    delegate: QaTile {
                                        required property var modelData
                                        required property int index
                                        entry: modelData
                                        isToggle: actions.isToggleAction(modelData.action)
                                        on: isToggle && actions.toggleState(modelData.action)
                                        highlighted: actions.selectedIndex === index
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        onPicked: actions.activate(index)
                                        onHovered: actions.selectedIndex = index
                                    }
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                readonly property var cur: actions.gridItems[actions.selectedIndex]
                                text: cur ? (actions.isToggleAction(cur.action) ? actions.toggleDesc(cur.action) : cur.label) : ""
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "←→↑↓ move · ↵ select"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
