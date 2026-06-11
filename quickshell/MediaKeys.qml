// Compact media chip: optional track title + prev / play-pause / next.
// Drives the active MPRIS player directly. Visibility bound to
// Settings.mediaKeysVisible.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris

Item {
    id: mk
    property var parentBar: null
    property bool playerOpen: false
    property real curPos: 0
    function fmtTime(s) {
        s = Math.max(0, Math.floor(s));
        const m = Math.floor(s / 60);
        const ss = s % 60;
        return m + ":" + (ss < 10 ? "0" : "") + ss;
    }
    // Some players expose trackArtists as a string, not a list — coerce safely.
    function artistText() {
        if (!mk.player) return "";
        const a = mk.player.trackArtists;
        if (typeof a === "string") return a;
        if (a && a.length > 0) { try { return a.join(", "); } catch (e) { return String(a[0]); } }
        return mk.player.trackArtist || "";
    }
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
        const a = mk.artistText();
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

        // Wheel anywhere on the chip cycles through players; left-click opens
        // the full now-playing popup. Sits below the buttons (z=-1) so the
        // per-button MouseAreas get their clicks first.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            z: -1
            cursorShape: Qt.PointingHandCursor
            onClicked: mk.playerOpen = !mk.playerOpen
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

    // Full now-playing popup: album art, title/artist, seek bar, transport.
    PopupWindow {
        id: playerPopup
        visible: mk.playerOpen && mk.hasPlayer
        color: "transparent"
        anchor.window: mk.parentBar
        anchor.item: mk
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        implicitWidth: 280
        implicitHeight: playerCard.implicitHeight

        HyprlandFocusGrab {
            active: playerPopup.visible
            windows: [playerPopup]
            onCleared: mk.playerOpen = false
        }

        // Refresh the playback position while open and playing.
        Timer {
            running: mk.playerOpen && mk.isPlaying
            interval: 1000
            repeat: true
            triggeredOnStart: true
            onTriggered: mk.curPos = mk.player ? mk.player.position : 0
        }
        Connections {
            target: mk
            function onPlayerChanged() { mk.curPos = mk.player ? mk.player.position : 0 }
        }

        Rectangle {
            id: playerCard
            width: parent.width
            implicitHeight: playerCol.implicitHeight + 2 * Theme.spacing.lg
            radius: Theme.radius.lg
            color: Theme.bgAlt
            border.color: Theme.borderStrong
            border.width: 1
            scale: mk.playerOpen ? 1.0 : 0.96
            opacity: mk.playerOpen ? 1.0 : 0.0
            transformOrigin: Item.Top
            Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

            ColumnLayout {
                id: playerCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                // Album art (square; falls back to a note glyph).
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 180
                    Layout.preferredHeight: 180
                    radius: Theme.radius.lg
                    color: Theme.bgDeep
                    clip: true
                    Image {
                        id: art
                        anchors.fill: parent
                        source: mk.player && mk.player.trackArtUrl ? mk.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        visible: source != "" && status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !art.visible
                        text: "󰝚"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: 72
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: mk.player && mk.player.trackTitle ? mk.player.trackTitle : "Nothing playing"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        if (!mk.player) return "";
                        const a = mk.player.trackArtists;   // referenced so the binding tracks changes
                        if (typeof a === "string") return a;
                        if (a && a.length > 0) { try { return a.join(", "); } catch (e) { return String(a[0]); } }
                        return mk.player.trackArtist || "";
                    }
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                }

                // Seek bar + time labels.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 2
                    visible: mk.player && mk.player.lengthSupported && mk.player.length > 0
                    Item {
                        id: seek
                        Layout.fillWidth: true
                        implicitHeight: 14
                        property bool dragging: false
                        property real dragFrac: 0
                        property real frac: dragging ? dragFrac
                            : (mk.player && mk.player.length > 0
                                ? Math.max(0, Math.min(1, mk.curPos / mk.player.length)) : 0)
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 5
                            radius: 2.5
                            color: Theme.bgDeep
                            border.color: Theme.borderStrong
                            border.width: 1
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(0, parent.width * seek.frac)
                                height: 5
                                radius: 2.5
                                color: Theme.accent.blue
                            }
                        }
                        Rectangle {
                            width: 12
                            height: 12
                            radius: 6
                            color: Theme.fg
                            border.color: Theme.accent.blue
                            border.width: 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: Math.max(0, Math.min(parent.width - width, seek.frac * parent.width - width / 2))
                            visible: seekMa.containsMouse || seekMa.pressed
                        }
                        MouseArea {
                            id: seekMa
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            preventStealing: true
                            enabled: mk.player && mk.player.canSeek
                            cursorShape: Qt.PointingHandCursor
                            onPressed: (e) => { seek.dragging = true; seek.dragFrac = Math.max(0, Math.min(1, (e.x + 6) / seek.width)); }
                            onPositionChanged: (e) => { if (pressed) seek.dragFrac = Math.max(0, Math.min(1, (e.x + 6) / seek.width)); }
                            onReleased: {
                                if (mk.player && mk.player.length > 0) {
                                    mk.player.position = seek.dragFrac * mk.player.length;
                                    mk.curPos = seek.dragFrac * mk.player.length;
                                }
                                seek.dragging = false;
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: mk.fmtTime(mk.curPos)
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: mk.fmtTime(mk.player ? mk.player.length : 0)
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                        }
                    }
                }

                // Transport controls.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    spacing: Theme.spacing.xl
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
