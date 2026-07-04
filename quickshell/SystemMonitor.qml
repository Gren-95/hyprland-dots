// System monitor modal: CPU usage + per-core grid, RAM, disk, thermals,
// fans, uptime. All in one centered page. Refreshes every 1.5s while open.
// Bound to Super+M.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool open: false
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
    function refresh() { if (!sysProc.running) sysProc.running = true }

    // Color for percent bars: green → yellow → red.
    function pctColor(p) {
        if (p < 50) return Theme.accent.green;
        if (p < 80) return Theme.accent.yellow;
        return Theme.accent.red;
    }
    function tempColor(t) {
        if (t < 60) return Theme.accent.green;
        if (t < 80) return Theme.accent.yellow;
        return Theme.accent.red;
    }

    Process {
        id: sysProc
        command: ["bash", Quickshell.env("HOME") + "/.config/scripts/sysinfo.sh"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.data = JSON.parse(text); } catch (e) {}
            }
        }
    }

    Timer {
        running: root.open
        interval: settingsStore.sysmonInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("sysmon", "w", 620)
        cardHeight: settingsStore.flyoutSize("sysmon", "h", 640)
        onDismissed: root.close()
        Item {
                anchors.fill: parent
                ColumnLayout {
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: Theme.spacing.lg
                    }
                    spacing: Theme.spacing.md

                    // ============ Modal title ============
                    Text {
                        Layout.fillWidth: true
                        text: "System monitor"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }

                    // ============ CPU card ============
                    StatCard {
                        glyph: "󰍛"
                        title: "PROCESSOR"
                        headline: root.data.cpu_pct.toFixed(0) + "%"
                        subtitle: "across 12 cores · " + root.data.cpu_temp + "°C"
                        headlineColor: root.pctColor(root.data.cpu_pct)
                        pct: root.data.cpu_pct
                        barColor: root.pctColor(root.data.cpu_pct)
                        // Per-core mini-bars
                        contentLoader: Component {
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 6
                                rowSpacing: 4
                                columnSpacing: 4
                                Repeater {
                                    model: root.data.cpu_cores
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        Layout.fillWidth: true
                                        implicitHeight: 16
                                        radius: 3
                                        color: Theme.bgDeep
                                        Rectangle {
                                            anchors {
                                                left: parent.left
                                                top: parent.top
                                                bottom: parent.bottom
                                                margins: 1
                                            }
                                            width: (parent.width - 2) * Math.min(1, modelData / 100)
                                            radius: 2
                                            color: root.pctColor(modelData)
                                            Behavior on width { NumberAnimation { duration: Theme.duration.fast } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "c" + index
                                            color: modelData > 50 ? Theme.bg : Theme.muted
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontSize.xs
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ============ Memory ============
                    StatCard {
                        glyph: "󰧴"
                        title: "MEMORY"
                        headline: root.data.ram_used_gb.toFixed(1) + " GB"
                        subtitle: "of " + root.data.ram_total_gb.toFixed(1) + " GB · " + root.data.ram_pct.toFixed(0) + "%"
                        headlineColor: root.pctColor(root.data.ram_pct)
                        pct: root.data.ram_pct
                        barColor: root.pctColor(root.data.ram_pct)
                    }

                    // ============ Storage (one row per mounted filesystem) ============
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.sm
                        text: "STORAGE"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: -4
                        spacing: 6
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

                    // ============ Thermal chips ============
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.sm
                        text: "THERMAL"
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        font.letterSpacing: 1
                        font.bold: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: -4
                        spacing: Theme.spacing.sm
                        ThermalChip { glyph: "󰻠"; label: "CPU";    value: root.data.cpu_temp + "°";  accent: root.tempColor(root.data.cpu_temp) }
                        ThermalChip { glyph: "󰋊"; label: "NVMe";   value: root.data.nvme_temp + "°"; accent: root.tempColor(root.data.nvme_temp) }
                        ThermalChip { glyph: "󰈐"; label: "Fan 1";  value: root.data.fan1 + "";       accent: Theme.accent.blue; suffix: "rpm" }
                        ThermalChip { glyph: "󰈐"; label: "Fan 2";  value: root.data.fan2 + "";       accent: Theme.accent.blue; suffix: "rpm" }
                    }

                    // ============ Uptime ============
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.sm
                        text: "󱎫  Up " + root.data.uptime
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
        }
    }

    // ───── Reusable: a stat card with glyph, title, headline number, ─────
    // ───── subtitle line, percent bar, and optional nested content. ─────
    component StatCard: Rectangle {
        id: stat
        property string glyph: ""
        property string title: ""
        property string headline: ""
        property string subtitle: ""
        property color headlineColor: Theme.fg
        property real pct: 0
        property color barColor: Theme.accent.blue
        property Component contentLoader: null
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + 24
        radius: 12
        color: Theme.bgDeep
        border.color: Theme.borderSubtle
        border.width: 1

        ColumnLayout {
            id: cardCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 12
            }
            spacing: 6

            // Glyph + title row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: stat.glyph
                    color: stat.headlineColor
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                }
                Text {
                    text: stat.title
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.letterSpacing: 1
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
            }

            // Headline + subtitle
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: -2
                spacing: 8
                Text {
                    text: stat.headline
                    color: stat.headlineColor
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 4
                    text: stat.subtitle
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true }
            }

            // Percent bar
            Rectangle {
                id: barBg
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 8
                radius: 4
                color: Theme.bg
                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        margins: 1
                    }
                    width: (barBg.width - 2) * Math.min(1, stat.pct / 100)
                    radius: 3
                    color: stat.barColor
                    Behavior on width { NumberAnimation { duration: Theme.duration.fast } }
                }
            }

            // Optional nested content (used by CPU card for the per-core grid).
            Loader {
                Layout.fillWidth: true
                Layout.topMargin: 6
                active: stat.contentLoader !== null
                sourceComponent: stat.contentLoader
            }
        }
    }

    // ───── Compact per-disk row ─────
    // One per mounted filesystem. Glyph + mount path + used/total + pct + bar.
    // Used in the STORAGE section; lays out horizontally with a bar below.
    component DiskRow: Rectangle {
        id: dr
        property string mount: ""
        property real usedGb: 0
        property real totalGb: 0
        property real pct: 0
        implicitHeight: drCol.implicitHeight + 16
        radius: 10
        color: Theme.bgDeep
        border.color: Theme.borderSubtle
        border.width: 1

        // Format GB as "62 GB" if < 1000, else "1.0 TB" to keep the row tight.
        function fmt(gb) {
            return gb >= 1000 ? (gb / 1000).toFixed(1) + " TB"
                              : gb.toFixed(0) + " GB";
        }

        ColumnLayout {
            id: drCol
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "󰋊"
                    color: root.pctColor(dr.pct)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                }
                Text {
                    text: dr.mount
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: dr.fmt(dr.usedGb) + " / " + dr.fmt(dr.totalGb) + " · " + dr.pct.toFixed(0) + "%"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }
            Rectangle {
                id: drBarBg
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.bg
                Rectangle {
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        margins: 1
                    }
                    width: (drBarBg.width - 2) * Math.min(1, dr.pct / 100)
                    radius: 2
                    color: root.pctColor(dr.pct)
                    Behavior on width { NumberAnimation { duration: Theme.duration.fast } }
                }
            }
        }
    }

    // ───── Reusable thermal/fan chip ─────
    component ThermalChip: Rectangle {
        id: chip
        property string glyph: ""
        property string label: ""
        property string value: ""
        property string suffix: ""
        property color accent: Theme.accent.blue
        Layout.fillWidth: true
        implicitHeight: 64
        radius: 10
        color: Qt.rgba(accent.r, accent.g, accent.b, 0.08)
        border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.4)
        border.width: 1

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6
                Text {
                    text: chip.glyph
                    color: chip.accent
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                }
                Text {
                    text: chip.value
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                }
                Text {
                    visible: chip.suffix !== ""
                    text: chip.suffix
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: chip.label
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.letterSpacing: 1
            }
        }
    }
}
