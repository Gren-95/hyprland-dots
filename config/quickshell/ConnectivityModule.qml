import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Bluetooth

// Bluetooth flyout. Wi-Fi, wired and Tailscale are handled by the nm-applet
// tray app, not by the shell.
Item {
    id: bt
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override set by toggleOpen(from). Fallback: own icon.
    property Item flyoutAnchor: null
    property Item _openAnchor: null
    // tabIndex: 0 = power, 1 = scan, then paired devices, then discovered
    // (unpaired) devices.
    property int tabIndex: 0
    // Address of the device whose details are revealed ("" = none).
    property string expandedAddress: ""
    signal navigateNext()
    signal navigatePrev()
    readonly property int tabStopCount: 2 + visibleDevices.length + availableDevices.length
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
    // Discovered but not paired. Unnamed ones (bare MAC addresses) are noise.
    readonly property var availableDevices: {
        const all = (Bluetooth.devices ? Bluetooth.devices.values : []) || [];
        const macLike = /^([0-9a-f]{2}[-:]){5}[0-9a-f]{2}$/i;
        return all.filter(d => !d.paired && !d.connected && d.name && !macLike.test(d.name))
                  .sort((a, b) => (a.name || "").localeCompare(b.name || ""));
    }
    // The device behind a list stop (paired first, then available).
    function deviceAtStop(stop) {
        const i = stop - 2;
        if (i < 0) return null;
        if (i < visibleDevices.length) return visibleDevices[i];
        return availableDevices[i - visibleDevices.length] ?? null;
    }
    readonly property var selectedDevice: deviceAtStop(tabIndex)

    // Popup height follows the content (up to what the screen allows), so
    // there is never empty space under the last control.
    readonly property real fitHeight: Math.min(
        parentBar && parentBar.screen ? parentBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)

    // The popup keeps the height it had when it opened: revealing a device
    // list or details scrolls inside instead of growing the popup.
    property real lockedHeight: 0
    Timer {
        id: lockTimer
        interval: 60
        onTriggered: bt.lockedHeight = bt.fitHeight
    }

    // Toggle the popup. `from` (optional) re-anchors the flyout under the
    // bar item that opened it (overflow rows, spotlight). Omitted → default.
    function toggleOpen(from) {
        _openAnchor = from ?? null;
        popupOpen = !popupOpen;
    }

    onPopupOpenChanged: {
        lockedHeight = 0;
        if (popupOpen) {
            tabIndex = 0;
            expandedAddress = "";
            lockTimer.restart();
        }
    }

    function cycleTab(delta) {
        const n = tabStopCount;
        if (n <= 0) return;
        tabIndex = (tabIndex + delta + n) % n;
    }
    function openAt(idx) {
        _openAnchor = null;   // ring hops open at the module's own anchor
        popupOpen = true;
        const n = tabStopCount;
        tabIndex = idx < 0 ? Math.max(0, n - 1) : Math.min(idx, Math.max(0, n - 1));
    }
    // Enter on a device: connect or disconnect a paired one, pair a new one.
    function activateDevice(d) {
        if (!d) return;
        if (!d.paired && !d.connected) { d.trusted = true; d.pair(); }
        else if (d.connected) d.disconnect();
        else d.connect();
    }
    function toggleExpand(d) {
        if (!d || !(d.paired || d.connected)) return;
        expandedAddress = expandedAddress === d.address ? "" : d.address;
    }
    function togglePrimary() { if (adapter) adapter.enabled = !adapter.enabled; }
    function toggleSecondary() { if (adapter) adapter.discovering = !adapter.discovering; }
    function forgetSelected() {
        const d = selectedDevice;
        if (d && (d.paired || d.connected)) d.forget();
    }

    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 20

    BarHover { hovered: btHover.hovered; active: bt.popupOpen && (bt._openAnchor ?? bt.flyoutAnchor ?? bt) === bt }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.sm
        Text {
            text: !bt.powered ? "󰂲" : (bt.connectedDevices.length ? "󰂱" : "󰂯")
            color: !bt.powered ? Theme.mutedDeep : Theme.accent.blueBright
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        Text {
            visible: bt.powered && bt.connectedDevices.length > 0
            text: bt.connectedDevices.length
            color: Theme.accent.blueBright
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
            bt.toggleOpen();
        }
    }

    HoverHandler { id: btHover }
    BarTooltip {
        bar: bt.parentBar
        target: bt
        text: "Bluetooth · Super+Shift+B"
        active: btHover.hovered && !bt.popupOpen
    }

    BarFlyout {
        id: popup
        parentBar: bt.parentBar
        anchorItem: bt._openAnchor ?? bt.flyoutAnchor ?? bt
        open: bt.popupOpen
        cardWidth: settingsStore.flyoutSize("network", "w", 460)
        cardHeight: settingsStore.flyoutSize("network", "h", bt.lockedHeight > 0 ? bt.lockedHeight : bt.fitHeight)
        pinned: bt.pinned
        onDismissed: bt.popupOpen = false
        onKeyPressed: (e) => {
            const n = bt.tabStopCount - 2;
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                bt.navigateNext();
                e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                bt.navigatePrev();
                e.accepted = true;
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                bt.cycleTab(1); e.accepted = true;
            } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                bt.cycleTab(-1); e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (bt.tabIndex === 0) bt.togglePrimary();
                else if (bt.tabIndex === 1) bt.toggleSecondary();
                else bt.activateDevice(bt.selectedDevice);
                e.accepted = true;
            } else if (e.key === Qt.Key_D || e.key === Qt.Key_Space) {
                if (bt.tabIndex >= 2) bt.toggleExpand(bt.selectedDevice);
                e.accepted = true;
            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                    (bt.selectedIndex + 1 < n ? bt.tabIndex + 1 : 2);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                // From the top row (tabIndex 0/1), Up wraps to the LAST
                // list item rather than diving into the first one.
                if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? (1 + n) :
                    (bt.selectedIndex > 0 ? bt.tabIndex - 1 : 1 + n);
                e.accepted = true;
            } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                bt.forgetSelected(); e.accepted = true;
            }
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            // ===== Header =====
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: bt.pinned
                    onToggled: bt.pinned = !bt.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "Bluetooth"
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
                id: btFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: btCol.implicitHeight
                clip: true
                contentWidth: width
                contentHeight: btCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {
                    policy: btFlick.contentHeight > btFlick.height + 2 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: btCol
                    width: btFlick.width - Theme.spacing.md
                    spacing: Theme.spacing.lg

                    // ===== Adapter card: power button, status, scan =====
                    Rectangle {
                        id: adapterCard
                        Layout.fillWidth: true
                        implicitHeight: 104
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.xl

                            // Power button with radar rings while scanning.
                            Item {
                                id: powerBox
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 64
                                Layout.alignment: Qt.AlignVCenter
                                readonly property bool scanning: bt.powered && !!bt.adapter && bt.adapter.discovering

                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        id: ring
                                        required property int index
                                        anchors.centerIn: parent
                                        width: 56; height: 56; radius: 28
                                        color: "transparent"
                                        border.color: Theme.accent.blue
                                        border.width: 2
                                        opacity: 0
                                        scale: 1
                                        visible: powerBox.scanning
                                        SequentialAnimation {
                                            running: powerBox.scanning && bt.popupOpen
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: ring.index * 550 }
                                            ParallelAnimation {
                                                NumberAnimation { target: ring; property: "scale"; from: 1.0; to: 1.55; duration: 1650; easing.type: Easing.OutCubic }
                                                NumberAnimation { target: ring; property: "opacity"; from: 0.55; to: 0.0; duration: 1650; easing.type: Easing.OutCubic }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: powerBtn
                                    anchors.centerIn: parent
                                    width: 56; height: 56; radius: 28
                                    color: bt.powered ? Theme.accent.blueDeep : Theme.bgInset
                                    border.color: bt.tabIndex === 0 ? Theme.fg : (bt.powered ? Theme.accent.blue : Theme.borderStrong)
                                    border.width: bt.tabIndex === 0 ? 2 : 1
                                    scale: pwrMa.pressed ? 0.9 : 1.0
                                    Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                                    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: bt.powered ? "󰂯" : "󰂲"
                                        color: bt.powered ? Theme.fg : Theme.mutedDeep
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.hero
                                        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                                    }
                                    MouseArea {
                                        id: pwrMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { bt.tabIndex = 0; bt.togglePrimary(); }
                                        onContainsMouseChanged: if (containsMouse) bt.tabIndex = 0
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: bt.adapter && bt.adapter.name ? bt.adapter.name : "Bluetooth"
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.md
                                    font.bold: true
                                }
                                Text {
                                    id: statusText
                                    property int dots: 0
                                    Layout.fillWidth: true
                                    text: !bt.adapter ? "No adapter"
                                        : !bt.powered ? "Off"
                                        : bt.adapter.discovering ? "Scanning" + ".".repeat(dots)
                                        : bt.connectedDevices.length > 0 ? bt.connectedDevices.length + " connected"
                                        : "On, nothing connected"
                                    color: bt.powered ? (bt.connectedDevices.length > 0 ? Theme.accent.green : Theme.muted) : Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.base
                                    Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                                    Timer {
                                        interval: 380
                                        repeat: true
                                        running: !!bt.adapter && bt.adapter.discovering && bt.popupOpen
                                        onTriggered: statusText.dots = (statusText.dots + 1) % 4
                                    }
                                }
                            }

                            // Scan button
                            Rectangle {
                                visible: bt.powered
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: scanRow.implicitWidth + 28
                                implicitHeight: 38
                                radius: height / 2
                                color: scanMa.containsMouse || powerBox.scanning ? Theme.bgActive : Theme.bgInset
                                border.color: bt.tabIndex === 1 ? Theme.fg : (powerBox.scanning ? Theme.accent.blue : Theme.borderStrong)
                                border.width: bt.tabIndex === 1 ? 2 : 1
                                scale: scanMa.pressed ? 0.94 : 1.0
                                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                                Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                                Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                                RowLayout {
                                    id: scanRow
                                    anchors.centerIn: parent
                                    spacing: Theme.spacing.sm
                                    Text {
                                        text: "󰑐"
                                        color: powerBox.scanning ? Theme.accent.blueBright : Theme.fgMuted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.lg
                                        RotationAnimator on rotation {
                                            running: powerBox.scanning && bt.popupOpen
                                            from: 0; to: 360; duration: 1400
                                            loops: Animation.Infinite
                                        }
                                    }
                                    Text {
                                        text: powerBox.scanning ? "Stop" : "Scan"
                                        color: Theme.fg
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.base
                                    }
                                }
                                MouseArea {
                                    id: scanMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { bt.tabIndex = 1; bt.toggleSecondary(); }
                                    onContainsMouseChanged: if (containsMouse) bt.tabIndex = 1
                                }
                            }
                        }
                    }

                    // ===== My devices =====
                    Rectangle {
                        Layout.fillWidth: true
                        visible: bt.powered
                        implicitHeight: myCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: myCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.md
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "MY DEVICES"
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: bt.visibleDevices.length
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacing.md
                                Layout.bottomMargin: Theme.spacing.md
                                visible: bt.visibleDevices.length === 0
                                text: "No paired devices yet. Scan to find some."
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                horizontalAlignment: Text.AlignHCenter
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Repeater {
                                    model: bt.visibleDevices
                                    delegate: BtDeviceRow {
                                        required property var modelData
                                        required property int index
                                        device: modelData
                                        highlighted: bt.selectedIndex === index
                                        expanded: bt.expandedAddress === modelData.address
                                        onHovered: bt.tabIndex = index + 2
                                        onExpandToggled: bt.toggleExpand(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // ===== Available (discovered, not paired) =====
                    Rectangle {
                        Layout.fillWidth: true
                        visible: bt.powered && (powerBox.scanning || bt.availableDevices.length > 0)
                        implicitHeight: avCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: avCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.md
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "AVAILABLE"
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                                Item { Layout.fillWidth: true }
                                Spinner {
                                    visible: powerBox.scanning
                                    color: Theme.accent.blueBright
                                    implicitWidth: 14
                                    implicitHeight: 14
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacing.md
                                Layout.bottomMargin: Theme.spacing.md
                                visible: bt.availableDevices.length === 0
                                text: "Looking for devices…"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.base
                                horizontalAlignment: Text.AlignHCenter
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Repeater {
                                    model: bt.availableDevices
                                    delegate: BtDeviceRow {
                                        required property var modelData
                                        required property int index
                                        device: modelData
                                        available: true
                                        highlighted: bt.selectedIndex === bt.visibleDevices.length + index
                                        onHovered: bt.tabIndex = bt.visibleDevices.length + index + 2
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "↑↓ move · ↵ select · D details · del forget · esc close"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
