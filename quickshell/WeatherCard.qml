// Current conditions for the day panel's calendar column: the reading itself,
// then today's spread as a row of chips.
//
// Colour carries meaning here rather than decoration: the condition glyph
// takes its bucket's colour (yellow sun, blue rain, purple storm), and every
// temperature runs through the same warm-to-cool ramp, so freezing and hot
// are distinguishable before the number is read. The ramp's bands are wide
// on purpose — a high and a low within the same band should look alike.
// The chips sit in a Flow so a narrower panel wraps them instead of clipping.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    readonly property var svc: weatherService
    // { glyph, value, colour } — dropped when the field is missing.
    readonly property var metrics: !svc.ready ? [] : [
        { g: "󰖌", v: svc.humidity + "%",                          c: Theme.accent.blueBright, on: svc.humidity >= 0 },
        { g: "󰖝", v: Math.round(svc.wind) + " " + svc.windUnit,   c: Theme.accent.teal,       on: true },
        { g: "󰘇", v: svc.precipProb + "%",                        c: Theme.accent.blue,       on: svc.precipProb >= 0 },
        { g: "󰖜", v: svc.sunrise,                                 c: Theme.accent.orange,     on: svc.sunrise !== "" },
        { g: "󰖛", v: svc.sunset,                                  c: Theme.accent.purple,     on: svc.sunset !== "" }
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
        spacing: Theme.spacing.xs

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

        Flow {
            Layout.fillWidth: true
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
