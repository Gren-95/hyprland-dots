import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

Item {
    id: snd
    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    // Tab layout:
    //   0                       : output mute toggle
    //   1..outCount             : output device i = tabIndex - 1
    //   outCount+1              : input mute toggle
    //   outCount+2..tabStopCount: input device i = tabIndex - outCount - 2
    property int tabIndex: 0
    signal navigateNext()
    signal navigatePrev()
    readonly property int outCount: outputDevices.length
    readonly property int inCount: inputDevices.length
    readonly property int tabStopCount: outCount + inCount + 2
    readonly property int outSelectedIndex: tabIndex >= 1 && tabIndex <= outCount ? tabIndex - 1 : -1
    readonly property int inSelectedIndex: tabIndex >= outCount + 2 ? tabIndex - outCount - 2 : -1
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
    Layout.fillHeight: true
    implicitWidth: row.implicitWidth + 16

    onPopupOpenChanged: if (popupOpen) {
        const idx = outputDevices.indexOf(sink);
        tabIndex = idx >= 0 ? idx + 1 : 0;
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
    function adjustVolume(delta) {
        if (!sink || !sink.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + delta));
    }
    function activateOutput(i) {
        if (i < 0 || i >= outputDevices.length) return;
        Pipewire.preferredDefaultAudioSink = outputDevices[i];
    }
    function activateInput(i) {
        if (i < 0 || i >= inputDevices.length) return;
        Pipewire.preferredDefaultAudioSource = inputDevices[i];
    }
    function activateTabIndex() {
        if (tabIndex === 0) {
            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
        } else if (tabIndex <= outCount) {
            activateOutput(tabIndex - 1);
        } else if (tabIndex === outCount + 1) {
            if (source && source.audio) source.audio.muted = !source.audio.muted;
        } else {
            activateInput(tabIndex - outCount - 2);
        }
    }

    PwObjectTracker { objects: [snd.sink, snd.source] }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacing.xs
        Text {
            text: {
                if (!snd.sink || !snd.sink.audio) return "󰕾";
                if (snd.sink.audio.muted) return "󰖁";
                const v = snd.sink.audio.volume;
                if (v < 0.34) return "󰕿";
                if (v < 0.67) return "󰖀";
                return "󰕾";
            }
            color: snd.sink && snd.sink.audio && snd.sink.audio.muted ? Theme.mutedDeep : "#f5f5f4"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        Text {
            text: {
                if (!snd.sink || !snd.sink.audio) return "";
                if (snd.sink.audio.muted) return "muted";
                return Math.round(snd.sink.audio.volume * 100) + "%";
            }
            color: snd.sink && snd.sink.audio && snd.sink.audio.muted ? Theme.mutedDeep : "#f5f5f4"
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
                if (snd.sink && snd.sink.audio) snd.sink.audio.muted = !snd.sink.audio.muted;
            } else {
                snd.popupOpen = !snd.popupOpen;
            }
        }
        onWheel: (e) => {
            if (!snd.sink || !snd.sink.audio) return;
            snd.sink.audio.volume = Math.max(0, Math.min(1,
                snd.sink.audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05)));
        }
    }

    PopupWindow {
        id: sndPopup
        anchor.window: snd.parentBar
        anchor.rect.x: (snd.parentBar.width - implicitWidth) / 2
        anchor.rect.y: (snd.parentBar.screen.height - implicitHeight) / 2
        implicitWidth: 320
        implicitHeight: sndCol.implicitHeight + 24
        visible: snd.popupOpen
        color: "transparent"

        SproutBg {
            anchors.fill: parent
            fillColor: Theme.bgAlt
            borderColor: Theme.mutedDeep
            showTail: false
        }
        Item {
            anchors.fill: parent
            focus: snd.popupOpen
            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) {
                    snd.popupOpen = false;
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    snd.navigateNext();
                    e.accepted = true;
                } else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    snd.navigatePrev();
                    e.accepted = true;
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Down || e.key === Qt.Key_J
                         || e.key === Qt.Key_Right || e.key === Qt.Key_L) {
                    snd.cycleTab(e.modifiers & Qt.ShiftModifier ? -1 : 1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K
                         || e.key === Qt.Key_Left || e.key === Qt.Key_H) {
                    snd.cycleTab(-1);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                    snd.activateTabIndex();
                    e.accepted = true;
                } else if (e.key === Qt.Key_M) {
                    if (snd.sink && snd.sink.audio) snd.sink.audio.muted = !snd.sink.audio.muted;
                    e.accepted = true;
                } else if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) {
                    snd.adjustVolume(0.05);
                    e.accepted = true;
                } else if (e.key === Qt.Key_Minus) {
                    snd.adjustVolume(-0.05);
                    e.accepted = true;
                }
            }

            ColumnLayout {
                id: sndCol
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: snd.pinned
                        onToggled: snd.pinned = !snd.pinned
                    }
                    Text {
                        text: "Sound"
                        color: "#f5f5f4"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                }

                AudioSection {
                    Layout.fillWidth: true
                    title: "󰕾  Output"
                    node: snd.sink
                    isSink: true
                    selectedIndex: snd.outSelectedIndex !== undefined ? snd.outSelectedIndex : -1
                    toggleHighlighted: snd.tabIndex === 0
                    onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                    onDeviceHovered: (idx) => snd.tabIndex = idx + 1
                    onToggleHovered: snd.tabIndex = 0
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderStrong }

                AudioSection {
                    Layout.fillWidth: true
                    title: "󰍬  Input"
                    node: snd.source
                    isSink: false
                    selectedIndex: snd.inSelectedIndex !== undefined ? snd.inSelectedIndex : -1
                    toggleHighlighted: snd.tabIndex === snd.outCount + 1
                    onLaunchMixer: { pavuProc.startDetached(); snd.popupOpen = false }
                    onDeviceHovered: (idx) => snd.tabIndex = snd.outCount + 2 + idx
                    onToggleHovered: snd.tabIndex = snd.outCount + 1
                }
            }
        }
    }

    Process { id: pavuProc; command: ["pavucontrol"] }

    HyprlandFocusGrab {
        active: snd.popupOpen && !snd.pinned
        windows: [sndPopup]
        onCleared: snd.popupOpen = false
    }
}
