// MediaCard.qml — MPRIS "now playing" card for the notification panel.
// Self-contained: drives the active MPRIS player (prev / play-pause / next,
// scrub, cycle between players). Collapses to zero height when nothing is
// playing. Gated by settingsStore.mediaKeysVisible so the Quick Actions
// "Media keys" toggle still shows/hides it — just in the panel now, not the bar.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

Item {
    id: media
    property real curPos: 0
    // -1 = auto (prefer Playing); otherwise the user scrolled to pick one.
    property int selectedIdx: -1

    function fmtTime(s) {
        s = Math.max(0, Math.floor(s));
        const m = Math.floor(s / 60);
        const ss = s % 60;
        return m + ":" + (ss < 10 ? "0" : "") + ss;
    }
    // Some players expose trackArtists as a string, not a list — coerce safely.
    function artistText() {
        if (!media.player) return "";
        const a = media.player.trackArtists;
        if (typeof a === "string") return a;
        if (a && a.length > 0) { try { return a.join(", "); } catch (e) { return String(a[0]); } }
        return media.player.trackArtist || "";
    }

    // All controllable players (Spotify, Firefox, mpv, …). Guard both
    // Mpris.players AND .values — the service can have the outer object before
    // values is populated, .filter() would crash.
    readonly property var controllable: {
        const list = (Mpris.players && Mpris.players.values) || [];
        return list.filter(p => p && p.canControl);
    }
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

    onControllableChanged: selectedIdx = -1
    function cyclePlayer(delta) {
        if (controllable.length <= 1) return;
        const curIdx = controllable.indexOf(player);
        selectedIdx = ((curIdx >= 0 ? curIdx : 0) + delta + controllable.length) % controllable.length;
    }

    visible: hasPlayer && settingsStore.mediaKeysVisible
    implicitHeight: visible ? card.implicitHeight : 0
    clip: true

    // Keep the scrub position fresh while visible and playing.
    Timer {
        running: media.visible && media.isPlaying
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: media.curPos = media.player ? media.player.position : 0
    }
    Connections {
        target: media
        function onPlayerChanged() { media.curPos = media.player ? media.player.position : 0 }
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: cardRow.implicitHeight + 2 * Theme.spacing.md
        radius: Theme.radius.lg
        color: Theme.bgDeep
        border.color: media.isPlaying ? Theme.accentPrimary : Theme.borderSubtle
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        // Wheel cycles between players.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: (e) => media.cyclePlayer(e.angleDelta.y > 0 ? -1 : 1)
        }

        RowLayout {
            id: cardRow
            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.md

            // Album art (square; falls back to a note glyph).
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                radius: Theme.radius.md
                // Accent-tinted when falling back to the glyph so there's always
                // a clearly visible icon, even when the player exposes no art.
                color: art.visible ? Theme.bg
                    : Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.15)
                clip: true
                Image {
                    id: art
                    anchors.fill: parent
                    source: media.player && media.player.trackArtUrl ? media.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    visible: source != "" && status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !art.visible
                    text: media.isPlaying ? "󰎈" : "󰝚"
                    color: Theme.accentPrimary
                    font.family: Theme.font
                    font.pixelSize: 28
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                // Title + optional player counter.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.sm
                    Text {
                        Layout.fillWidth: true
                        text: media.player && media.player.trackTitle ? media.player.trackTitle : "Nothing playing"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: media.hasMultiple
                        text: (media.controllable.indexOf(media.player) + 1) + "/" + media.controllable.length
                        color: Theme.accent.purple
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: media.artistText()
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    elide: Text.ElideRight
                }

                // Thin scrub bar (only when the player reports a length).
                Item {
                    id: seek
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 12
                    visible: media.player && media.player.lengthSupported && media.player.length > 0
                    property bool dragging: false
                    property real dragFrac: 0
                    property real frac: dragging ? dragFrac
                        : (media.player && media.player.length > 0
                            ? Math.max(0, Math.min(1, media.curPos / media.player.length)) : 0)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2 * Theme.radiusScale
                        color: Theme.bg
                        Rectangle {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width * seek.frac)
                            height: 4
                            radius: 2 * Theme.radiusScale
                            color: Theme.accentPrimary
                        }
                    }
                    MouseArea {
                        id: seekMa
                        anchors.fill: parent
                        anchors.margins: -6
                        preventStealing: true
                        enabled: media.player && media.player.canSeek
                        cursorShape: Qt.PointingHandCursor
                        onPressed: (e) => { seek.dragging = true; seek.dragFrac = Math.max(0, Math.min(1, (e.x + 6) / seek.width)); }
                        onPositionChanged: (e) => { if (pressed) seek.dragFrac = Math.max(0, Math.min(1, (e.x + 6) / seek.width)); }
                        onReleased: {
                            if (media.player && media.player.length > 0) {
                                media.player.position = seek.dragFrac * media.player.length;
                                media.curPos = seek.dragFrac * media.player.length;
                            }
                            seek.dragging = false;
                        }
                    }
                }
            }

            // Transport controls.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.spacing.sm
                MediaBtn {
                    glyph: "󰒮"
                    enabledLook: media.hasPlayer && media.player.canGoPrevious
                    onClicked: if (media.hasPlayer) media.player.previous()
                }
                MediaBtn {
                    glyph: media.isPlaying ? "󰏤" : "󰐊"
                    highlight: media.isPlaying
                    enabledLook: media.hasPlayer && media.player.canTogglePlaying
                    onClicked: if (media.hasPlayer) media.player.togglePlaying()
                }
                MediaBtn {
                    glyph: "󰒭"
                    enabledLook: media.hasPlayer && media.player.canGoNext
                    onClicked: if (media.hasPlayer) media.player.next()
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

        implicitWidth: 26
        implicitHeight: 26

        Rectangle {
            anchors.centerIn: parent
            width: 26
            height: 26
            radius: 13 * Theme.radiusScale
            color: btn.highlight ? Theme.accentPrimary
                : (hover.containsMouse ? Theme.bgHover : "transparent")
            opacity: btn.enabledLook ? 1.0 : 0.35
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
