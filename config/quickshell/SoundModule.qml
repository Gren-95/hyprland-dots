// Sound popup: an output card and an input card, each with a mute button, a
// volume slider and a device list that only reveals from a dropdown, plus a
// per-app mixer card while anything is playing. Owns the bar speaker icon.
// Power lives in PowerModule.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Pipewire

Item {
    id: ap
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Default flyout anchor (placement-aware, bound from shell.qml) and a
    // per-open override set by toggleOpen(from). Fallback: own icon.
    property Item flyoutAnchor: null
    property Item _openAnchor: null
    signal navigateNext()
    signal navigatePrev()

    // ===== Sound state =====
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var outputDevices: {
        if (!Pipewire.nodes) return [];
        return (Pipewire.nodes.values || []).filter(n => n.isSink && !n.isStream && n.audio);
    }
    readonly property var inputDevices: {
        if (!Pipewire.nodes) return [];
        return (Pipewire.nodes.values || []).filter(n => !n.isSink && !n.isStream && n.audio);
    }
    // App playback streams (devices are not streams; capture streams are not
    // sinks). Their volume and mute state are only bound while tracked.
    readonly property var appStreams: {
        if (!Pipewire.nodes) return [];
        return (Pipewire.nodes.values || []).filter(n => n.isStream && n.isSink && n.audio);
    }
    PwObjectTracker { objects: ap.appStreams }

    // What kind of device a node is, from its PipeWire name: icon and label.
    function kindOf(n) {
        const id = n ? String(n.name || "") : "";
        if (id.indexOf("bluez") >= 0) return "bluetooth";
        if (/hdmi|displayport/i.test(id)) return "hdmi";
        if (id.indexOf("usb") >= 0) return "usb";
        return "builtin";
    }
    function kindGlyph(n, isSink) {
        switch (kindOf(n)) {
        case "bluetooth": return isSink ? "󰋋" : "󰋎";
        case "hdmi":      return "󰍹";
        default:          return isSink ? "󰓃" : "󰍬";
        }
    }
    function kindLabel(n) {
        switch (kindOf(n)) {
        case "bluetooth": return "Bluetooth";
        case "hdmi":      return "HDMI / DisplayPort";
        case "usb":       return "USB";
        default:          return "Built-in";
        }
    }
    function nodeName(n) { return n ? (n.nickname || n.description || n.name || "") : "No device"; }

    readonly property int outCount: outputDevices.length
    readonly property int inCount: inputDevices.length
    // Sound-tab navigation index (matches old SoundModule).
    property int sndIndex: 0
    readonly property int sndStopCount: outCount + inCount + 2
    readonly property int outSelectedIndex: sndIndex >= 1 && sndIndex <= outCount ? sndIndex - 1 : -1
    readonly property int inSelectedIndex: sndIndex >= outCount + 2 ? sndIndex - outCount - 2 : -1

    // The section the sound-tab cursor is currently in: output (sink) for
    // indices 0..outCount, input (source) beyond that. Left/Right adjust this
    // node's volume so the arrows feel the same as the Power tab's sliders.
    readonly property var sndActiveNode: sndIndex >= outCount + 1 ? source : sink
    function adjustVolume(delta) {
        const node = sndActiveNode;
        if (!node || !node.audio) return;
        node.audio.volume = Math.max(0, Math.min(settingsStore.maxVolume / 100, node.audio.volume + delta));
    }
    function toggleSndMute() {
        const node = sndActiveNode;
        if (node && node.audio) node.audio.muted = !node.audio.muted;
    }
    function activateOutput(i) {
        if (i < 0 || i >= outputDevices.length) return;
        Pipewire.preferredDefaultAudioSink = outputDevices[i];
    }
    function activateInput(i) {
        if (i < 0 || i >= inputDevices.length) return;
        Pipewire.preferredDefaultAudioSource = inputDevices[i];
    }
    function activateSndIndex() {
        if (sndIndex === 0) {
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
        } else if (sndIndex <= outCount) {
            activateOutput(sndIndex - 1);
        } else if (sndIndex === outCount + 1) {
            if (source && source.audio) source.audio.muted = !source.audio.muted;
        } else {
            activateInput(sndIndex - outCount - 2);
        }
    }
    // Keyboard stops, top to bottom in the order they appear: output volume
    // (0), output devices, input volume (outCount + 1), input devices. Both
    // device lists are always on screen, so every index is a stop.
    readonly property var sndStops: {
        const s = [];
        for (let i = 0; i < outCount + inCount + 2; i++) s.push(i);
        return s;
    }
    // Up/Down move the cursor through the stops, wrapping around.
    function moveSound(delta) {
        const stops = sndStops;
        const at = Math.max(0, stops.indexOf(sndIndex));
        sndIndex = stops[(at + delta + stops.length) % stops.length];
    }

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
        onTriggered: ap.lockedHeight = ap.fitHeight
    }

    // ===== Popup control =====
    // `from` (optional) re-anchors the flyout under the bar item that opened
    // it (overflow rows, Spotlight) so it appears where it was asked for.
    function toggleOpen(from) {
        _openAnchor = from ?? null;
        popupOpen = !popupOpen;
    }
    function openAt() {
        _openAnchor = null;   // ring hops open at the module's own anchor
        popupOpen = true;
    }
    onPopupOpenChanged: {
        lockedHeight = 0;
        if (popupOpen) {
            sndIndex = 0;
            lockTimer.restart();
        }
    }

    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 20

    BarHover { hovered: apHover.hovered; active: ap.popupOpen && (ap._openAnchor ?? ap.flyoutAnchor ?? ap) === ap }

    // ===== Bar speaker rendering (sound) =====
    PwObjectTracker { objects: [ap.sink, ap.source] }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            text: {
                if (!ap.sink || !ap.sink.audio) return "󰕾";
                if (ap.sink.audio.muted) return "󰖁";
                const v = ap.sink.audio.volume;
                if (v < 0.34) return "󰕿";
                if (v < 0.67) return "󰖀";
                return "󰕾";
            }
            color: ap.sink && ap.sink.audio && ap.sink.audio.muted ? Theme.mutedDeep : Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            text: {
                if (!ap.sink || !ap.sink.audio) return "";
                if (ap.sink.audio.muted) return "muted";
                return Math.round(ap.sink.audio.volume * 100) + "%";
            }
            color: ap.sink && ap.sink.audio && ap.sink.audio.muted ? Theme.mutedDeep : Theme.fg
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
                if (ap.sink && ap.sink.audio) ap.sink.audio.muted = !ap.sink.audio.muted;
                return;
            }
            ap.toggleOpen();
        }
        onWheel: (e) => {
            if (!ap.sink || !ap.sink.audio) return;
            ap.sink.audio.volume = Math.max(0, Math.min(settingsStore.maxVolume / 100,
                ap.sink.audio.volume + (e.angleDelta.y > 0 ? 1 : -1) * settingsStore.volumeStep / 100));
        }
    }


    component SectionLabel: Text {
        Layout.leftMargin: Theme.spacing.sm
        Layout.bottomMargin: 2
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.xs
        font.letterSpacing: 1
        font.bold: true
    }

    // ===== Popup =====
    HoverHandler { id: apHover }
    BarTooltip {
        bar: ap.parentBar
        target: ap
        text: "Sound · Super+S"
        active: apHover.hovered && !ap.popupOpen
    }

    BarFlyout {
        id: apPopup
        parentBar: ap.parentBar
        open: ap.popupOpen
        cardWidth: settingsStore.flyoutSize("audiopower", "w", 720)
        cardHeight: settingsStore.flyoutSize("audiopower", "h", ap.lockedHeight > 0 ? ap.lockedHeight : ap.fitHeight)
        pinned: ap.pinned
        onDismissed: ap.popupOpen = false
        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                ap.navigateNext(); e.accepted = true;
            } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                ap.navigatePrev(); e.accepted = true;
            } else if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                ap.moveSound(1); e.accepted = true;
            } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                ap.moveSound(-1); e.accepted = true;
            } else if (e.key === Qt.Key_Right || e.key === Qt.Key_L
                    || e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                ap.adjustVolume(settingsStore.volumeStep / 100); e.accepted = true;
            } else if (e.key === Qt.Key_Left || e.key === Qt.Key_H
                    || e.key === Qt.Key_Minus) {
                ap.adjustVolume(-settingsStore.volumeStep / 100); e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                ap.activateSndIndex(); e.accepted = true;
            } else if (e.key === Qt.Key_M) {
                ap.toggleSndMute(); e.accepted = true;
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
                    pinned: ap.pinned
                    onToggled: ap.pinned = !ap.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "Sound"
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

                RowLayout {
                    id: col
                    width: flick.width - Theme.spacing.md
                    spacing: Theme.spacing.lg

                    // ===== Left: devices, always listed =====
                    ColumnLayout {
                        Layout.preferredWidth: 236
                        Layout.maximumWidth: 236
                        Layout.alignment: Qt.AlignTop
                        spacing: 2

                        SectionLabel { text: "OUTPUT" }
                        Repeater {
                            model: ap.outputDevices
                            delegate: AudioDeviceRow {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                node: modelData
                                glyph: ap.kindGlyph(modelData, true)
                                kind: ap.kindLabel(modelData)
                                accent: Theme.accentPrimary
                                isActive: ap.sink === modelData
                                highlighted: ap.sndIndex === index + 1
                                onPicked: ap.activateOutput(index)
                                onHovered: ap.sndIndex = index + 1
                            }
                        }
                        SectionLabel { text: "INPUT"; Layout.topMargin: Theme.spacing.md }
                        Repeater {
                            model: ap.inputDevices
                            delegate: AudioDeviceRow {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                node: modelData
                                glyph: ap.kindGlyph(modelData, false)
                                kind: ap.kindLabel(modelData)
                                accent: Theme.accent.teal
                                isActive: ap.source === modelData
                                highlighted: ap.sndIndex === ap.outCount + 2 + index
                                onPicked: ap.activateInput(index)
                                onHovered: ap.sndIndex = ap.outCount + 2 + index
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: Theme.borderSubtle
                    }

                    // ===== Right: volumes =====
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: 2

                        SectionLabel { text: "VOLUME" }
                        VolumeLine {
                            Layout.fillWidth: true
                            label: "Output"
                            sublabel: ap.nodeName(ap.sink)
                            glyph: {
                                const v = ap.sink && ap.sink.audio ? ap.sink.audio.volume : 0;
                                return v < 0.34 ? "󰕿" : v < 0.67 ? "󰖀" : "󰕾";
                            }
                            volume: ap.sink && ap.sink.audio ? ap.sink.audio.volume : 0
                            muted: !!(ap.sink && ap.sink.audio && ap.sink.audio.muted)
                            accent: Theme.accentPrimary
                            highlighted: ap.sndIndex === 0
                            onMoved: (value) => { if (ap.sink && ap.sink.audio) ap.sink.audio.volume = value; }
                            onMuteToggled: { if (ap.sink && ap.sink.audio) ap.sink.audio.muted = !ap.sink.audio.muted; }
                            onHovered: ap.sndIndex = 0
                        }
                        VolumeLine {
                            Layout.fillWidth: true
                            label: "Input"
                            sublabel: ap.nodeName(ap.source)
                            glyph: "󰍬"
                            volume: ap.source && ap.source.audio ? ap.source.audio.volume : 0
                            muted: !!(ap.source && ap.source.audio && ap.source.audio.muted)
                            accent: Theme.accent.teal
                            highlighted: ap.sndIndex === ap.outCount + 1
                            onMoved: (value) => { if (ap.source && ap.source.audio) ap.source.audio.volume = value; }
                            onMuteToggled: { if (ap.source && ap.source.audio) ap.source.audio.muted = !ap.source.audio.muted; }
                            onHovered: ap.sndIndex = ap.outCount + 1
                        }

                        SectionLabel { text: "APPS"; Layout.topMargin: Theme.spacing.md }
                        // Per-app volumes; mouse only, not part of the keyboard cursor.
                        Repeater {
                            model: ap.appStreams
                            delegate: AudioAppRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                            }
                        }
                        Text {
                            visible: ap.appStreams.length === 0
                            Layout.leftMargin: Theme.spacing.sm
                            text: "Nothing is playing"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "↑↓ move · ←→ adjust · M mute · ↵ select device"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
