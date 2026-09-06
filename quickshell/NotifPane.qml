// Notification column of the day panel: now-playing card on top, then the
// notification history (flat, or bucketed by app).
//
// Pure view over the Notifications service handed in as `notifs`; the toast
// stack and the DBus server stay over there.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

Item {
    id: pane
    property var notifs

    readonly property var history: pane.notifs ? pane.notifs.historyList : []

    ColumnLayout {
        id: paneCol
        anchors.fill: parent
        spacing: Theme.spacing.md

        // ====== Header ======
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            Text {
                text: "󰂚"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
            }
            Text {
                text: "Notifications"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                font.bold: true
            }
            Text {
                text: pane.history.length + " items"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: pane.history.length > 0
                implicitWidth: clearText.implicitWidth + 16
                implicitHeight: 26
                radius: 4 * Theme.radiusScale
                color: clearMouse.containsMouse ? "#7f1d1d" : "transparent"
                border.color: "#7f1d1d"
                border.width: 1
                Text {
                    id: clearText
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: clearMouse.containsMouse ? Theme.fg : "#f87171"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pane.notifs.clearHistory()
                }
            }
        }
        // Quiet toggles. Both belong to this panel rather than the Quick
        // Actions grid: DND governs what lands in the list below it, and
        // Stay Awake is the other "stop interrupting me" switch.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.sm
            PaneToggle {
                glyph: on ? "󰂛" : "󰂚"
                label: "Do Not Disturb"
                accent: Theme.accent.orange
                on: pane.notifs ? pane.notifs.dnd : false
                onToggled: pane.notifs.dnd = !pane.notifs.dnd
            }
            PaneToggle {
                glyph: on ? "󰒲" : "󰒳"
                label: "Stay Awake"
                // Names the automatic condition (media / AC) when something
                // other than the manual switch is holding sleep off.
                note: on ? (idleService.reason || "manual") : ""
                accent: Theme.accent.purple
                on: idleService.effectiveInhibited
                onToggled: idleService.toggleManual()
            }
            Item { Layout.fillWidth: true }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.borderStrong }

        // MPRIS now-playing card. Always present while something is playing;
        // collapses to zero height when nothing is.
        MediaCard {
            id: mediaCard
            Layout.fillWidth: true
            Layout.topMargin: mediaCard.visible ? Theme.spacing.xs : 0
        }

        Flickable {
            id: historyView
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: historyCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: historyCol
                width: historyView.width
                spacing: Theme.spacing.xs

                // Flat list when grouping is off.
                Repeater {
                    model: settingsStore.notifGroupByApp ? [] : pane.history
                    delegate: HistoryRow {
                        required property var modelData
                        entry: modelData
                        Layout.fillWidth: true
                        onDismissed: pane.notifs.dismissHistoryEntry(modelData.id)
                    }
                }
                // Grouped by app: header (name · count · clear) for
                // multi-entry groups, max 3 rows until expanded.
                Repeater {
                    model: settingsStore.notifGroupByApp && pane.notifs ? pane.notifs.groupedHistory : []
                    delegate: ColumnLayout {
                        id: grp
                        required property var modelData
                        readonly property string app: modelData.app
                        readonly property int total: modelData.entries.length
                        readonly property bool expanded: pane.notifs.expandedGroups[app] === true
                        readonly property int shown: expanded ? total : Math.min(3, total)
                        Layout.fillWidth: true
                        spacing: Theme.spacing.xs

                        RowLayout {
                            visible: grp.total > 1
                            Layout.fillWidth: true
                            Layout.topMargin: 4
                            Layout.leftMargin: 4
                            Layout.rightMargin: 4
                            spacing: Theme.spacing.sm
                            Text {
                                text: grp.app
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                                font.bold: true
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                                Layout.maximumWidth: 200
                            }
                            Rectangle {
                                implicitWidth: grpCount.implicitWidth + 10
                                implicitHeight: 16
                                radius: 8 * Theme.radiusScale
                                color: Theme.bgDeep
                                border.color: Theme.borderSubtle
                                border.width: 1
                                Text {
                                    id: grpCount
                                    anchors.centerIn: parent
                                    text: grp.total
                                    color: Theme.mutedDeep
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.xs
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                implicitWidth: 18; implicitHeight: 18; radius: 9 * Theme.radiusScale
                                color: grpClearMa.containsMouse ? Theme.borderStrong : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.md
                                }
                                MouseArea {
                                    id: grpClearMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pane.notifs.clearApp(grp.app)
                                }
                            }
                        }

                        Repeater {
                            model: grp.modelData.entries.slice(0, grp.shown)
                            delegate: HistoryRow {
                                required property var modelData
                                entry: modelData
                                Layout.fillWidth: true
                                onDismissed: pane.notifs.dismissHistoryEntry(modelData.id)
                            }
                        }

                        Rectangle {
                            visible: grp.total > 3
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: 8 * Theme.radiusScale
                            color: moreMa.containsMouse ? Theme.bgHover : "transparent"
                            border.color: Theme.borderSubtle
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: grp.expanded ? "Show less"
                                    : (grp.total - grp.shown) + " more…"
                                color: Theme.fgMuted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.sm
                            }
                            MouseArea {
                                id: moreMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pane.notifs.toggleGroup(grp.app)
                            }
                        }
                    }
                }
                Text {
                    visible: pane.history.length === 0
                    text: "No notifications"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 32
                }
            }
        }
    }

    component PaneToggle: Rectangle {
        id: tgl
        property string glyph: ""
        property string label: ""
        property string note: ""
        property color accent: Theme.accent.blue
        property bool on: false
        signal toggled()
        implicitWidth: tglRow.implicitWidth + 20
        implicitHeight: 30
        radius: 15 * Theme.radiusScale
        color: tgl.on ? Qt.rgba(tgl.accent.r, tgl.accent.g, tgl.accent.b, 0.18)
             : (tglMa.containsMouse ? Theme.bgHover : Theme.bg)
        border.color: tgl.on ? tgl.accent : Theme.border
        border.width: 1
        scale: tglMa.pressed ? 0.94 : 1.0
        Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

        RowLayout {
            id: tglRow
            anchors.centerIn: parent
            spacing: Theme.spacing.sm
            Text {
                text: tgl.glyph
                color: tgl.on ? tgl.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
            }
            Text {
                text: tgl.label
                color: tgl.on ? Theme.fg : Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.bold: tgl.on
            }
            Text {
                visible: tgl.note !== ""
                text: "· " + tgl.note
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
            }
        }
        MouseArea {
            id: tglMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tgl.toggled()
        }
    }

    component HistoryRow: Rectangle {
        id: hist
        property var entry
        signal dismissed()
        implicitHeight: histCol.implicitHeight + 16
        radius: 8 * Theme.radiusScale
        color: histHover.containsMouse ? Theme.bgHover : Theme.bg
        border.color: Theme.border
        border.width: 1

        ColumnLayout {
            id: histCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: Theme.spacing.xs
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                IconImage {
                    visible: source != ""
                    source: pane.notifs ? pane.notifs.iconFor(hist.entry) : ""
                    implicitSize: 18
                }
                Text {
                    Layout.fillWidth: true
                    text: hist.entry ? (hist.entry.summary || hist.entry.appName) : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    text: hist.entry ? Qt.formatTime(hist.entry.time, "hh:mm") : ""
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                }
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20; radius: 10 * Theme.radiusScale
                    color: dismissMouse.containsMouse ? Theme.borderStrong : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                    }
                    MouseArea {
                        id: dismissMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hist.dismissed()
                    }
                }
            }
            Text {
                visible: hist.entry && hist.entry.body
                Layout.fillWidth: true
                text: hist.entry ? hist.entry.body : ""
                color: Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
        MouseArea {
            id: histHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }
    }
}
