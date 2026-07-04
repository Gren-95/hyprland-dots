//@ pragma UseQApplication

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Scope {
    // Shared stores, instantiated FIRST so every sibling below (and the
    // components they create) resolves them via the id scope chain — the
    // same proven pattern as notifService. These were `pragma Singleton`
    // files before, but config singletons don't reliably instantiate on a
    // cold start: consumer binding reads just return undefined until a
    // change notification happens to heal them.
    Settings { id: settingsStore }
    PopupManager { id: popupManager }

    // Push the appearance settings into the Theme singleton (it can't
    // resolve settingsStore itself — singletons sit outside this scope).
    Binding { target: Theme; property: "fontScale";         value: settingsStore.fontScale }
    Binding { target: Theme; property: "fontFamily";        value: settingsStore.fontFamily }
    Binding { target: Theme; property: "accentPrimaryName"; value: settingsStore.accentPrimaryName }

    Notifications { id: notifService }
    IcsCalendar { id: cal }
    Spotlight { id: spotlight }
    Clipboard { id: clipboard }
    Osd { id: osd }
    Keybinds { id: keybinds }
    WorkspaceOverview { id: workspaceOverview }
    ScreenRecorder { id: recorder }
    PolkitPrompt { id: polkit }
    SystemMonitor { id: sysmon }
    WallpaperPicker { id: wallpaperPicker }
    SettingsPanel { id: settingsPanel }
    RegionSelector { id: regionSelector }
    ScreenshotActions { id: screenshotActions }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: settingsStore.barHeight
            color: "transparent"

            // Anchor the shared flyout modals to this bar's items. On
            // multi-monitor the last-created bar wins (same as the calendar).
            Component.onCompleted: {
                spotlight.anchorBar = bar;       spotlight.anchorItem = launcherIcon;
                // Quick-Actions residents default to the QA chevron, but the
                // chevron can be hidden (placement, or everything promoted) —
                // so the default is a LIVE binding falling back to the
                // overflow chevron, then bar-center (null). Anchoring to an
                // invisible item puts the flyout at a garbage position.
                const qaOr = () => quickMod.visible ? quickMod
                            : overflowChevron.visible ? overflowChevron : null;
                clipboard.anchorBar = bar;       clipboard.anchorItem = Qt.binding(qaOr);
                keybinds.anchorBar = bar;        keybinds.anchorItem = Qt.binding(qaOr);
                wallpaperPicker.anchorBar = bar; wallpaperPicker.anchorItem = Qt.binding(qaOr);
                settingsPanel.anchorBar = bar;   settingsPanel.anchorItem = Qt.binding(qaOr);
                sysmon.anchorBar = bar;          sysmon.anchorItem = clockAnchor;
            }

            Rectangle {
                id: barRect
                anchors.fill: parent
                color: Theme.bgAlt
                radius: 0
                border.width: 0

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.mutedDeep
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (e) => {
                        const dir = e.angleDelta.y > 0 ? "e+1" : "e-1";
                        Hyprland.dispatch("workspace " + dir);
                    }
                }

                Timer {
                    id: clockTimer
                    property date now: new Date()
                    interval: 1000; running: true; repeat: true
                    onTriggered: now = new Date()
                }

                // ============ CENTER (absolute, anchored to monitor center) ============
                Item {
                    id: clockAnchor
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: clockRow.implicitWidth + 12
                    implicitHeight: clockRow.implicitHeight + 4
                    Component.onCompleted: { cal.anchorBar = bar; cal.anchorItem = clockAnchor; }

                    HoverHandler { id: clockHover }
                    BarTooltip {
                        bar: bar
                        target: clockAnchor
                        text: "Calendar · Super+D"
                        active: clockHover.hovered && !cal.open
                    }

                    RowLayout {
                        id: clockRow
                        anchors.centerIn: parent
                        spacing: Theme.spacing.md

                        // Date + time wrapper — owns the calendar click region.
                        Item {
                            Layout.preferredWidth: dateTimeRow.implicitWidth
                            Layout.preferredHeight: dateTimeRow.implicitHeight
                            RowLayout {
                                id: dateTimeRow
                                anchors.centerIn: parent
                                spacing: Theme.spacing.md
                                Text {
                                    text: "  " + Qt.formatDate(clockTimer.now, "ddd, dd MMM")
                                    color: Theme.muted
                                    font { family: Theme.font; pixelSize: Theme.fontSize.base }
                                }
                                Text {
                                    text: Qt.formatTime(clockTimer.now, "HH:mm")
                                    color: "#f5f5f4"
                                    font { family: Theme.font; pixelSize: Theme.fontSize.md; bold: true }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    cal.anchorBar = bar;
                                    cal.anchorItem = clockAnchor;
                                    cal.toggle();
                                }
                            }
                        }

                        NotifBell {
                            parentBar: bar
                            notifs: notifService
                            visible: settingsStore.placement("bell") === "bar"
                        }

                        // iOS-style status icons (camera / mic / recording /
                        // remote access / sleep-inhibit) next to the bell.
                        StatusIndicators {
                            parentBar: bar
                        }
                    }
                }

                // Slot for the media transport cluster — fills the gap
                // between the clock (centered) and the right systray, and
                // centers MediaKeys inside that slot. Visibility toggled
                // from Quick Actions.
                Item {
                    id: mediaKeysSlot
                    anchors.left: clockAnchor.right
                    anchors.right: rightGroup.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.spacing.lg
                    anchors.rightMargin: Theme.spacing.lg

                    MediaKeys {
                        id: mediaKeys
                        parentBar: bar
                        anchors.centerIn: parent
                    }
                }

                // ============ LEFT ============
                RowLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    BarIcon {
                        id: launcherIcon
                        parentBar: bar
                        glyph: "󰀻"
                        pixelSize: Theme.fontSize.xl
                        tooltip: "App launcher · Super+R"
                        onClicked: spotlight.toggle()
                    }
                    BarSep {}

                    WorkspaceStrip {
                        parentBar: bar
                        glyphFn: workspaceGlyph
                    }

                    Item { width: 8 }
                    Text {
                        Layout.maximumWidth: 400
                        elide: Text.ElideRight
                        text: Hyprland.activeToplevel ? Hyprland.activeToplevel.title : ""
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                    }
                }

                // ============ RIGHT ============
                RowLayout {
                    id: rightGroup
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    // Windows-style hidden-tray chevron: hosts everything
                    // placed in "overflow" via the Settings Bar tab.
                    OverflowChevron {
                        id: overflowChevron
                        parentBar: bar
                        entries: [
                            { id: "network",      label: "Network",       glyph: () => "󰂯",              color: () => Theme.fgMuted,        open: (a) => btMod.openTab("bluetooth", a) },
                            { id: "wifi",         label: "Wi-Fi",         glyph: () => wifiIcon.glyph,    color: () => wifiIcon.color,       open: (a) => btMod.openTab("wifi", a) },
                            { id: "vpn",          label: "VPN",           glyph: () => "󰒃",              color: () => TailscaleService.running ? Theme.accent.purple : Theme.muted, open: (a) => btMod.openTab("vpn", a) },
                            { id: "audiopower",   label: "Sound",         glyph: () => "󰕾",              color: () => Theme.fgMuted,        open: (a) => apMod.openTab("sound", a) },
                            { id: "battery",      label: "Battery",       glyph: () => batteryIcon.glyph, color: () => batteryIcon.color,    open: (a) => apMod.openTab("power", a) },
                            { id: "mic",          label: "Mute microphone", glyph: () => "󰍬",            color: () => Theme.accent.orange,  when: () => micIcon.unmuted, open: (a) => { if (micIcon.src && micIcon.src.audio) micIcon.src.audio.muted = true; } },
                            { id: "quickactions", label: "Quick actions", glyph: () => "󰍝",              color: () => Theme.fgMuted,        open: (a) => { quickMod._openAnchor = a; quickMod.popupOpen = true; } },
                        ]
                    }

                    RowLayout {
                        spacing: Theme.spacing.md
                        Repeater {
                            // Only tray apps placed on the bar; the rest live
                            // in the overflow chevron (or are hidden).
                            model: {
                                const list = (SystemTray.items && SystemTray.items.values) || [];
                                return list.filter(t => settingsStore.trayPlacementOf(t.id || t.title) === "bar");
                            }
                            delegate: TrayItem {
                                required property SystemTrayItem modelData
                                item: modelData
                                anchorWindow: bar
                            }
                        }
                    }

                    // Quick Actions items promoted to the bar ("Bar" in the
                    // Settings Bar tab), rendered as first-class bar icons.
                    Repeater {
                        model: quickMod.promotedItems
                        delegate: QuickActionIcon {
                            required property var modelData
                            entry: modelData
                            actions: quickMod
                            parentBar: bar
                        }
                    }
                    BarSep { visible: quickMod.promotedItems.length > 0 }

                    QuickActions {
                        id: quickMod
                        parentBar: bar
                        // Hide the chevron too when every item has been
                        // promoted or hidden — an empty panel is useless.
                        visible: settingsStore.placement("quickactions") === "bar" && totalItems > 0
                        flyoutAnchor: visible ? null : (overflowChevron.visible ? overflowChevron : null)
                    }
                    BarSep {}

                    ConnectivityModule {
                        id: btMod
                        parentBar: bar
                        visible: settingsStore.placement("network") === "bar"
                        flyoutAnchor: visible ? null : (overflowChevron.visible ? overflowChevron : null)
                        onNavigateNext: { popupOpen = false; apMod.openAt("sound") }
                        onNavigatePrev: { popupOpen = false; cal.openAt(0) }
                    }

                    // Wi-Fi indicator — opens the same popup as Bluetooth but
                    // on the Wi-Fi tab.
                    BarIcon {
                        id: wifiIcon
                        parentBar: bar
                        visible: settingsStore.placement("wifi") === "bar"
                        readonly property var dev: btMod.wifiDevice
                        readonly property bool enabled: btMod.wifiEnabled
                        readonly property bool connected: btMod.wifiConnected
                        glyph: !enabled ? "󰖪"
                            : connected ? "󰖩"
                            : "󰤨"
                        color: !enabled ? Theme.mutedDeep
                            : connected ? Theme.accent.green
                            : Theme.muted
                        pixelSize: Theme.fontSize.md
                        tooltip: (!enabled ? "Wi-Fi off"
                            : connected && btMod.activeNetwork ? btMod.activeNetwork.name
                            : "Wi-Fi") + " · Super+Shift+B"
                        onClicked: btMod.openTab("wifi", wifiIcon)
                    }

                    // VPN indicator — a network satellite like the Wi-Fi icon:
                    // always present, state shown by color, click opens the
                    // Network flyout's VPN tab (toggle, peers, exit nodes).
                    BarIcon {
                        id: vpnIcon
                        parentBar: bar
                        visible: settingsStore.placement("vpn") === "bar"
                        glyph: "󰒃"
                        color: !TailscaleService.daemonOk ? Theme.mutedDeep
                             : TailscaleService.running ? Theme.accent.purple
                             : Theme.muted
                        pixelSize: Theme.fontSize.md
                        tooltip: (!TailscaleService.daemonOk ? "VPN daemon down"
                            : TailscaleService.running ? (TailscaleService.tailnet || "VPN up")
                            : "VPN off") + " · Super+Shift+B"
                        onClicked: btMod.openTab("vpn", vpnIcon)
                    }

                    BarSep {}

                    AudioPowerModule {
                        id: apMod
                        parentBar: bar
                        visible: settingsStore.placement("audiopower") === "bar"
                        flyoutAnchor: visible ? null : (overflowChevron.visible ? overflowChevron : null)
                        onNavigateNext: { popupOpen = false; spotlight.openAt(0) }
                        onNavigatePrev: { popupOpen = false; btMod.openAt(-1) }
                    }

                    // Battery: opens AudioPowerModule on the Power tab.
                    BarIcon {
                        id: batteryIcon
                        parentBar: bar
                        visible: settingsStore.placement("battery") === "bar"
                        onClicked: apMod.openTab("power", batteryIcon)
                        readonly property var dev: UPower.displayDevice
                        readonly property int pct: dev ? Math.round(dev.percentage * 100) : 0
                        readonly property bool charging: dev && (dev.state === UPowerDeviceState.Charging
                            || dev.state === UPowerDeviceState.FullyCharged)
                        readonly property bool plugged: dev && !UPower.onBattery
                        glyph: {
                            if (charging) return "󰂄";
                            if (plugged) return "󰂏";
                            const icons = ["󰂎","󰁺","󰁾","󰂀","󰁹"];
                            return icons[Math.min(4, Math.floor(pct / 21))];
                        }
                        label: pct + "%"
                        color: {
                            if (charging || plugged) return Theme.accent.green;
                            if (pct <= 20) return Theme.accent.red;
                            return Theme.accent.yellow;
                        }
                        tooltip: {
                            const kb = " · Super+S";
                            if (charging && dev && dev.timeToFull > 0)
                                return Math.round(dev.timeToFull / 60) + " min to full" + kb;
                            if (dev && dev.timeToEmpty > 0)
                                return Math.round(dev.timeToEmpty / 60) + " min left" + kb;
                            return "Audio & Power" + kb;
                        }
                        onWheel: (up) => {
                            brightProc.command = ["brightnessctl", "set", up ? "+5%" : "5%-"];
                            brightProc.startDetached();
                        }
                        Process { id: brightProc; command: [] }
                    }

                    // Microphone (only when unmuted)
                    BarIcon {
                        id: micIcon
                        parentBar: bar
                        readonly property var src: Pipewire.defaultAudioSource
                        readonly property bool unmuted: src && src.audio ? !src.audio.muted : false
                        visible: unmuted && settingsStore.placement("mic") === "bar"
                        glyph: "󰍬"
                        color: Theme.accent.orange
                        tooltip: "Mute microphone"
                        onClicked: {
                            if (src && src.audio) src.audio.muted = true;
                        }
                        PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
                    }

                }

                Connections {
                    target: cal
                    function onNavigateNext() { cal.close(); btMod.openAt(0) }
                    function onNavigatePrev() { cal.close(); spotlight.openAt(0) }
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "spotlight"
                    description: "Toggle app launcher"
                    onPressed: spotlight.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "clipboard"
                    description: "Toggle clipboard history selector"
                    onPressed: clipboard.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "keybinds"
                    description: "Toggle keybinds viewer"
                    onPressed: keybinds.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "powermenu"
                    description: "Open the Power tab (session actions live there)"
                    onPressed: apMod.openTab("power")
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "sysmon"
                    description: "Toggle system monitor"
                    onPressed: sysmon.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "quickactions"
                    description: "Toggle quick actions panel"
                    onPressed: quickMod.popupOpen = !quickMod.popupOpen
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "audiopower"
                    description: "Toggle audio & power panel (Sound tab)"
                    onPressed: apMod.openTab("sound")
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "calendar"
                    description: "Toggle calendar popup"
                    onPressed: { cal.anchorBar = bar; cal.anchorItem = clockAnchor; cal.toggle() }
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "wallpaper"
                    description: "Toggle wallpaper picker"
                    onPressed: wallpaperPicker.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "settings"
                    description: "Toggle shell settings panel"
                    onPressed: settingsPanel.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "screenshot-region"
                    description: "Pick a region with the Quickshell region selector"
                    onPressed: regionSelector.start()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "bluetooth"
                    description: "Toggle bluetooth menu"
                    onPressed: { btMod._openAnchor = null; btMod.popupOpen = !btMod.popupOpen }
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "notifications"
                    description: "Toggle notification center"
                    onPressed: notifService.toggleCenter()
                }
                // Classic Super+Tab: open + cycle on Tab presses, release Super commits.
                GlobalShortcut {
                    appid: "quickshell"
                    name: "overview-cycle"
                    description: "Open overview / cycle next workspace"
                    onPressed: workspaceOverview.cycleOrOpen(1)
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "overview-cycle-prev"
                    description: "Open overview / cycle previous workspace"
                    onPressed: workspaceOverview.cycleOrOpen(-1)
                }
                // Listens to Super press/release via bindi. Press is a no-op,
                // release commits the highlighted workspace if overview is open.
                GlobalShortcut {
                    appid: "quickshell"
                    name: "supertap"
                    description: "Commit overview selection on Super release"
                    onReleased: workspaceOverview.commitIfOpen()
                }
            }
        }
    }

    function workspaceGlyph(id) {
        const m = {1:"",2:"",3:"",4:"",5:"",6:"",7:"",8:"",9:""};
        return m[id] || "";
    }

}
