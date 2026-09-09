// Wallpaper deck — the wallpaper chooser, on Super+W.
//
// Same shape as the workspace overview: hold Super to keep the deck up, tap W
// to turn over the next card (Shift+W to deal back), release Super to apply
// whatever is on top. The deal order is a shuffle, so W walks the whole
// collection without repeats rather than stepping through it alphabetically.
//
// Commit-on-release comes from SuperWatch, which polls the real key state —
// see that file for why the compositor cannot tell us.
//
// Owns the whole job: listing $wallpaperDir, the shuffle, and handing the
// chosen file to scripts/wallpaper.sh.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool open: false

    // Every image under the wallpaper dir, sorted; the deck deals from these.
    property var wallpapers: []
    function refresh() { if (!listProc.running) listProc.running = true }

    Process {
        id: listProc
        command: ["sh", "-c",
            "find " + settingsStore.wallpaperDir + " -type f \\( " +
            "-iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' \\) | sort"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpapers = text.trim().split("\n").filter(s => s.length > 0);
            }
        }
    }

    // Detached: wallpaper.sh outlives the call, and nothing here waits on it.
    Process { id: setProc; command: [] }
    function _apply(path) {
        setProc.command = ["bash", Quickshell.env("HOME") + "/.config/scripts/wallpaper.sh", path];
        setProc.startDetached();
        accentService.refreshSoon();   // re-extract the auto accent
    }

    // Shuffled positions into wallpapers, dealt in order — a real
    // shuffle, so nothing repeats until the deck runs out.
    property var order: []
    property int pos: 0

    readonly property var files: root.wallpapers
    // Offset is signed: the fan shows cards either side of the one in hand.
    function _at(offset) {
        const n = root.order.length;
        if (n === 0) return "";
        return root.files[root.order[((root.pos + offset) % n + n) % n]] || "";
    }
    readonly property string topFile: root._at(0)

    // Cards drawn either side of the selected one. Seven reads as a hand
    // without the outermost cards leaving the screen on a narrow monitor.
    readonly property int fanSpread: 3
    readonly property int cardW: 260
    readonly property int cardH: 364
    // How far below the cards the fan pivots — the hand holding them, off the
    // bottom of the screen. Larger means a shallower arc.
    readonly property int pivotDrop: 520
    readonly property real fanAngle: 11    // degrees between neighbouring cards

    function _reshuffle() {
        const idx = [];
        for (let i = 0; i < root.files.length; i++) idx.push(i);
        for (let i = idx.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = idx[i]; idx[i] = idx[j]; idx[j] = t;
        }
        root.order = idx;
        root.pos = 0;
    }

    // ===== Driven entirely by global shortcuts: W deals, Super release or
    // Enter/Space commits, Escape cancels. Nothing is read from a focused
    // surface — the deck never takes focus. =====
    // Every W press while Super is down. The first one opens the deck on a
    // fresh shuffle; the rest turn over the next card.
    function step() {
        if (root.files.length === 0) return;
        superWatch.poke();
        if (!root.open) {
            root._reshuffle();
            root.open = true;
            // Re-list in the background while this deck is up, so wallpapers
            // added since the last deal show up in the next one.
            root.refresh();
            return;
        }
        root.pos = (root.pos + 1) % root.order.length;
    }
    // The other direction. Overshooting a card you liked is the obvious way to
    // lose it, and taking it back before you let go beats applying the wrong
    // one and reverting afterwards. A no-op with the deck closed — this is a
    // browse control, not a way in.
    function stepBack() {
        if (!root.open || root.order.length === 0) return;
        superWatch.poke();
        const n = root.order.length;
        root.pos = (root.pos - 1 + n) % n;
    }
    // Super came up. Same entry point WorkspaceOverview uses, and a no-op
    // unless the deck is actually showing.
    function commitIfOpen() {
        if (!root.open) return;
        root.open = false;
        // Read the position directly rather than through the topFile binding.
        // In a change handler that binding can still hold the previous card,
        // and which file lands on the desktop should not depend on binding
        // evaluation order.
        const pick = root._at(0);
        if (pick !== "") root._apply(pick);
    }
    function close() { root.open = false; }

    // Super coming back up is what applies the card in hand; SuperWatch is
    // what notices. commitIfOpen no-ops when the deck is closed, so it does
    // not matter that the overview hears the same signal.
    Connections {
        target: superWatch
        function onReleased() { root.commitIfOpen() }
    }

    // Built once at startup so the very first Super+W of a session already
    // has a card to turn over.
    Component.onCompleted: root.refresh()

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // Only the monitor with focus — a hand of cards is held in front
            // of you, not mirrored onto every screen.
            readonly property bool onActiveMonitor: Hyprland.focusedMonitor
                && Hyprland.focusedMonitor.name === modelData.name
            visible: root.open && onActiveMonitor
            color: "transparent"

            // A strip along the bottom edge: the fan rises out of it, pivoting
            // from a point below the screen.
            anchors { bottom: true; left: true; right: true }
            implicitHeight: 500
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Never takes focus. An exclusive grab here stopped the
            // compositor's Super-release bind from firing for the cycle that
            // opened the deck, which meant Super had to be pressed a second
            // time to apply. Every key the deck responds to is a global
            // shortcut instead — see shell.qml.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: emptyRegion
            Region { id: emptyRegion }

            // Shadow under the hand rather than a full-screen scrim: the fan
            // only occupies the bottom of the screen, so only the bottom needs
            // darkening to lift the cards off the wallpaper.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#00000000" }
                    GradientStop { position: 0.55; color: "#66000000" }
                    GradientStop { position: 1.0;  color: "#cc000000" }
                }
            }

            Item {
                id: fan
                anchors.fill: parent
                opacity: root.open ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }

                Repeater {
                    // Outermost cards first so the middle of the hand paints
                    // over them, leaving the card in play fully visible.
                    model: 2 * root.fanSpread + 1
                    delegate: DeckCard {
                        required property int index
                        // -3 … 0 … +3, 0 being the card that gets applied.
                        readonly property int slot: index - root.fanSpread
                        readonly property int dist: Math.abs(slot)
                        readonly property bool inHand: slot === 0

                        file: root._at(slot)
                        highlighted: inHand

                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        // Bottom edge sits below the screen, as if the cards
                        // carried on into a hand.
                        // Cut off by the bottom edge the way a hand cuts off
                        // the cards it is holding, the played one least of all.
                        anchors.bottomMargin: inHand ? -14 : -36

                        opacity: 1.0 - dist * 0.13
                        z: root.fanSpread - dist
                        scale: inHand ? 1.06 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

                        // Rotating about a point well below the card fans the
                        // hand along an arc — the sideways spread falls out of
                        // the rotation instead of being positioned by hand.
                        transform: Rotation {
                            origin.x: root.cardW / 2
                            origin.y: root.cardH + root.pivotDrop
                            angle: slot * root.fanAngle
                        }
                    }
                }
            }

            // Name and keys ride above the fan rather than on the card: the
            // card in hand is clipped by the screen edge, and a label down
            // there would be half off it.
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: Theme.spacing.md
                spacing: Theme.spacing.sm
                opacity: fan.opacity

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: name.implicitWidth + 32
                    implicitHeight: 34
                    radius: 17 * Theme.radiusScale
                    color: Theme.bgDeep
                    border.color: Theme.accentPrimary
                    border.width: 1
                    Text {
                        id: name
                        anchors.centerIn: parent
                        text: root.topFile.split("/").pop()
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: hint.implicitWidth + 28
                    implicitHeight: 26
                    radius: 13 * Theme.radiusScale
                    color: Theme.bgDeep
                    border.color: Theme.borderStrong
                    border.width: 1
                    Text {
                        id: hint
                        anchors.centerIn: parent
                        text: "W  next    ·    ⇧W  back    ·    ↵  apply    ·    Esc  cancel"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        font.letterSpacing: 1
                    }
                }
            }
        }
    }

    component DeckCard: Rectangle {
        id: dc
        property string file: ""
        property bool highlighted: false
        implicitWidth: root.cardW
        implicitHeight: root.cardH
        width: implicitWidth
        height: implicitHeight
        radius: 12 * Theme.radiusScale
        // A playing card's white border, so the fan reads as cards rather
        // than as floating thumbnails.
        color: dc.highlighted ? Theme.fg : Theme.fgMuted
        border.color: dc.highlighted ? Theme.accentPrimary : Theme.mutedDeep
        border.width: dc.highlighted ? 3 : 1
        antialiasing: true
        Behavior on color        { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        Image {
            anchors.fill: parent
            anchors.margins: 7
            source: dc.file !== "" ? "file://" + dc.file : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            // Portrait crop of a landscape wallpaper, so the thumbnail is
            // sampled tall rather than squashed.
            sourceSize.width: 520
            sourceSize.height: 728
        }

    }
}
