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

    readonly property string scripts: Quickshell.env("HOME") + "/.config/scripts"

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
        { key: "immich",   glyph: "󰋩", label: "Immich sync",   accent: "#f59e0b",         detail: "photos, hourly (cron)" },
        { key: "jellyfin", glyph: "󰝚", label: "Jellyfin sync", accent: "#818cf8",         detail: "" }
    ]
    readonly property var onDemand: [
        { key: "wayvnc", glyph: "󰢹", label: "Remote access", accent: Theme.accent.orange, detail: "VNC on :5900" },
        { key: "winvm",  glyph: "󰖳", label: "Windows VM",    accent: Theme.accent.blue,   detail: "WinApps container" }
    ]

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
    implicitWidth: 28

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
        command: ["bash", mod.scripts + "/services-status.sh"]
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
        runProc.command = ["bash", mod.scripts + "/" + entry.script];
        runProc.startDetached();
        mod.busyKey = entry.key;
        busyTimeout.restart();
        probeSoon.restart();
    }
    function toggle(key) {
        if (key === "immich" || key === "jellyfin")
            runProc.command = ["bash", mod.scripts + "/sync-toggle.sh", "toggle", key];
        else if (key === "wayvnc")
            runProc.command = ["bash", mod.scripts + "/wayvnc-toggle.sh"];
        else if (key === "winvm")
            runProc.command = ["bash", mod.scripts + "/winvm-toggle.sh", "toggle"];
        else return;
        runProc.startDetached();
        mod.busyKey = key;
        busyTimeout.restart();
        probeSoon.restart();
    }
    Timer { id: probeSoon; interval: 1200; onTriggered: probe.running = true }

    // ============ Panel ============
    BarFlyout {
        id: flyout
        parentBar: mod.parentBar
        anchorItem: mod.flyoutAnchor ?? mod
        open: mod.popupOpen
        pinned: mod.pinned
        cardWidth: settingsStore.flyoutSize("services", "w", 380)
        cardHeight: panel.implicitHeight + 28
        onDismissed: mod.popupOpen = false
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_Escape) { mod.popupOpen = false; e.accepted = true; }
        }

        ColumnLayout {
            id: panel
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: Theme.spacing.lg
            }
            spacing: Theme.spacing.sm

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                Text {
                    text: "󰓦"
                    color: Theme.accent.blue
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                }
                Text {
                    Layout.fillWidth: true
                    text: "Services"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                }
                Text {
                    text: mod.daemonsDown > 0 ? mod.daemonsDown + " down" : "all up"
                    color: mod.daemonsDown > 0 ? Theme.accent.orange : Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }

            SectionLabel { text: "SESSION DAEMONS" }
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

            SectionLabel { text: "SCHEDULED" }
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

            SectionLabel { text: "ON DEMAND" }
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
