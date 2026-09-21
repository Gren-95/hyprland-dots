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
    // tabIndex: 0 = power toggle, 1 = scan toggle, 2+ = device in the list.
    property int tabIndex: 0
    signal navigateNext()
    signal navigatePrev()
    readonly property int tabStopCount: 2 + visibleDevices.length
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

    // Toggle the popup. `from` (optional) re-anchors the flyout under the
    // bar item that opened it (overflow rows, spotlight). Omitted → default.
    function toggleOpen(from) {
        _openAnchor = from ?? null;
        popupOpen = !popupOpen;
    }

    onPopupOpenChanged: if (popupOpen) tabIndex = 0

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
    function activateDevice(i) {
        if (i < 0 || i >= visibleDevices.length) return;
        const d = visibleDevices[i];
        if (d.connected) d.disconnect();
        else d.connect();
    }
    function togglePrimary() { if (adapter) adapter.enabled = !adapter.enabled; }
    function toggleSecondary() { if (adapter) adapter.discovering = !adapter.discovering; }
    function forgetDevice(i) {
        const d = visibleDevices[i];
        if (d) d.forget();
    }

    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 16

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
        cardWidth: settingsStore.flyoutSize("network", "w", 360)
        cardHeight: settingsStore.flyoutSize("network", "h", 460)
        pinned: bt.pinned
        onDismissed: bt.popupOpen = false
        onKeyPressed: (e) => {
            const n = bt.visibleDevices.length;
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
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                bt.cycleTab(1); e.accepted = true;
            } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                bt.cycleTab(-1); e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (bt.tabIndex === 0) bt.togglePrimary();
                else if (bt.tabIndex === 1) bt.toggleSecondary();
                else bt.activateDevice(bt.selectedIndex);
                e.accepted = true;
            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? 2 :
                    (bt.selectedIndex + 1 < n ? bt.tabIndex + 1 : 2);
                e.accepted = true;
            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                // From the toggle row (tabIndex 0/1), Up wraps to the LAST
                // list item rather than diving into the first one.
                if (n > 0) bt.tabIndex = bt.tabIndex < 2 ? (1 + n) :
                    (bt.selectedIndex > 0 ? bt.tabIndex - 1 : 1 + n);
                e.accepted = true;
            } else if (e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) {
                bt.forgetDevice(bt.selectedIndex); e.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.md

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
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }

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

            Text {
                visible: bt.powered
                text: "PAIRED DEVICES"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.letterSpacing: 1
                font.bold: true
            }

            Flickable {
                id: btFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: -8
                visible: bt.powered
                clip: true
                contentWidth: width
                contentHeight: btRowsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}
                ColumnLayout {
                    id: btRowsCol
                    width: btFlick.width
                    spacing: 2
                    Repeater {
                        id: btRepeater
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
                // Keep the keyboard-selected row scrolled into view.
                Connections {
                    target: bt
                    function onTabIndexChanged() { Qt.callLater(btFlick.ensureVisible) }
                }
                function ensureVisible() {
                    if (bt.selectedIndex < 0) return;
                    const it = btRepeater.itemAt(bt.selectedIndex);
                    if (!it) return;
                    const top = it.y, bot = top + it.height;
                    if (top < btFlick.contentY) btFlick.contentY = Math.max(0, top - 4);
                    else if (bot > btFlick.contentY + btFlick.height)
                        btFlick.contentY = Math.min(Math.max(0, btFlick.contentHeight - btFlick.height), bot - btFlick.height + 4);
                }
            }
            // Keep content top-aligned when the list is hidden.
            Item { Layout.fillHeight: true; visible: !bt.powered }

            Text {
                Layout.fillWidth: true
                text: "↑↓ move · ↵ select · del forget · esc close"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
