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

    implicitHeight: Theme.height.rowSm
    radius: Theme.radius.sm
    color: hh.hovered && row.actionable ? Theme.bgHover : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.md
        anchors.rightMargin: Theme.spacing.md
        spacing: Theme.spacing.md

        Text {
            text: row.glyph
            color: row.on ? row.accent : Theme.disabled
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: row.label
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: row.detail !== ""
                text: row.detail
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                elide: Text.ElideRight
            }
        }

        // State never rides on colour alone — the dot always has its word
        // beside it.
        Rectangle {
            implicitWidth: pill.implicitWidth + Theme.spacing.md
            implicitHeight: Theme.height.chip
            radius: height / 2
            color: row.on ? Qt.rgba(Theme.accent.green.r, Theme.accent.green.g,
                                    Theme.accent.green.b, 0.14) : Theme.bgDeep
            border.width: 1
            border.color: row.on ? Qt.rgba(Theme.accent.green.r, Theme.accent.green.g,
                                           Theme.accent.green.b, 0.35) : Theme.borderSubtle

            RowLayout {
                id: pill
                anchors.centerIn: parent
                spacing: Theme.spacing.xs
                Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: row.busy ? Theme.accent.orange
                        : row.on ? Theme.accent.green : Theme.mutedDeep
                }
                Text {
                    text: row.busy ? "working" : row.on ? row.stateOn : row.stateOff
                    color: row.on ? Theme.fgMuted : Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
            }
        }
    }

    HoverHandler { id: hh; enabled: row.actionable }
    TapHandler {
        enabled: row.actionable
        onTapped: row.activated()
    }
}
