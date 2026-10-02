// System monitor flyout in the spirit of btop: CPU and memory history
// graphs, per-core load, network and disk throughput, the busiest processes,
// thermals. Samples sysinfo.sh while open and keeps a short history for the
// graphs. Bound to Super+M.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

Scope {
    id: root
    property bool open: false
    property bool pinned: false
    // Set from the bar so the monitor flyout hangs by the clock cluster.
    property var anchorBar: null
    property var anchorItem: null
    property var data: ({
        cpu_pct: 0, cpu_cores: [], cpu_temp: 0, cpu_model: "", cpu_freq_mhz: 0, load: [0, 0, 0],
        ram_used_gb: 0, ram_total_gb: 0, ram_pct: 0,
        mem: { total: 0, used: 0, available: 0, cached: 0, buffers: 0, free: 0, swap_total: 0, swap_used: 0 },
        nvme_temp: 0, fan1: 0, fan2: 0,
        net: { iface: "", rx: 0, tx: 0 }, io: { read: 0, write: 0 }, ts_ms: 0,
        disks: [], procs: [], uptime: ""
    })

    // ===== History (newest last) and rates derived from the byte counters =====
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var memHistory: []
    property var rxHistory: []
    property var txHistory: []
    property var readHistory: []
    property var writeHistory: []
    property real rxRate: 0
    property real txRate: 0
    property real readRate: 0
    property real writeRate: 0
    property var _previous: null
    property var _previousCpu: null   // { all: [total, idle], cores: [[total, idle], ...] }

    function _push(list, value) {
        const next = list.concat([value]);
        return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    }
    // CPU percentages from the difference between two cumulative samples.
    function _cpuPercent(now, before) {
        const dt = now[0] - before[0];
        return dt > 0 ? Math.max(0, Math.min(100, (1 - (now[1] - before[1]) / dt) * 100)) : 0;
    }
    // Fast probe (sysfast.sh): counters and meminfo, sampled on every tick.
    function _ingestFast(d) {
        const p = _previous;
        const pc = _previousCpu;
        const cpuPct = pc ? _cpuPercent(d.cpu.all, pc.all) : 0;
        const cores = pc ? d.cpu.cores.map((c, i) => _cpuPercent(c, pc.cores[i] || c)) : d.cpu.cores.map(() => 0);
        if (p && d.ts_ms > p.ts_ms) {
            const dt = (d.ts_ms - p.ts_ms) / 1000;
            rxRate = Math.max(0, (d.net.rx - p.net.rx) / dt);
            txRate = Math.max(0, (d.net.tx - p.net.tx) / dt);
            readRate = Math.max(0, (d.io.read - p.io.read) / dt);
            writeRate = Math.max(0, (d.io.write - p.io.write) / dt);
            rxHistory = _push(rxHistory, rxRate);
            txHistory = _push(txHistory, txRate);
            readHistory = _push(readHistory, readRate);
            writeHistory = _push(writeHistory, writeRate);
        }
        if (pc) cpuHistory = _push(cpuHistory, cpuPct);
        const ramPct = d.mem.total > 0 ? d.mem.used / d.mem.total * 100 : 0;
        memHistory = _push(memHistory, ramPct);
        _previous = d;
        _previousCpu = d.cpu;
        data = Object.assign({}, data, {
            cpu_pct: cpuPct, cpu_cores: cores, load: d.load, cpu_freq_mhz: d.cpu_freq_mhz,
            mem: d.mem, ram_pct: ramPct, ram_used_gb: d.mem.used, ram_total_gb: d.mem.total,
            net: d.net, io: d.io, ts_ms: d.ts_ms
        });
    }
    // Slow probe (sysinfo.sh): processes, disk usage, temperatures.
    function _ingestSlow(d) {
        data = Object.assign({}, data, d);
    }
    function _resetHistory() {
        cpuHistory = []; memHistory = []; rxHistory = []; txHistory = [];
        readHistory = []; writeHistory = [];
        rxRate = 0; txRate = 0; readRate = 0; writeRate = 0;
        _previous = null;
        _previousCpu = null;
    }
    onOpenChanged: if (open) {
        _resetHistory();
        paused = false;
    }

    // Refresh control: the chips in the header pick the interval (persisted
    // in settingsStore.sysmonInterval); pausing stops sampling until resumed.
    property bool paused: false
    readonly property var intervalChoices: [500, 1000, 2000, 5000]
    function choiceLabel(ms) { return (ms / 1000) + "s"; }

    function toggle() { open = !open }
    function close()  { open = false }
    // Two probes on separate timers so the cheap one can run as fast as the
    // chips allow: sysfast.sh takes tens of milliseconds, sysinfo.sh (top,
    // df, hwmon) about half a second.
    property bool _fastBusy: false
    property bool _slowBusy: false
    function refreshFast() {
        if (_fastBusy) return;
        _fastBusy = true;
        Cmd.run(["bash", Paths.scripts + "/sysfast.sh"], (ok, out) => {
            root._fastBusy = false;
            if (!ok) return;
            try { root._ingestFast(JSON.parse(out)); } catch (e) { console.warn("[SystemMonitor] fast parse fail", e); }
        });
    }
    function refreshSlow() {
        if (_slowBusy) return;
        _slowBusy = true;
        Cmd.run(["bash", Paths.scripts + "/sysinfo.sh"], (ok, out) => {
            root._slowBusy = false;
            if (!ok) return;
            try { root._ingestSlow(JSON.parse(out)); } catch (e) { console.warn("[SystemMonitor] slow parse fail", e); }
        });
    }

    // Colour for percent gauges: green, yellow, orange, red.
    function pctColor(p) {
        if (p < 50) return Theme.accent.green;
        if (p < 75) return Theme.accent.yellow;
        if (p < 90) return Theme.accent.orange;
        return Theme.accent.red;
    }
    function tempColor(t) {
        if (t < 60) return Theme.accent.green;
        if (t < 75) return Theme.accent.yellow;
        if (t < 85) return Theme.accent.orange;
        return Theme.accent.red;
    }
    // "1.2 MB/s": decimal units, one decimal below 10.
    function fmtRate(bytesPerSec) {
        const units = ["B/s", "KB/s", "MB/s", "GB/s"];
        let v = bytesPerSec, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }
    function fmtBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let v = bytes, i = 0;
        while (v >= 1000 && i < units.length - 1) { v /= 1000; i++; }
        return (v >= 10 || i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + units[i];
    }

    // Sampling interval from the header chips, never faster than 250 ms.
    readonly property int sampleInterval: Math.max(250, settingsStore.sysmonInterval)

    Timer {
        id: refreshTimer
        running: root.open && !root.paused
        interval: root.sampleInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: { root.refreshFast(); countdown.restart(); }
        onIntervalChanged: countdown.restart()
    }
    Timer {
        running: root.open && !root.paused
        interval: Math.max(2000, root.sampleInterval)
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshSlow()
    }

    // Popup height follows the content (up to what the screen allows); the
    // width is the wide two-column layout, clamped to the screen.
    readonly property real fitHeight: Math.min(
        anchorBar && anchorBar.screen ? anchorBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)
    readonly property real fitWidth: Math.min(
        1320, anchorBar && anchorBar.screen ? anchorBar.screen.width - 80 : 1320)

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        pinned: root.pinned
        cardWidth: settingsStore.flyoutSize("sysmon", "w", root.fitWidth)
        cardHeight: settingsStore.flyoutSize("sysmon", "h", root.fitHeight)
        onDismissed: root.close()

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            // Header: pin on the left, title centred, refresh control on the right.
            Item {
                Layout.fillWidth: true
                implicitHeight: 34
                PinButton {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    pinned: root.pinned
                    onToggled: root.pinned = !root.pinned
                }
                Text {
                    anchors.centerIn: parent
                    text: "System monitor"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing.sm
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: Theme.spacing.sm
                        text: "󰑐 Refresh"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        font.letterSpacing: 1
                    }
                    Repeater {
                        model: root.intervalChoices
                        delegate: IntervalChip {
                            required property int modelData
                            label: root.choiceLabel(modelData)
                            active: !root.paused && settingsStore.sysmonInterval === modelData
                            onPicked: { root.paused = false; settingsStore.sysmonInterval = modelData; }
                        }
                    }
                    IntervalChip {
                        label: "󰏤"
                        active: root.paused
                        danger: true
                        onPicked: root.paused = !root.paused
                    }
                }
                // Time until the next sample.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 2
                    radius: 1
                    color: Theme.bgInset
                    Rectangle {
                        height: parent.height
                        radius: 1
                        width: parent.width * countdown.progress
                        color: root.paused ? Theme.mutedDeep : Theme.accentPrimary
                        Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
                    }
                }
                QtObject {
                    id: countdown
                    property real progress: 0
                    function restart() { anim.stop(); progress = 0; if (refreshTimer.running) anim.start(); }
                    property NumberAnimation anim: NumberAnimation {
                        target: countdown
                        property: "progress"
                        from: 0
                        to: 1
                        duration: root.sampleInterval
                    }
                }
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.lg

                        // ----- Left: CPU, memory and network, thermals -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 3
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.spacing.lg

                            Card {
                                visible: settingsStore.sysmonShowCpu
                                title: "CPU"
                                subtitle: root.data.cpu_model
                                headerData: [
                                    Stat { label: "Load"; value: root.data.load.map(l => l.toFixed(2)).join("  ") },
                                    Stat { label: "Freq"; value: (root.data.cpu_freq_mhz / 1000).toFixed(1) + " GHz" },
                                    Stat { label: "Temp"; value: root.data.cpu_temp + "°C"; tint: root.tempColor(root.data.cpu_temp) },
                                    Text {
                                        text: root.data.cpu_pct.toFixed(0) + "%"
                                        color: root.pctColor(root.data.cpu_pct)
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.xxl
                                        font.bold: true
                                        Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                                    }
                                ]

                                SysGraph {
                                    Layout.fillWidth: true
                                    implicitHeight: 120
                                    values: root.cpuHistory
                                    maxValue: 100
                                    samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                    color: root.pctColor(root.data.cpu_pct)
                                }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 6
                                    rowSpacing: Theme.spacing.sm
                                    columnSpacing: Theme.spacing.sm
                                    Repeater {
                                        model: root.data.cpu_cores
                                        delegate: CoreBar {
                                            required property var modelData
                                            required property int index
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            label: "C" + index
                                            pct: modelData
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignTop
                                spacing: Theme.spacing.lg

                                Card {
                                    visible: settingsStore.sysmonShowRam
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1
                                    title: "MEMORY"
                                    subtitle: root.data.mem.total.toFixed(1) + " GB total"
                                    headerData: [
                                        Text {
                                            text: root.data.ram_pct.toFixed(0) + "%"
                                            color: root.pctColor(root.data.ram_pct)
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.xxl
                                            font.bold: true
                                            Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                                        }
                                    ]

                                    SysGraph {
                                        Layout.fillWidth: true
                                        implicitHeight: 100
                                        values: root.memHistory
                                        maxValue: 100
                                        samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                        color: root.pctColor(root.data.ram_pct)
                                    }
                                    MemRow { label: "Used";      value: root.data.mem.used;      total: root.data.mem.total; tint: root.pctColor(root.data.ram_pct) }
                                    MemRow { label: "Available"; value: root.data.mem.available; total: root.data.mem.total; tint: Theme.accent.green }
                                    MemRow { label: "Cached";    value: root.data.mem.cached;    total: root.data.mem.total; tint: Theme.accent.blue }
                                    MemRow { label: "Free";      value: root.data.mem.free;      total: root.data.mem.total; tint: Theme.accent.slate }
                                    MemRow {
                                        visible: root.data.mem.swap_total > 0
                                        label: "Swap"
                                        value: root.data.mem.swap_used
                                        total: root.data.mem.swap_total
                                        tint: Theme.accent.purple
                                    }
                                }

                                Card {
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 1
                                    title: "NETWORK"
                                    subtitle: root.data.net.iface
                                    headerData: [
                                        Text {
                                            text: "󰁅 " + root.fmtRate(root.rxRate) + "   󰁝 " + root.fmtRate(root.txRate)
                                            color: Theme.fg
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.md
                                            font.bold: true
                                        }
                                    ]

                                    SysGraph {
                                        Layout.fillWidth: true
                                        implicitHeight: 70
                                        values: root.rxHistory
                                        maxValue: 0
                                        floorMax: 100000
                                        samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                        color: Theme.accent.teal
                                    }
                                    SysGraph {
                                        Layout.fillWidth: true
                                        implicitHeight: 70
                                        values: root.txHistory
                                        maxValue: 0
                                        floorMax: 100000
                                        mirror: true
                                        samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                        color: Theme.accent.orange
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacing.xl
                                        Stat { label: "Down total"; value: root.fmtBytes(root.data.net.rx); tint: Theme.accent.teal }
                                        Stat { label: "Up total"; value: root.fmtBytes(root.data.net.tx); tint: Theme.accent.orange }
                                        Item { Layout.fillWidth: true }
                                        Stat { label: "Up"; value: root.data.uptime }
                                    }
                                }
                            }
                            Card {
                                visible: settingsStore.sysmonShowThermal
                                title: "THERMAL"
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.md
                                    ThermalTile { glyph: "󰻠"; label: "CPU";   number: root.data.cpu_temp;  unit: "°C"; maxValue: 100; tint: root.tempColor(root.data.cpu_temp) }
                                    ThermalTile { glyph: "󰋊"; label: "NVMe";  number: root.data.nvme_temp; unit: "°C"; maxValue: 100; tint: root.tempColor(root.data.nvme_temp) }
                                    ThermalTile { glyph: "󰈐"; label: "Fan 1"; number: root.data.fan1;      unit: "rpm"; maxValue: 5000; tint: Theme.accent.blue }
                                    ThermalTile { glyph: "󰈐"; label: "Fan 2"; number: root.data.fan2;      unit: "rpm"; maxValue: 5000; tint: Theme.accent.blue }
                                }
                            }
                        }

                        // ----- Right: processes and disks -----
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 2
                            Layout.alignment: Qt.AlignTop
                            spacing: Theme.spacing.lg

                            Card {
                                Layout.fillHeight: true
                                title: "PROCESSES"
                                subtitle: "by CPU"

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.md
                                    ProcHeader { Layout.preferredWidth: 60; text: "PID" }
                                    ProcHeader { Layout.fillWidth: true; Layout.preferredWidth: 3; text: "NAME" }
                                    ProcHeader { Layout.fillWidth: true; Layout.preferredWidth: 3; text: "CPU" }
                                    ProcHeader { Layout.preferredWidth: 56; text: "MEM" }
                                }
                                Repeater {
                                    model: root.data.procs
                                    delegate: ProcRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        proc: modelData
                                    }
                                }
                            }

                            Card {
                                visible: settingsStore.sysmonShowStorage
                                title: "DISKS"
                                headerData: [
                                    Text {
                                        text: "R " + root.fmtRate(root.readRate) + "   W " + root.fmtRate(root.writeRate)
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.base
                                    }
                                ]

                                Repeater {
                                    model: root.data.disks
                                    delegate: DiskRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        mount: modelData.mount
                                        usedGb: modelData.used_gb
                                        totalGb: modelData.total_gb
                                        pct: parseFloat(modelData.pct) || 0
                                    }
                                }
                                SysGraph {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    values: root.readHistory
                                    maxValue: 0
                                    floorMax: 1000000
                                    samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                    color: Theme.accent.green
                                }
                                SysGraph {
                                    Layout.fillWidth: true
                                    implicitHeight: 36
                                    values: root.writeHistory
                                    maxValue: 0
                                    floorMax: 1000000
                                    mirror: true
                                    samples: root.historyLength
                                    scrollMs: root.paused ? 0 : root.sampleInterval
                                    color: Theme.accent.pink
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A bordered card: small-caps title (with an optional muted subtitle) on
    // the left, `headerData` on the right; children stack below.
    component Card: Rectangle {
        id: card
        property string title: ""
        property string subtitle: ""
        property alias headerData: trailing.data
        default property alias content: cardCol.data
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + Theme.spacing.xl * 2
        radius: 10 * Theme.radiusScale
        color: Theme.bg
        border.color: cardHover.hovered ? Theme.borderStrong : Theme.border
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
        HoverHandler { id: cardHover }

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.md

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                ColumnLayout {
                    spacing: 0
                    Text {
                        text: card.title
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    Text {
                        visible: card.subtitle !== ""
                        text: card.subtitle
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                    }
                }
                Item { Layout.fillWidth: true }
                RowLayout {
                    id: trailing
                    spacing: Theme.spacing.md
                }
            }
        }
    }

    // A small pill in the header for picking the refresh interval.
    component IntervalChip: Rectangle {
        id: chip
        property string label: ""
        property bool active: false
        property bool danger: false
        signal picked()
        implicitWidth: Math.max(34, chipText.implicitWidth + 18)
        implicitHeight: 28
        radius: height / 2
        color: chip.active ? Theme.alpha(chip.danger ? Theme.accent.red : Theme.accentPrimary, 0.2)
             : (chipMa.containsMouse ? Theme.bgActive : Theme.bgInset)
        border.color: chip.active ? (chip.danger ? Theme.accent.red : Theme.accentPrimary) : Theme.borderStrong
        border.width: 1
        scale: chipMa.pressed ? 0.92 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.active ? Theme.fg : Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: chip.active
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.picked()
        }
    }

    // A label with its value underneath (load, freq, totals).
    component Stat: ColumnLayout {
        property string label: ""
        property string value: ""
        property color tint: Theme.fg
        spacing: 0
        Text {
            text: parent.label
            color: Theme.mutedDeep
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
        }
        Text {
            text: parent.value
            color: parent.tint
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
            font.bold: true
            Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
        }
    }

    // Thin bar with a label: one logical CPU core.
    component CoreBar: Rectangle {
        id: cb
        property string label: ""
        property real pct: 0
        implicitHeight: 30
        radius: 6 * Theme.radiusScale
        color: Theme.bgInset

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 1 }
            width: Math.max(0, (parent.width - 2) * Math.min(1, cb.pct / 100))
            radius: 5 * Theme.radiusScale
            color: Theme.alpha(root.pctColor(cb.pct), 0.85)
            Behavior on width { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
            Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
        }
        Text {
            anchors.centerIn: parent
            text: cb.label + "  " + cb.pct.toFixed(0) + "%"
            color: cb.pct > 50 ? Theme.fgOnAccent : Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
    }

    // One memory figure: label, a proportional bar and the size in GB.
    component MemRow: RowLayout {
        id: mr
        property string label: ""
        property real value: 0
        property real total: 1
        property color tint: Theme.accent.blue
        Layout.fillWidth: true
        spacing: Theme.spacing.md
        Text {
            Layout.preferredWidth: 78
            text: mr.label
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
        Rectangle {
            id: mrTrack
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4 * Theme.radiusScale
            color: Theme.bgInset
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: mrTrack.width * Math.max(0, Math.min(1, mr.total > 0 ? mr.value / mr.total : 0))
                radius: 4 * Theme.radiusScale
                color: mr.tint
                Behavior on width { NumberAnimation { duration: Theme.duration.slow * 3; easing.type: Theme.easing.standard } }
                Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
            }
        }
        Text {
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
            text: mr.value.toFixed(1) + " GB"
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    // One mounted filesystem: glyph, mount path, used / total, bar.
    component DiskRow: ColumnLayout {
        id: dr
        property string mount: ""
        property real usedGb: 0
        property real totalGb: 0
        property real pct: 0
        spacing: Theme.spacing.sm

        // "62 GB" below 1000, else "1.0 TB".
        function fmt(gb) {
            return gb >= 1000 ? (gb / 1000).toFixed(1) + " TB"
                              : gb.toFixed(0) + " GB";
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            Text {
                text: "󰋊"
                color: root.pctColor(dr.pct)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
            }
            Text {
                text: dr.mount
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
                font.bold: true
            }
            Item { Layout.fillWidth: true }
            Text {
                text: dr.fmt(dr.usedGb) + " / " + dr.fmt(dr.totalGb)
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
            Text {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: dr.pct.toFixed(0) + "%"
                color: root.pctColor(dr.pct)
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: true
                Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
            }
        }
        Rectangle {
            id: drBarBg
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4 * Theme.radiusScale
            color: Theme.bgInset
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: drBarBg.width * Math.min(1, dr.pct / 100)
                radius: 4 * Theme.radiusScale
                color: root.pctColor(dr.pct)
                Behavior on width { NumberAnimation { duration: Theme.duration.slow * 3; easing.type: Theme.easing.standard } }
                Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
            }
        }
    }

    component ProcHeader: Text {
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.sm
        font.letterSpacing: 1
        font.bold: true
    }

    // One process: pid, name, user, a CPU bar and a memory bar.
    component ProcRow: Rectangle {
        id: pr
        property var proc: ({ pid: 0, name: "", user: "", cpu: 0, mem: 0 })
        implicitHeight: 32
        radius: 6 * Theme.radiusScale
        color: prHover.hovered ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        HoverHandler { id: prHover }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.sm
            anchors.rightMargin: Theme.spacing.sm
            spacing: Theme.spacing.md
            Text {
                Layout.preferredWidth: 60
                text: pr.proc.pid
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
            Text {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                text: pr.proc.name
                color: Theme.fg
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                spacing: Theme.spacing.md
                Rectangle {
                    id: cpuTrack
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Theme.bgInset
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: cpuTrack.width * Math.min(1, pr.proc.cpu / 100)
                        radius: 3
                        color: root.pctColor(pr.proc.cpu)
                        Behavior on width { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                        Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                    }
                }
                Text {
                    Layout.preferredWidth: 50
                    horizontalAlignment: Text.AlignRight
                    text: pr.proc.cpu.toFixed(1) + "%"
                    color: root.pctColor(pr.proc.cpu)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: true
                }
            }
            Text {
                Layout.preferredWidth: 56
                horizontalAlignment: Text.AlignRight
                text: pr.proc.mem.toFixed(1) + "%"
                color: Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
            }
        }
    }

    // Temperature or fan tile: small ring on the left, reading on the right.
    component ThermalTile: Rectangle {
        id: tile
        property string glyph: ""
        property string label: ""
        property real number: 0
        property string unit: ""
        property real maxValue: 100
        property color tint: Theme.accent.blue
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 64
        radius: 8 * Theme.radiusScale
        color: tileHover.hovered ? Theme.bgActive : Theme.bgInset
        border.color: Theme.alpha(tile.tint, tileHover.hovered ? 0.6 : 0.35)
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
        HoverHandler { id: tileHover }

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.lg
            SysGauge {
                size: 44
                thickness: 5
                value: tile.number
                maxValue: tile.maxValue
                color: tile.tint
                Text {
                    anchors.centerIn: parent
                    text: tile.glyph
                    color: tile.tint
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    spacing: Theme.spacing.xs
                    Text {
                        text: tile.number + ""
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.lg
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignBottom
                        text: tile.unit
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                    }
                }
                Text {
                    text: tile.label
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
            }
        }
    }
}
