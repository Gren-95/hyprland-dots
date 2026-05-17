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
    Notifications { id: notifService }
    IcsCalendar { id: cal }
    Spotlight { id: spotlight }
    Clipboard { id: clipboard }
    Osd { id: osd }
    Keybinds { id: keybinds }
    PowerMenu { id: powerMenu }
    WorkspaceOverview { id: workspaceOverview }
    ScreenRecorder { id: recorder }
    PolkitPrompt { id: polkit }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            implicitHeight: 36
            color: "transparent"

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
                        }
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
                        glyph: "󰀻"
                        pixelSize: Theme.fontSize.xl
                        tooltip: "Open app launcher"
                        onClicked: spotlight.toggle()
                    }
                    BarSep {}

                    WorkspaceStrip {
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
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    RowLayout {
                        spacing: Theme.spacing.md
                        Repeater {
                            model: SystemTray.items
                            delegate: TrayItem {
                                required property SystemTrayItem modelData
                                item: modelData
                                anchorWindow: bar
                            }
                        }
                    }

                    QuickActions {
                        id: quickMod
                        parentBar: bar
                    }
                    BarSep {}

                    ConnectivityModule {
                        id: btMod
                        parentBar: bar
                        onNavigateNext: { popupOpen = false; apMod.openAt("sound") }
                        onNavigatePrev: { popupOpen = false; cal.openAt(0) }
                    }

                    // Wi-Fi indicator — opens the same popup as Bluetooth but
                    // on the Wi-Fi tab.
                    BarIcon {
                        id: wifiIcon
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
                        tooltip: !enabled ? "Wi-Fi off"
                            : connected && btMod.activeNetwork ? btMod.activeNetwork.name
                            : "Wi-Fi"
                        onClicked: btMod.openTab("wifi")
                    }

                    // VPN indicator — only visible when Tailscale is up.
                    BarIcon {
                        id: vpnIcon
                        visible: TailscaleService.running
                        glyph: "󰒃"
                        color: Theme.accent.purple
                        pixelSize: Theme.fontSize.md
                        tooltip: TailscaleService.tailnet || "VPN"
                        onClicked: btMod.openTab("vpn")
                    }

                    BarSep {}

                    AudioPowerModule {
                        id: apMod
                        parentBar: bar
                        onNavigateNext: { popupOpen = false; spotlight.openAt(0) }
                        onNavigatePrev: { popupOpen = false; btMod.openAt(-1) }
                    }

                    // Battery: opens AudioPowerModule on the Power tab.
                    BarIcon {
                        id: batteryIcon
                        onClicked: apMod.openTab("power")
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
                            if (!dev) return "";
                            if (charging && dev.timeToFull > 0)
                                return Math.round(dev.timeToFull / 60) + " min to full";
                            if (dev.timeToEmpty > 0)
                                return Math.round(dev.timeToEmpty / 60) + " min left";
                            return "";
                        }
                        onWheel: (up) => {
                            brightProc.command = ["brightnessctl", "set", up ? "+5%" : "5%-"];
                            brightProc.startDetached();
                        }
                        Process { id: brightProc; command: [] }
                    }

                    // Microphone (only when unmuted)
                    BarIcon {
                        readonly property var src: Pipewire.defaultAudioSource
                        visible: src && src.audio && !src.audio.muted
                        glyph: "󰍬"
                        color: Theme.accent.orange
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
                    description: "Toggle power menu"
                    onPressed: powerMenu.toggle()
                }
                GlobalShortcut {
                    appid: "quickshell"
                    name: "bluetooth"
                    description: "Toggle bluetooth menu"
                    onPressed: btMod.popupOpen = !btMod.popupOpen
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
