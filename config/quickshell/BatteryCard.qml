// Battery summary card for the Audio & Power popup: a progress ring that
// animates while charging (a bright arc chases along the filled part, the
// bolt breathes, a halo pulses), the charge state with time remaining, and a
// few UPower readings. Hidden when there is no battery.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Services.UPower

Rectangle {
    id: card

    readonly property var dev: UPower.displayDevice
    readonly property bool present: !!dev && dev.isPresent
    readonly property real pct: dev ? dev.percentage * 100 : 0
    readonly property bool charging: !!dev && dev.state === UPowerDeviceState.Charging
    readonly property bool full: !!dev && dev.state === UPowerDeviceState.FullyCharged
    readonly property bool plugged: !UPower.onBattery
    readonly property color stateColor: charging || full || plugged ? Theme.accent.green
        : pct <= 20 ? Theme.accent.red
        : pct <= 40 ? Theme.accent.orange
        : Theme.accent.yellow

    // Animated copy of the percentage so the ring and number glide to a new
    // level instead of snapping.
    property real shownPct: 0
    Behavior on shownPct { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    onPctChanged: shownPct = pct
    Component.onCompleted: shownPct = pct

    function _span(seconds) {
        const m = Math.round(seconds / 60);
        if (m < 1) return "<1m";
        const h = Math.floor(m / 60);
        return h > 0 ? h + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m" : m + "m";
    }
    readonly property string statusText: {
        if (!dev) return "";
        if (full) return "Fully charged";
        if (charging) return dev.timeToFull > 0 ? "Charging · " + _span(dev.timeToFull) + " to full" : "Charging";
        if (plugged) return "Plugged in";
        return dev.timeToEmpty > 0 ? _span(dev.timeToEmpty) + " left" : "On battery";
    }

    visible: present
    implicitHeight: present ? 152 : 0
    radius: 10 * Theme.radiusScale
    color: Theme.bg
    border.color: Theme.border
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.xl

        // ===== Ring =====
        Item {
            id: ringBox
            Layout.preferredWidth: 112
            Layout.preferredHeight: 112
            Layout.alignment: Qt.AlignVCenter

            // Breathing halo behind the ring while charging.
            Rectangle {
                id: halo
                anchors.centerIn: parent
                width: parent.width - 4
                height: width
                radius: width / 2
                color: "transparent"
                border.color: card.stateColor
                border.width: 2
                opacity: 0
                scale: 1
                visible: card.charging
                ParallelAnimation {
                    running: card.charging && card.visible
                    loops: Animation.Infinite
                    SequentialAnimation {
                        NumberAnimation { target: halo; property: "opacity"; from: 0.45; to: 0.0; duration: 1600; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 300 }
                    }
                    SequentialAnimation {
                        NumberAnimation { target: halo; property: "scale"; from: 1.0; to: 1.22; duration: 1600; easing.type: Easing.OutCubic }
                        PauseAnimation { duration: 300 }
                    }
                }
            }

            Shape {
                id: ring
                anchors.fill: parent
                layer.enabled: true
                layer.samples: 4

                readonly property real cx: width / 2
                readonly property real r: width / 2 - 8
                readonly property real sweep: 360 * Math.max(0, Math.min(100, card.shownPct)) / 100
                // 0..1 position of the chasing arc along the filled part.
                property real chase: 0
                readonly property real chaseLen: 26

                SequentialAnimation on chase {
                    running: card.charging && card.visible && ring.sweep > ring.chaseLen
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 1; duration: 1900; easing.type: Easing.InOutSine }
                    PauseAnimation { duration: 350 }
                }

                ShapePath {
                    strokeColor: Theme.bgInset
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: ring.cx; centerY: ring.cx; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: card.stateColor
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    Behavior on strokeColor { ColorAnimation { duration: Theme.duration.slow } }
                    PathAngleArc { centerX: ring.cx; centerY: ring.cx; radiusX: ring.r; radiusY: ring.r; startAngle: -90; sweepAngle: ring.sweep }
                }
                // The "energy flowing in" highlight: a short bright arc that
                // travels along the filled part and fades at the ends.
                ShapePath {
                    strokeColor: Qt.rgba(1, 1, 1, card.charging ? 0.85 * Math.sin(ring.chase * Math.PI) : 0)
                    strokeWidth: 10
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.cx; centerY: ring.cx; radiusX: ring.r; radiusY: ring.r
                        startAngle: -90 + ring.chase * Math.max(0, ring.sweep - ring.chaseLen)
                        sweepAngle: ring.chaseLen
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                Text {
                    id: bolt
                    Layout.alignment: Qt.AlignHCenter
                    text: "󱐋"
                    color: card.stateColor
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    visible: card.charging
                    SequentialAnimation on opacity {
                        running: card.charging && card.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation on scale {
                        running: card.charging && card.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 1.18; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1.18; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(card.shownPct) + "%"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xxl
                    font.bold: true
                }
            }
        }

        // ===== Status + readings =====
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.spacing.md

            Rectangle {
                id: chip
                implicitHeight: 30
                implicitWidth: chipRow.implicitWidth + 22
                radius: height / 2
                color: Theme.alpha(card.stateColor, 0.16)
                border.color: Theme.alpha(card.stateColor, 0.45)
                border.width: 1
                Behavior on color { ColorAnimation { duration: Theme.duration.slow } }
                Behavior on border.color { ColorAnimation { duration: Theme.duration.slow } }
                Behavior on implicitWidth { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Theme.spacing.sm
                    Rectangle {
                        id: dot
                        width: 7; height: 7; radius: 3.5
                        color: card.stateColor
                        SequentialAnimation on opacity {
                            running: card.charging && card.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 0.25; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        text: card.statusText
                        color: card.stateColor
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.spacing.lg
                rowSpacing: 4
                Text {
                    visible: !!card.dev && Math.abs(card.dev.changeRate) > 0.05
                    text: card.charging ? "Charge rate" : "Power draw"
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
                Text {
                    visible: !!card.dev && Math.abs(card.dev.changeRate) > 0.05
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: card.dev ? Math.abs(card.dev.changeRate).toFixed(1) + " W" : ""
                    color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
                Text {
                    visible: !!card.dev && card.dev.energyCapacity > 0
                    text: "Energy"
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
                Text {
                    visible: !!card.dev && card.dev.energyCapacity > 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: card.dev ? card.dev.energy.toFixed(1) + " / " + card.dev.energyCapacity.toFixed(1) + " Wh" : ""
                    color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
                Text {
                    visible: !!card.dev && card.dev.healthSupported
                    text: "Health"
                    color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
                Text {
                    visible: !!card.dev && card.dev.healthSupported
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: card.dev ? Math.round(card.dev.healthPercentage) + "%" : ""
                    color: Theme.fg; font.family: Theme.font; font.pixelSize: Theme.fontSize.base
                }
            }
        }
    }
}
