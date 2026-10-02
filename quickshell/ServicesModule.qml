// Everything that runs in the background, in one place: the daemons restart.sh
// starts at login, the two scheduled syncs, and the services that are only up
// when asked for.
//
// The panel is a read-out first. Quick Actions already toggles the handful of
// these that are worth one click from the bar; what it cannot tell you is
// whether `dotwatch` actually survived the last session, or when the Jellyfin
// timer next fires. Every status comes from one probe — scripts/services-
// status.sh — so the QML never grows a shell pipeline in a string literal.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

Item {
    id: mod

    property var parentBar
    property bool popupOpen: false
    property bool pinned: false
    property Item flyoutAnchor: null

    // key → bool, rebuilt wholesale on every probe (mutating a JS object in
    // place would not re-evaluate the bindings that read it).
    property var st: ({})
    property int jfNext: 0
    // Set while a toggle script is in flight, so an in-progress row reads
    // "working" instead of flipping back on the next stale probe.
    property string busyKey: ""

    // ============ What we watch ============
    // `script` is what starts a stopped daemon; `action` names a toggle.
    readonly property var daemons: [
        { key: "battery-notify",     glyph: "󰁹", label: "Battery notify",   detail: "warns at 20% and 10%",            script: "battery-notify.sh" },
        { key: "power-auto",         glyph: "󰉁", label: "Power profile",    detail: "follows AC and battery level",    script: "power-auto.sh" },
        { key: "media-inhibit",      glyph: "󰅶", label: "Media inhibit",    detail: "no sleep while media plays",      script: "media-inhibit.sh" },
        { key: "fullscreen-inhibit", glyph: "󰊓", label: "Fullscreen inhibit", detail: "no idle while fullscreen",      script: "fullscreen-inhibit.sh" },
        { key: "dotwatch",           glyph: "󰼂", label: "Dotwatch",         detail: "hot-reloads edited dotfiles",     script: "dotwatch.sh" }
    ]
    readonly property var scheduled: [
        { key: "immich",   glyph: "󰋩", label: "Immich sync",   accent: Theme.accent.orange,         detail: "photos, hourly (cron)" },
        { key: "jellyfin", glyph: "󰝚", label: "Jellyfin sync", accent: Theme.accent.purple,         detail: "" }
    ]
    readonly property var onDemand: [
        { key: "wayvnc", glyph: "󰢹", label: "Remote access", accent: Theme.accent.orange, detail: "VNC on :5900" },
        { key: "winvm",  glyph: "󰖳", label: "Windows VM",    accent: Theme.accent.blue,   detail: "WinApps container" }
    ]

    // The four services that used to be Quick Actions toggles stay reachable
    // by name in the Spotlight palette — moving them out of that panel should
    // not make them harder to find.
    readonly property var spotlightActions: scheduled.concat(onDemand).map(e => ({
        name: e.label, glyph: e.glyph, accent: e.accent, keywords: e.key,
        isToggle: true,
        state: () => mod.up(e.key),
        run: () => mod.toggle(e.key)
    }))

    function up(key) { return st[key] === true }
    readonly property int daemonsDown: {
        let n = 0;
        for (const d of daemons) if (st[d.key] === false) n++;
        return n;
    }
    readonly property string jellyfinDetail: {
        if (!up("jellyfin")) return "music, daily (timer off)";
        if (jfNext <= 0) return "music, daily";
        return "music, daily · next " + Qt.formatDateTime(new Date(jfNext * 1000), "ddd HH:mm");
    }

    // ============ Bar icon ============
    Layout.fillHeight: true
    implicitWidth: 36

    BarHover { hovered: hov.hovered; active: mod.popupOpen }

    Text {
        anchors.centerIn: parent
        // Orange only for a daemon that should be up and isn't — the rest of
        // the panel's contents are opt-in, so their being off is not a fault.
        text: "󰓦"
        color: mod.popupOpen ? Theme.accent.blue
            : mod.daemonsDown > 0 ? Theme.accent.orange : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.md
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: mod.popupOpen = !mod.popupOpen
    }

    HoverHandler { id: hov }
    BarTooltip {
        bar: mod.parentBar
        target: mod
        text: mod.daemonsDown > 0
            ? mod.daemonsDown + " background service" + (mod.daemonsDown === 1 ? "" : "s") + " down"
            : "Background services"
        active: hov.hovered && !mod.popupOpen
    }

    // ============ Probe ============
    Process {
        id: probe
        command: ["bash", Paths.scripts + "/services-status.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "") return;
                const next = {};
                let jf = 0;
                for (const kv of text.trim().split(/\s+/)) {
                    const [k, v] = kv.split("=");
                    if (k === "jfnext") jf = parseInt(v, 10) || 0;
                    else if (k) next[k] = v === "1";
                }
                // A toggle in flight owns its key until reality agrees.
                if (mod.busyKey !== "" && next[mod.busyKey] === mod.st[mod.busyKey])
                    next[mod.busyKey] = mod.st[mod.busyKey];
                else if (mod.busyKey !== "")
                    mod.busyKey = "";
                mod.st = next;
                mod.jfNext = jf;
            }
        }
    }
    Timer {
        interval: mod.popupOpen ? 3000 : 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
    // Give a toggle a bounded amount of time to take effect.
    Timer {
        id: busyTimeout
        interval: 20000
        onTriggered: mod.busyKey = ""
    }

    Process { id: runProc; command: [] }

    function startDaemon(entry) {
        // Detached: a daemon parented to Quickshell would die with the next
        // shell reload, which is exactly the failure this panel reports.
        runProc.command = ["bash", Paths.scripts + "/" + entry.script];
        runProc.startDetached();
        mod.busyKey = entry.key;
        busyTimeout.restart();
        probeSoon.restart();
    }
    function toggle(key) {
        if (key === "immich" || key === "jellyfin")
            runProc.command = ["bash", Paths.scripts + "/sync-toggle.sh", "toggle", key];
        else if (key === "wayvnc")
            runProc.command = ["bash", Paths.scripts + "/wayvnc-toggle.sh"];
        else if (key === "winvm")
            runProc.command = ["bash", Paths.scripts + "/winvm-toggle.sh", "toggle"];
        else return;
        runProc.startDetached();
        mod.busyKey = key;
        busyTimeout.restart();
        probeSoon.restart();
    }
    Timer { id: probeSoon; interval: 1200; onTriggered: probe.running = true }

    // Popup height follows the content (up to what the screen allows), so
    // there is never empty space under the last row.
    readonly property real fitHeight: Math.min(
        parentBar && parentBar.screen ? parentBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)

    // ============ Panel ============
    BarFlyout {
        id: flyout
        parentBar: mod.parentBar
        anchorItem: mod.flyoutAnchor ?? mod
        open: mod.popupOpen
        pinned: mod.pinned
        cardWidth: settingsStore.flyoutSize("services", "w", 460)
        cardHeight: settingsStore.flyoutSize("services", "h", mod.fitHeight)
        onDismissed: mod.popupOpen = false

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: mod.pinned
                    onToggled: mod.pinned = !mod.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "Services"
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

                ColumnLayout {
                    id: col
                    width: flick.width - Theme.spacing.md
                    spacing: Theme.spacing.lg

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: daemonCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: daemonCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.md
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: "SESSION DAEMONS"
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                                Text {
                                    text: mod.daemonsDown > 0 ? mod.daemonsDown + " down" : "all up"
                                    color: mod.daemonsDown > 0 ? Theme.accent.orange : Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.bold: mod.daemonsDown > 0
                                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                                }
                            }
                            Repeater {
                                model: mod.daemons
                                delegate: ServiceRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    glyph: modelData.glyph
                                    label: modelData.label
                                    detail: mod.up(modelData.key) ? modelData.detail : "click to start · " + modelData.detail
                                    on: mod.up(modelData.key)
                                    busy: mod.busyKey === modelData.key
                                    accent: Theme.accent.green
                                    // A running daemon has nothing to do; only a dead one is
                                    // worth clicking.
                                    actionable: !mod.up(modelData.key)
                                    onActivated: mod.startDaemon(modelData)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: schedCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: schedCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.md
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: "SCHEDULED"
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                            }
                            Repeater {
                                model: mod.scheduled
                                delegate: ServiceRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    glyph: modelData.glyph
                                    label: modelData.label
                                    detail: modelData.key === "jellyfin" ? mod.jellyfinDetail : modelData.detail
                                    on: mod.up(modelData.key)
                                    busy: mod.busyKey === modelData.key
                                    accent: modelData.accent
                                    stateOn: "enabled"
                                    stateOff: "disabled"
                                    onActivated: mod.toggle(modelData.key)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: demandCol.implicitHeight + Theme.spacing.xl * 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        ColumnLayout {
                            id: demandCol
                            anchors.fill: parent
                            anchors.margins: Theme.spacing.xl
                            spacing: Theme.spacing.md
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: "ON DEMAND"
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.sm
                                    font.letterSpacing: 1
                                    font.bold: true
                                }
                            }
                            Repeater {
                                model: mod.onDemand
                                delegate: ServiceRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    glyph: modelData.glyph
                                    label: modelData.label
                                    detail: modelData.detail
                                    on: mod.up(modelData.key)
                                    busy: mod.busyKey === modelData.key
                                    accent: modelData.accent
                                    stateOn: "on"
                                    stateOff: "off"
                                    onActivated: mod.toggle(modelData.key)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
