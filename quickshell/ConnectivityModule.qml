import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking

Item {
    id: bt
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // activeTab: "bluetooth" or "wifi"
    property string activeTab: "bluetooth"
    // tabIndex: 0 = primary toggle (BT power / wifi enable), 1 = secondary
    // toggle (scan / refresh), 2+ = item in the current tab's list.
    property int tabIndex: 0
    signal navigateNext()
    signal navigatePrev()
    readonly property var currentItems: activeTab === "wifi" ? visibleNetworks
                                      : activeTab === "vpn"  ? TailscaleService.peers
                                      : visibleDevices
    readonly property int tabStopCount: 2 + currentItems.length
    readonly property int selectedIndex: tabIndex >= 2 ? tabIndex - 2 : -1
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter && adapter.enabled
    readonly property var connectedDevices: {
        const list = [];
        if (!Bluetooth.devices) return list;
        for (let i = 0; i < Bluetooth.devices.values.length; i++) {
            const d = Bluetooth.devices.values[i];
            if (d.connected) list.push(d);
        }
        return list;
    }
    readonly property var visibleDevices: {
        const all = (Bluetooth.devices ? Bluetooth.devices.values : []) || [];
        return all.filter(d => d.paired || d.connected).sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
    }

    // ===== Wifi =====
    readonly property var wifiDevice: {
        const devs = Networking.devices ? Networking.devices.values : [];
        for (const d of devs) {
            if (d.type === DeviceType.Wifi) return d;
        }
        return null;
    }
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiConnected: wifiDevice ? wifiDevice.connected : false
    readonly property var visibleNetworks: {
        if (!wifiDevice || !wifiDevice.networks) return [];
        const all = wifiDevice.networks.values || [];
        return all.slice().sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1;
            if (a.known !== b.known) return a.known ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
    }
    readonly property var activeNetwork: {
        for (const n of visibleNetworks) if (n.connected) return n;
        return null;
    }

    // Fast poll while the VPN tab is open (4 s).
    Timer {
        running: bt.popupOpen && bt.activeTab === "vpn"
        interval: 4000
        repeat: true
        triggeredOnStart: true
        onTriggered: TailscaleService.refresh()
    }

    function setTab(name) {
        if (activeTab === name) return;
        activeTab = name;
        tabIndex = 0;
        if (name === "wifi" && wifiDevice) wifiDevice.scannerEnabled = true;
        if (name === "vpn") TailscaleService.refresh();
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            tabIndex = 0;
            if (activeTab === "wifi" && wifiDevice) wifiDevice.scannerEnabled = true;
            if (activeTab === "vpn") TailscaleService.refresh();
        } else {
            if (wifiDevice) wifiDevice.scannerEnabled = false;
        }
    }

    function cycleTab(delta) {
        const n = tabStopCount;
        if (n <= 0) return;
        tabIndex = (tabIndex + delta + n) % n;
    }
    function openAt(idx) {
        popupOpen = true;
        const n = tabStopCount;
        tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
    }
    function activateDevice(i) {
        if (i < 0 || i >= visibleDevices.length) return;
        const d = visibleDevices[i];
        if (d.connected) d.disconnect();
        else d.connect();
    }
    function activateNetwork(i) {
        if (i < 0 || i >= visibleNetworks.length) return;
        const n = visibleNetworks[i];
        if (n.connected) {
            n.disconnect();
        } else {
            n.connect();
            // Close the popup so NetworkManager's password dialog (if it
            // needs one) isn't hidden under our overlay surface.
            popupOpen = false;
        }
    }
    function togglePrimary() {
        if (activeTab === "wifi") Networking.wifiEnabled = !Networking.wifiEnabled;
        else if (activeTab === "vpn") TailscaleService.toggle();
        else if (adapter) adapter.enabled = !adapter.enabled;
    }
    function toggleSecondary() {
        if (activeTab === "wifi") { if (wifiDevice) wifiDevice.scannerEnabled = !wifiDevice.scannerEnabled; }
        else if (activeTab === "vpn") TailscaleService.refresh();
        else if (adapter) adapter.discovering = !adapter.discovering;
    }
    function activateCurrent(i) {
        if (activeTab === "wifi") activateNetwork(i);
        else if (activeTab === "vpn") {
            const p = TailscaleService.peers[i];
            if (p) TailscaleService.copyIp(p.ips[0] || "");
        }
        else activateDevice(i);
    }
    function forgetCurrent(i) {
        if (activeTab === "wifi") {
            const n = visibleNetworks[i];
            if (n && n.known) n.forget();
        } else if (activeTab === "bluetooth") {
            const d = visibleDevices[i];
            if (d) d.forget();
        }
    }

    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 16

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.sm
        Text {
            text: !bt.powered ? "󰂲" : (bt.connectedDevices.length ? "󰂱" : "󰂯")
            color: !bt.powered ? Theme.mutedDeep : "#60a5fa"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            visible: bt.powered && bt.connectedDevices.length > 0
            text: bt.connectedDevices.length
            color: "#60a5fa"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (e) => {
            if (e.button === Qt.RightButton) {
                if (bt.adapter) bt.adapter.enabled = !bt.adapter.enabled;
                return;
            }
            // Open / close the popup, but always land on the Bluetooth tab
            // when clicking the Bluetooth bar icon.
            if (bt.popupOpen && bt.activeTab === "bluetooth") {
                bt.popupOpen = false;
            } else {
                bt.setTab("bluetooth");
                bt.popupOpen = true;
            }
        }
    }

    PopupWindow {
        id: popup
        anchor.window: bt.parentBar
        anchor.rect.x: (bt.parentBar.width - implicitWidth) / 2
        anchor.rect.y: (bt.parentBar.screen.height - implicitHeight) / 2
        implicitWidth: 360
        implicitHeight: contentCol.implicitHeight + 24
        visible: bt.popupOpen
        color: "transparent"

        SproutBg { anchors.fill: parent; fillColor: Theme.bgAlt; borderColor: Theme.borderStrong; showTail: false }
        Item {
            anchors.fill: parent
            focus: bt.popupOpen
            Keys.onPressed: (e) => {
                const n = bt.currentItems.length;
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) {
                    bt.popupOpen = false;
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    bt.navigateNext();
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    bt.navigatePrev();
                    e.accepted = true;
                } else if (e.key === Qt.Key_Tab) {
                    // Tab cycles between Bluetooth / Wifi tabs
                    bt.setTab(bt.activeTab === "wifi" ? "bluetooth" : "wifi");
                    e.accepted = true;
                } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                    bt.cycleTab(1); e.accepted = true;
                } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    bt.cycleTab(-1); e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    if (bt.tabIndex === 0) bt.togglePrimary();
                    else if (bt.tabIndex === 1) bt.toggleSecondary();
                    else bt.activateCurrent(bt.selectedIndex);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                        (bt.selectedIndex + 1 < n ? bt.tabIndex + 1 : 2);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                        (bt.selectedIndex > 0 ? bt.tabIndex - 1 : 1 + n);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                    bt.forgetCurrent(bt.selectedIndex); e.accepted = true;
                }
            }

            ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                // ===== Header with pin + tab strip =====
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: bt.pinned
                        onToggled: bt.pinned = !bt.pinned
                    }

                    // Tab strip: two pills sharing a single rounded container
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 30
                        radius: 15
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 2
                            spacing: 0
                            TabPill {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                glyph: "󰂯"
                                label: "Bluetooth"
                                active: bt.activeTab === "bluetooth"
                                accent: Theme.accent.blue
                                onPicked: bt.setTab("bluetooth")
                            }
                            TabPill {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                glyph: bt.wifiEnabled ? "󰖩" : "󰖪"
                                label: "Wi-Fi"
                                active: bt.activeTab === "wifi"
                                accent: Theme.accent.green
                                onPicked: bt.setTab("wifi")
                            }
                            TabPill {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                glyph: "󰒃"
                                label: "VPN"
                                active: bt.activeTab === "vpn"
                                accent: Theme.accent.purple
                                onPicked: bt.setTab("vpn")
                            }
                        }
                    }
                }

                // ===== Tab content =====
                // Loader.sourceComponent reassignment occasionally leaves
                // a stale item visible during the swap on some Qt versions.
                // Force a clean rebuild by clearing first via a Binding.
                Loader {
                    id: paneLoader
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    active: bt.popupOpen
                    sourceComponent: !bt.popupOpen ? null
                                   : bt.activeTab === "wifi" ? wifiPane
                                   : bt.activeTab === "vpn"  ? vpnPane
                                   : btPane
                }

                Component {
                    id: btPane
                    ColumnLayout {
                        spacing: Theme.spacing.md

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.md
                            Text {
                                text: !bt.adapter ? "No adapter"
                                    : bt.powered
                                        ? (bt.adapter.discovering ? "Scanning…" : (bt.connectedDevices.length + " connected"))
                                        : "Bluetooth is off"
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                            }
                            Item { Layout.fillWidth: true }
                            BtToggle {
                                visible: bt.powered
                                label: bt.adapter && bt.adapter.discovering ? "Stop" : "Scan"
                                active: bt.adapter && bt.adapter.discovering
                                highlighted: bt.tabIndex === 1
                                onClicked: { bt.tabIndex = 1; bt.toggleSecondary() }
                            }
                            BtToggle {
                                label: bt.powered ? "On" : "Off"
                                active: bt.powered
                                highlighted: bt.tabIndex === 0
                                onClicked: { bt.tabIndex = 0; bt.togglePrimary() }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                        Text {
                            Layout.fillWidth: true
                            visible: bt.powered && bt.visibleDevices.length === 0
                            text: "No known devices"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: bt.powered
                            Repeater {
                                model: bt.visibleDevices
                                delegate: BtDeviceRow {
                                    required property var modelData
                                    required property int index
                                    device: modelData
                                    highlighted: bt.selectedIndex === index
                                    onHovered: bt.tabIndex = index + 2
                                }
                            }
                        }
                    }
                }

                Component {
                    id: wifiPane
                    ColumnLayout {
                        spacing: Theme.spacing.md

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.md
                            Text {
                                text: !bt.wifiDevice ? "No wireless adapter"
                                    : !bt.wifiEnabled ? "Wi-Fi is off"
                                    : bt.activeNetwork ? "Connected · " + bt.activeNetwork.name
                                    : (bt.visibleNetworks.length + " networks")
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            BtToggle {
                                visible: bt.wifiEnabled && bt.wifiDevice
                                label: bt.wifiDevice && bt.wifiDevice.scannerEnabled ? "Stop" : "Scan"
                                active: bt.wifiDevice && bt.wifiDevice.scannerEnabled
                                highlighted: bt.tabIndex === 1
                                onClicked: { bt.tabIndex = 1; bt.toggleSecondary() }
                            }
                            BtToggle {
                                label: bt.wifiEnabled ? "On" : "Off"
                                active: bt.wifiEnabled
                                highlighted: bt.tabIndex === 0
                                onClicked: { bt.tabIndex = 0; bt.togglePrimary() }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                        Text {
                            Layout.fillWidth: true
                            visible: bt.wifiEnabled && bt.visibleNetworks.length === 0
                            text: "Scanning for networks…"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !bt.wifiEnabled
                            text: "Turn on Wi-Fi to see networks"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: bt.wifiEnabled
                            Repeater {
                                model: bt.visibleNetworks
                                delegate: WifiNetworkRow {
                                    required property var modelData
                                    required property int index
                                    network: modelData
                                    highlighted: bt.selectedIndex === index
                                    onHovered: bt.tabIndex = index + 2
                                    onPicked: bt.activateNetwork(index)
                                    onForgetRequested: if (network) network.forget()
                                }
                            }
                        }
                    }
                }

                Component {
                    id: vpnPane
                    ColumnLayout {
                        spacing: Theme.spacing.md

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.md
                            Text {
                                Layout.fillWidth: true
                                text: !TailscaleService.daemonOk ? "tailscaled is not running"
                                    : !TailscaleService.running ? "Tailscale is off"
                                    : TailscaleService.tailnet ? TailscaleService.tailnet
                                    : "Connected"
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                elide: Text.ElideRight
                            }
                            BtToggle {
                                visible: TailscaleService.daemonOk
                                label: "Refresh"
                                active: false
                                highlighted: bt.tabIndex === 1
                                onClicked: { bt.tabIndex = 1; TailscaleService.refresh() }
                            }
                            BtToggle {
                                visible: TailscaleService.daemonOk
                                label: TailscaleService.running ? "On" : "Off"
                                active: TailscaleService.running
                                highlighted: bt.tabIndex === 0
                                onClicked: { bt.tabIndex = 0; TailscaleService.toggle() }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }

                        // Self info + daemon hint
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: TailscaleService.daemonOk && TailscaleService.running && TailscaleService.selfIPs.length > 0
                            Text {
                                text: TailscaleService.host
                                color: Theme.fg
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                font.bold: true
                            }
                            Text {
                                text: TailscaleService.selfIPs.join("  ·  ")
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !TailscaleService.daemonOk
                            text: "sudo systemctl enable --now tailscaled"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: TailscaleService.daemonOk && TailscaleService.running && TailscaleService.peers.length === 0
                            text: "No peers"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            horizontalAlignment: Text.AlignHCenter
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            visible: TailscaleService.daemonOk && TailscaleService.running
                            Repeater {
                                model: TailscaleService.peers
                                delegate: VpnPeerRow {
                                    required property var modelData
                                    required property int index
                                    entry: modelData
                                    isExitNode: modelData.id === TailscaleService.exitNodeId
                                    highlighted: bt.selectedIndex === index
                                    onHovered: bt.tabIndex = index + 2
                                    onCopied: TailscaleService.copyIp(modelData.ips[0] || "")
                                    onExitToggled: TailscaleService.setExitNode(modelData.id === TailscaleService.exitNodeId ? "" : modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: bt.popupOpen && !bt.pinned
        windows: [popup]
        onCleared: bt.popupOpen = false
    }
}
