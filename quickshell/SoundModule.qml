// Sound popup: an output card and an input card, each with a mute button, a
// volume slider and a device list that only reveals from a dropdown. Owns the
// bar speaker icon. Power lives in PowerModule.
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
    // Device lists only exist on screen while their dropdown is open, so
    // the keyboard cursor skips them while closed.
    property bool outExpanded: false
    property bool inExpanded: false
    readonly property var sndStops: {
        const s = [0];
        if (outExpanded) for (let i = 1; i <= outCount; i++) s.push(i);
        s.push(outCount + 1);
        if (inExpanded) for (let i = 0; i < inCount; i++) s.push(outCount + 2 + i);
        return s;
    }
    // Up/Down move the cursor through the visible stops, wrapping around.
    function moveSound(delta) {
        const stops = sndStops;
        const at = Math.max(0, stops.indexOf(sndIndex));
        sndIndex = stops[(at + delta + stops.length) % stops.length];
    }
    // Open or close the device dropdown of the section holding the cursor.
    function toggleExpand() {
        if (sndIndex <= outCount) {
            outExpanded = !outExpanded;
            if (!outExpanded && sndIndex > 0) sndIndex = 0;
        } else {
            inExpanded = !inExpanded;
            if (!inExpanded && sndIndex > outCount + 1) sndIndex = outCount + 1;
        }
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
    onPopupOpenChanged: if (popupOpen) {
        outExpanded = false;
        inExpanded = false;
        sndIndex = 0;
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
            ap.sink.audio.volume = Math.max(0, Math.min(1,
                ap.sink.audio.volume + (e.angleDelta.y > 0 ? 1 : -1) * settingsStore.volumeStep / 100));
        }
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
        anchorItem: ap._openAnchor ?? ap.flyoutAnchor ?? ap
        open: ap.popupOpen
        cardWidth: settingsStore.flyoutSize("audiopower", "w", 420)
        cardHeight: settingsStore.flyoutSize("audiopower", "h", 440)
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
            } else if (e.key === Qt.Key_D || e.key === Qt.Key_Space) {
                ap.toggleExpand(); e.accepted = true;
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
            anchors.fill: parent
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.md

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
                    font.pixelSize: Theme.fontSize.md
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
                clip: true
                contentWidth: width
                contentHeight: col.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar {}

                ColumnLayout {
                    id: col
                    width: flick.width - Theme.spacing.md
                    spacing: Theme.spacing.md

                    AudioSection {
                        Layout.fillWidth: true
                        title: "OUTPUT"
                        node: ap.sink
                        isSink: true
                        expanded: ap.outExpanded
                        selectedIndex: ap.outSelectedIndex
                        toggleHighlighted: ap.sndIndex === 0
                        sliderActive: ap.sndIndex <= ap.outCount
                        onExpandToggled: ap.outExpanded = !ap.outExpanded
                        onDeviceHovered: (idx) => ap.sndIndex = idx + 1
                        onToggleHovered: ap.sndIndex = 0
                    }
                    AudioSection {
                        Layout.fillWidth: true
                        title: "INPUT"
                        node: ap.source
                        isSink: false
                        expanded: ap.inExpanded
                        selectedIndex: ap.inSelectedIndex
                        toggleHighlighted: ap.sndIndex === ap.outCount + 1
                        sliderActive: ap.sndIndex >= ap.outCount + 1
                        onExpandToggled: ap.inExpanded = !ap.inExpanded
                        onDeviceHovered: (idx) => ap.sndIndex = ap.outCount + 2 + idx
                        onToggleHovered: ap.sndIndex = ap.outCount + 1
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "↑↓ move · ←→ adjust · D devices · M mute · ↵ select"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
            }
        }
    }
}
