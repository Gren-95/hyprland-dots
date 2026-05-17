// Compact media chip: optional track title + prev / play-pause / next.
// Drives the active MPRIS player directly. Visibility bound to
// Settings.mediaKeysVisible.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: mk
    visible: Settings.mediaKeysVisible
    implicitHeight: 28
    // Width is the chip's natural size; the wrapper in shell.qml centers us.
    implicitWidth: chip.implicitWidth
    width: implicitWidth
    height: implicitHeight

    // All controllable players (Spotify, Firefox, mpv, …).
    // Guard both Mpris.players AND .values — the service can have the
    // outer object before values is populated, .filter() would crash.
    readonly property var controllable: {
        const list = (Mpris.players && Mpris.players.values) || [];
        return list.filter(p => p && p.canControl);
    }
    // -1 = auto (prefer Playing); otherwise the user has scrolled to pick one.
    property int selectedIdx: -1
    readonly property var player: {
        if (controllable.length === 0) return null;
        if (selectedIdx >= 0 && selectedIdx < controllable.length) return controllable[selectedIdx];
        for (const p of controllable) {
            if (p.playbackState === MprisPlaybackState.Playing) return p;
        }
        return controllable[0];
    }
    readonly property bool hasPlayer: player !== null
    readonly property bool hasMultiple: controllable.length > 1
    readonly property bool isPlaying: player && player.playbackState === MprisPlaybackState.Playing
    readonly property string trackTitle: {
        if (!player || !player.trackTitle) return "";
        const a = player.trackArtists && player.trackArtists.length ? player.trackArtists[0] : "";
        return a ? (player.trackTitle + "  ·  " + a) : player.trackTitle;
    }
    // Reset to auto-pick when the player list changes (a player gone away
    // shifts indices; better to fall back to "playing one" than show wrong).
    onControllableChanged: selectedIdx = -1

    function cyclePlayer(delta) {
        if (controllable.length <= 1) return;
        const curIdx = controllable.indexOf(player);
        selectedIdx = ((curIdx >= 0 ? curIdx : 0) + delta + controllable.length) % controllable.length;
    }

    // Single rounded pill wrapping everything so the cluster reads as one
    // widget, not three loose glyphs.
    Rectangle {
        id: chip
        anchors.fill: parent
        implicitWidth: chipRow.implicitWidth + 16
        radius: height / 2
        color: mk.isPlaying
            ? Qt.rgba(Theme.accent.blue.r, Theme.accent.blue.g, Theme.accent.blue.b, 0.10)
            : Theme.bgDeep
        border.color: mk.isPlaying ? Theme.accent.blue : Theme.borderSubtle
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        // Wheel anywhere on the chip cycles through players. Sits below
        // the buttons (z=-1) and doesn't take clicks so per-button MouseAreas
        // get their events first.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            z: -1
            onWheel: (e) => mk.cyclePlayer(e.angleDelta.y > 0 ? -1 : 1)
        }

        RowLayout {
            id: chipRow
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            spacing: 8

            // Player counter — inline at the start when multiple players exist.
            // Accent-colored so it reads as metadata, not part of the track text.
            Text {
                visible: mk.hasMultiple
                Layout.alignment: Qt.AlignVCenter
                text: (mk.controllable.indexOf(mk.player) + 1) + "/" + mk.controllable.length
                color: Theme.accent.purple
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: true
            }
            Rectangle {
                // Separator between count and title (only when both shown).
                visible: mk.hasMultiple && mk.trackTitle !== ""
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 3; implicitHeight: 3
                radius: 1.5
                color: Theme.mutedDeep
            }

            // Track title — only shown when there's metadata. Truncates so
            // the chip stays bounded.
            Text {
                Layout.maximumWidth: 260
                Layout.alignment: Qt.AlignVCenter
                visible: mk.trackTitle !== ""
                text: mk.trackTitle
                color: mk.isPlaying ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.bold: mk.isPlaying
                elide: Text.ElideRight
            }

            // Separator dot between title and controls.
            Rectangle {
                visible: mk.trackTitle !== ""
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 3; implicitHeight: 3
                radius: 1.5
                color: Theme.mutedDeep
            }

            MediaBtn {
                glyph: "󰒮"
                enabledLook: mk.hasPlayer && mk.player.canGoPrevious
                onClicked: if (mk.hasPlayer) mk.player.previous()
            }
            MediaBtn {
                glyph: mk.isPlaying ? "󰏤" : "󰐊"
                highlight: mk.isPlaying
                enabledLook: mk.hasPlayer && mk.player.canTogglePlaying
                onClicked: if (mk.hasPlayer) mk.player.togglePlaying()
            }
            MediaBtn {
                glyph: "󰒭"
                enabledLook: mk.hasPlayer && mk.player.canGoNext
                onClicked: if (mk.hasPlayer) mk.player.next()
            }
        }
    }

    // Inline icon button — circular hover surface, scales on press.
    component MediaBtn: Item {
        id: btn
        property string glyph: ""
        property bool highlight: false
        property bool enabledLook: true
        signal clicked()

        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 22
        implicitHeight: 22

        Rectangle {
            anchors.centerIn: parent
            width: 22
            height: 22
            radius: 11
            color: btn.highlight ? Theme.accent.blue
                : (hover.containsMouse ? Theme.bgHover : "transparent")
            opacity: btn.enabledLook ? 1.0 : 0.35
            // Scale down briefly on press for a tactile feel.
            scale: hover.pressed ? 0.92 : 1.0
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

            Text {
                anchors.centerIn: parent
                text: btn.glyph
                color: btn.highlight ? Theme.bg
                    : (hover.containsMouse ? Theme.fg : Theme.muted)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabledLook
            cursorShape: btn.enabledLook ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: btn.clicked()
        }
    }
}
