// Current conditions for the day panel's calendar column: the reading, then
// when it is going to rain, then today's spread as a row of chips.
//
// Colour carries meaning rather than decoration. The condition glyph takes
// its WMO bucket's accent and every temperature runs through `tempColor`, a
// deliberately coarse warm-to-cool ramp — coarse so a high and a low in the
// same band stay the same colour.
//
// The hourly strip plots one measure, chance of rain, as bar height. Colour
// is NOT a second copy of that height: all bars share one hue, and the only
// distinction is dim below the rain threshold, full above it, so the hours
// worth caring about are the ones that stand out. The dim step is the pale
// end of the ramp and clears the card surface at 2.4:1. Only the peak is
// labelled — a number over every bar goes unread.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    readonly property var svc: weatherService
    // Bar hovered in the strip, or -1. Swaps the summary line for that hour.
    property int hover: -1

    readonly property color barHue: Theme.accent.blueBright
    readonly property real dimStep: 0.45     // validated pale end of the ramp

    // { glyph, value, colour } — dropped when the field is missing.
    readonly property var metrics: !svc.ready ? [] : [
        { g: "󰖌", v: svc.humidity + "%",                        c: Theme.accent.blueBright, on: svc.humidity >= 0 },
        { g: "󰖝", v: Math.round(svc.wind) + " " + svc.windUnit, c: Theme.accent.teal,       on: true },
        { g: "󰖜", v: svc.sunrise,                               c: Theme.accent.orange,     on: svc.sunrise !== "" },
        { g: "󰖛", v: svc.sunset,                                c: Theme.accent.purple,     on: svc.sunset !== "" }
    ].filter(m => m.on)

    implicitHeight: content.implicitHeight + Theme.spacing.md * 2
    color: Theme.bgInset
    radius: Theme.radius.md
    border.width: 1
    border.color: Theme.borderSubtle

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacing.md
        spacing: Theme.spacing.sm

        // ====== The reading ======
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md

            Text {
                text: card.svc.glyph
                color: card.svc.accent
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
            }

            ColumnLayout {
                spacing: 0
                RowLayout {
                    spacing: Theme.spacing.sm
                    Text {
                        text: card.svc.display
                        color: card.svc.tempColor(card.svc.temp)
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                        font.bold: true
                    }
                    Text {
                        Layout.alignment: Qt.AlignBaseline
                        text: card.svc.label
                        color: Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                    }
                }
                Text {
                    text: "feels " + Math.round(card.svc.feelsLike) + "°"
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
            }

            Item { Layout.fillWidth: true }

            // Today's spread, both on the same ramp as the reading.
            RowLayout {
                spacing: Theme.spacing.xs
                Text {
                    text: "󰔏"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                }
                Text {
                    text: "↑" + Math.round(card.svc.high) + "°"
                    color: card.svc.tempColor(card.svc.high)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: true
                }
                Text {
                    text: "↓" + Math.round(card.svc.low) + "°"
                    color: card.svc.tempColor(card.svc.low)
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: true
                }
            }
        }

        // ====== When it rains ======
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.xs
            visible: card.svc.hours.length > 0
            spacing: Theme.spacing.sm

            Text {
                readonly property bool wet: card.svc.rainWindows().length > 0
                text: wet ? "󰖗" : "󰖙"
                color: wet ? Theme.accent.blue : Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
            }
            Text {
                Layout.fillWidth: true
                text: {
                    const h = card.hover;
                    if (h >= 0 && h < card.svc.hours.length) {
                        const e = card.svc.hours[h];
                        return e.hh + ":00 · " + e.prob + "% rain · " + Math.round(e.temp) + "°";
                    }
                    return card.svc.rainSummary;
                }
                color: card.hover >= 0 ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                elide: Text.ElideRight
            }
        }

        // ====== Next 12 hours: chance of rain ======
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.svc.hours.length > 0
            spacing: 2

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 30

                // The axis the bars stand on — hairline, recessive, and the
                // whole chart on a day with nothing forecast.
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.border
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                        model: card.svc.hours
                        delegate: Item {
                            id: slot
                            required property var modelData
                            required property int index
                            readonly property bool wet: modelData.prob >= card.svc.rainThreshold
                            readonly property int barW: Math.min(18, Math.max(6, width - 6))

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Hover well: invisible until pointed at, so a dry
                            // strip stays a baseline and nothing else.
                            Rectangle {
                                anchors.fill: parent
                                radius: 3
                                visible: card.hover === slot.index
                                color: Theme.bgHover
                            }

                            Rectangle {
                                id: bar
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: slot.barW
                                height: Math.round((parent.height - 1)
                                    * Math.min(100, slot.modelData.prob) / 100)
                                radius: 4
                                visible: slot.modelData.prob > 0
                                color: Qt.rgba(card.barHue.r, card.barHue.g, card.barHue.b,
                                               slot.wet ? 1 : card.dimStep)
                                // Square off the foot: the rounded end belongs
                                // to the data, the base belongs to the axis.
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: Math.min(4, parent.height)
                                    color: parent.color
                                }
                            }

                            // Only the peak carries a number.
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: bar.top
                                anchors.bottomMargin: 1
                                visible: slot.index === card.svc.peakHour && slot.modelData.prob > 0
                                text: slot.modelData.prob + "%"
                                color: Theme.fgMuted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                            }

                            HoverHandler {
                                onHoveredChanged: card.hover = hovered ? slot.index : -1
                            }
                        }
                    }
                }
            }

            // Axis: every third hour, so the labels never collide.
            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                Repeater {
                    model: card.svc.hours
                    delegate: Text {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: index % 3 === 0 ? modelData.hh : ""
                        color: Theme.mutedDeep
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                    }
                }
            }
        }

        // ====== Everything else ======
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: Theme.spacing.xs
            spacing: Theme.spacing.lg

            Repeater {
                model: card.metrics
                delegate: Row {
                    required property var modelData
                    spacing: Theme.spacing.xs
                    Text {
                        text: modelData.g
                        color: modelData.c
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                    }
                    Text {
                        text: modelData.v
                        color: Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                    }
                }
            }
        }
    }
}
