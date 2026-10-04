// MediaCard.qml — MPRIS "now playing" card for the day panel.
// Self-contained: drives the active MPRIS player (prev / play-pause / next,
// scrub, cycle between players). Shown whenever something is playing and
// absent from the layout when nothing is — no toggle, since an empty card
// costs nothing and a hidden one is just a missing control.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris

DayCard {
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

    title: "Now playing"
    visible: hasPlayer

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

    // Wheel cycles between players.
    WheelHandler {
        onWheel: (e) => media.cyclePlayer(e.angleDelta.y > 0 ? -1 : 1)
    }

    headerData: Text {
        visible: media.hasMultiple
        text: (media.controllable.indexOf(media.player) + 1) + "/" + media.controllable.length
        color: Theme.accent.purple
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.bold: true
    }

    // ----- Art + track -----
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacing.xl

        // Album art (square; falls back to a note glyph).
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 72
            Layout.preferredHeight: 72
            radius: Theme.radius.md
            // Accent-tinted when falling back to the glyph so there's always
            // a clearly visible icon, even when the player exposes no art.
            color: art.visible ? Theme.bgInset
                : Theme.alpha(Theme.accentPrimary, 0.15)
            border.color: Theme.borderSubtle
            border.width: 1
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
                font.pixelSize: Theme.fontSize.hero
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Text {
                Layout.fillWidth: true
                text: media.player && media.player.trackTitle ? media.player.trackTitle : "Nothing playing"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: media.artistText()
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
            }
        }
    }

    // ----- Scrub bar (only when the player reports a length) -----
    RowLayout {
        Layout.fillWidth: true
        visible: media.player && media.player.lengthSupported && media.player.length > 0
        spacing: Theme.spacing.md

        Text {
            Layout.preferredWidth: 40
            text: media.fmtTime(seek.frac * (media.player ? media.player.length : 0))
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
        Item {
            id: seek
            Layout.fillWidth: true
            implicitHeight: 24
            property bool dragging: false
            property real dragFrac: 0
            readonly property real frac: dragging ? dragFrac
                : (media.player && media.player.length > 0
                    ? Math.max(0, Math.min(1, media.curPos / media.player.length)) : 0)
            // Glides between the once-a-second position ticks; follows the
            // pointer directly while scrubbing.
            property real shownFrac: frac
            Behavior on shownFrac {
                enabled: !seek.dragging
                NumberAnimation {
                    duration: media.isPlaying ? Math.round(1000 * Theme.animScale) : Theme.duration.normal
                    easing.type: media.isPlaying ? Easing.Linear : Theme.easing.standard
                }
            }
            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: seekMa.containsMouse || seek.dragging ? 8 : 6
                radius: height / 2
                color: Theme.bgInset
                border.color: Theme.borderSubtle
                border.width: 1
                Behavior on height { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width * seek.shownFrac)
                    height: parent.height
                    radius: height / 2
                    color: Theme.accentPrimary
                }
                Rectangle {
                    x: Math.max(0, Math.min(parent.width, parent.width * seek.shownFrac)) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: Theme.fg
                    opacity: seekMa.containsMouse || seek.dragging ? 1.0 : 0.0
                    scale: seek.dragging ? 1.15 : 1.0
                    Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                }
            }
            MouseArea {
                id: seekMa
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                enabled: media.player && media.player.canSeek
                cursorShape: Qt.PointingHandCursor
                onPressed: (e) => { seek.dragging = true; seek.dragFrac = Math.max(0, Math.min(1, e.x / seek.width)); }
                onPositionChanged: (e) => { if (pressed) seek.dragFrac = Math.max(0, Math.min(1, e.x / seek.width)); }
                onReleased: {
                    if (media.player && media.player.length > 0) {
                        media.player.position = seek.dragFrac * media.player.length;
                        media.curPos = seek.dragFrac * media.player.length;
                    }
                    seek.dragging = false;
                }
            }
        }
        Text {
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
            text: media.fmtTime(media.player ? media.player.length : 0)
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
    }

    // ----- Transport controls -----
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: Theme.spacing.xl
        MediaBtn {
            glyph: "󰒮"
            enabledLook: media.hasPlayer && media.player.canGoPrevious
            onClicked: if (media.hasPlayer) media.player.previous()
        }
        MediaBtn {
            glyph: media.isPlaying ? "󰏤" : "󰐊"
            highlight: true
            size: 48
            enabledLook: media.hasPlayer && media.player.canTogglePlaying
            onClicked: if (media.hasPlayer) media.player.togglePlaying()
        }
        MediaBtn {
            glyph: "󰒭"
            enabledLook: media.hasPlayer && media.player.canGoNext
            onClicked: if (media.hasPlayer) media.player.next()
        }
    }

    // Round transport button: hover wash, press squash. `highlight` fills it
    // with the accent (the play/pause button).
    component MediaBtn: Item {
        id: btn
        property string glyph: ""
        property bool highlight: false
        property bool enabledLook: true
        property int size: 40
        signal clicked()

        implicitWidth: size
        implicitHeight: size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: btn.highlight ? (hover.containsMouse ? Qt.lighter(Theme.accentPrimary, 1.12) : Theme.accentPrimary)
                : (hover.containsMouse ? Theme.bgActive : Theme.bgInset)
            border.color: btn.highlight ? "transparent" : (hover.containsMouse ? Theme.borderStrong : Theme.borderSubtle)
            border.width: 1
            opacity: btn.enabledLook ? 1.0 : 0.35
            scale: hover.pressed ? 0.92 : 1.0
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
            Text {
                anchors.centerIn: parent
                text: btn.glyph
                color: btn.highlight ? Theme.fgOnAccent
                    : (hover.containsMouse ? Theme.fg : Theme.fgMuted)
                font.family: Theme.font
                font.pixelSize: btn.highlight ? Theme.fontSize.xxl : Theme.fontSize.xl
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
