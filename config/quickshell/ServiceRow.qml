// One line in the Services panel: what it is, whether it is up, and the one
// action it accepts. Rows with no action (`actionable: false`) still show
// their state — a read-out is the point, the click is a bonus.
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row

    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool on: false
    property bool busy: false
    property color accent: Theme.accent.blue
    property string stateOn: "running"
    property string stateOff: "stopped"
    property bool actionable: true
    signal activated()

    implicitHeight: 52
    radius: Theme.radius.md
    color: tap.pressed && row.actionable ? Theme.bgActive
        : hh.hovered && row.actionable ? Theme.bgHover : "transparent"
    scale: tap.pressed && row.actionable ? 0.98 : 1.0
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.lg

        Rectangle {
            implicitWidth: 36
            implicitHeight: 36
            radius: Theme.radius.md
            color: row.on ? Theme.alpha(row.accent, 0.16) : Theme.bgInset
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Text {
                anchors.centerIn: parent
                text: row.glyph
                color: row.on ? row.accent : Theme.disabled
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: row.label
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.detail !== ""
                text: row.detail
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                elide: Text.ElideRight
            }
        }

        // State never rides on colour alone — the dot always has its word
        // beside it.
        Rectangle {
            implicitWidth: pill.implicitWidth + Theme.spacing.lg
            implicitHeight: 26
            radius: height / 2
            color: row.on ? Theme.alpha(Theme.accent.green, 0.14) : Theme.bgDeep
            border.width: 1
            border.color: row.on ? Theme.alpha(Theme.accent.green, 0.35) : Theme.borderSubtle
            Behavior on color { ColorAnimation { duration: Theme.duration.normal } }
            Behavior on border.color { ColorAnimation { duration: Theme.duration.normal } }

            RowLayout {
                id: pill
                anchors.centerIn: parent
                spacing: Theme.spacing.sm
                Rectangle {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: 4
                    color: row.busy ? Theme.accent.orange
                        : row.on ? Theme.accent.green : Theme.mutedDeep
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                }
                Text {
                    text: row.busy ? "working" : row.on ? row.stateOn : row.stateOff
                    color: row.on ? Theme.fgMuted : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
            }
        }
    }

    HoverHandler { id: hh; enabled: row.actionable }
    TapHandler {
        id: tap
        enabled: row.actionable
        onTapped: row.activated()
    }
}
