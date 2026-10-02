// System monitor flyout: gauge cards for CPU, memory, per-core load, disks,
// thermals and fans, plus uptime. Refreshes while open. Bound to Super+M.
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
        cpu_pct: 0, cpu_cores: [], cpu_temp: 0,
        ram_used_gb: 0, ram_total_gb: 0, ram_pct: 0,
        nvme_temp: 0, fan1: 0, fan2: 0,
        disks: [], uptime: ""
    })

    function toggle() { open = !open }
    function close()  { open = false }
    property bool _probing: false
    function refresh() {
        if (_probing) return;
        _probing = true;
        Cmd.run(["bash", Paths.scripts + "/sysinfo.sh"], (ok, out) => {
            root._probing = false;
            if (!ok) return;
            try { root.data = JSON.parse(out); } catch (e) { console.warn("[SystemMonitor] parse fail", e); }
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

    Timer {
        running: root.open
        interval: settingsStore.sysmonInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Popup height follows the content (up to what the screen allows).
    readonly property real fitHeight: Math.min(
        anchorBar && anchorBar.screen ? anchorBar.screen.height - 160 : 700,
        contentCol.implicitHeight + Theme.spacing.xl * 2)

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        pinned: root.pinned
        cardWidth: settingsStore.flyoutSize("sysmon", "w", 520)
        cardHeight: settingsStore.flyoutSize("sysmon", "h", root.fitHeight)
        onDismissed: root.close()

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.lg

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: root.pinned
                    onToggled: root.pinned = !root.pinned
                }
                Text {
                    Layout.fillWidth: true
                    text: "System monitor"
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

                    // ===== CPU + memory gauges =====
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.lg
                        visible: settingsStore.sysmonShowCpu || settingsStore.sysmonShowRam

                        GaugeCard {
                            visible: settingsStore.sysmonShowCpu
                            glyph: "󰍛"
                            titleLabel: "PROCESSOR"
                            value: root.data.cpu_pct
                            gaugeColor: root.pctColor(root.data.cpu_pct)
                            centerText: root.data.cpu_pct.toFixed(0) + "%"
                            line1: root.data.cpu_cores.length + " cores"
                            line2: root.data.cpu_temp + "°C"
                        }
                        GaugeCard {
                            visible: settingsStore.sysmonShowRam
                            glyph: "󰧴"
                            titleLabel: "MEMORY"
                            value: root.data.ram_pct
                            gaugeColor: root.pctColor(root.data.ram_pct)
                            centerText: root.data.ram_pct.toFixed(0) + "%"
                            line1: root.data.ram_used_gb.toFixed(1) + " GB"
                            line2: "of " + root.data.ram_total_gb.toFixed(1) + " GB"
                        }
                    }

                    // ===== Per-core load =====
                    Card {
                        visible: settingsStore.sysmonShowCpu && root.data.cpu_cores.length > 0
                        title: "CORES"
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 4
                            rowSpacing: Theme.spacing.md
                            columnSpacing: Theme.spacing.md
                            Repeater {
                                model: root.data.cpu_cores
                                delegate: CoreBar {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    label: "c" + index
                                    pct: modelData
                                }
                            }
                        }
                    }

                    // ===== Storage =====
                    Card {
                        visible: settingsStore.sysmonShowStorage
                        title: "STORAGE"
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
                    }

                    // ===== Thermals and fans =====
                    Card {
                        visible: settingsStore.sysmonShowThermal
                        title: "THERMAL"
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            rowSpacing: Theme.spacing.md
                            columnSpacing: Theme.spacing.md
                            ThermalTile { glyph: "󰻠"; label: "CPU";   number: root.data.cpu_temp;  unit: "°C"; maxValue: 100; tint: root.tempColor(root.data.cpu_temp) }
                            ThermalTile { glyph: "󰋊"; label: "NVMe";  number: root.data.nvme_temp; unit: "°C"; maxValue: 100; tint: root.tempColor(root.data.nvme_temp) }
                            ThermalTile { glyph: "󰈐"; label: "Fan 1"; number: root.data.fan1;      unit: "rpm"; maxValue: 5000; tint: Theme.accent.blue }
                            ThermalTile { glyph: "󰈐"; label: "Fan 2"; number: root.data.fan2;      unit: "rpm"; maxValue: 5000; tint: Theme.accent.blue }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "󱎫  Up " + root.data.uptime
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }
    }

    // A bordered card with an upper-case section label; children stack below.
    component Card: Rectangle {
        id: card
        property string title: ""
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
            anchors.fill: parent
            anchors.margins: Theme.spacing.xl
            spacing: Theme.spacing.md
            Text {
                text: card.title
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.letterSpacing: 1
                font.bold: true
            }
        }
    }

    // Ring gauge card: glyph + title, the ring, and two lines of detail.
    component GaugeCard: Card {
        id: gcard
        property string glyph: ""
        property string titleLabel: ""
        property real value: 0
        property color gaugeColor: Theme.accent.green
        property string centerText: ""
        property string line1: ""
        property string line2: ""
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        title: glyph + "  " + titleLabel

        SysGauge {
            Layout.alignment: Qt.AlignHCenter
            size: 112
            thickness: 10
            value: gcard.value
            color: gcard.gaugeColor
            centerText: gcard.centerText
            centerFontSize: Theme.fontSize.xxl
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: gcard.line1
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            font.bold: true
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: gcard.line2
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.base
        }
    }

    // Thin bar with a label: one logical CPU core.
    component CoreBar: Rectangle {
        id: cb
        property string label: ""
        property real pct: 0
        implicitHeight: 32
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
