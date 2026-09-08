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
                        // The cap counts stacks, not notifications: three rows
                        // of "Screenshot" are one stack and take one slot.
                        readonly property int stacks: modelData.clusters.length
                        readonly property bool expanded: pane.notifs.expandedGroups[app] === true
                        readonly property int shown: expanded ? stacks : Math.min(3, stacks)
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
                            model: grp.modelData.clusters.slice(0, grp.shown)
                            delegate: ColumnLayout {
                                id: stack
                                required property var modelData
                                readonly property int count: modelData.entries.length
                                readonly property bool expanded:
                                    pane.notifs.expandedGroups[modelData.key] === true
                                Layout.fillWidth: true
                                spacing: Theme.spacing.xs

                                // The newest entry stands for the whole stack.
                                // Collapsed it carries the ×N badge and the
                                // dismiss hits every entry behind it; expanded
                                // the rest unfold underneath, so this row is
                                // never a duplicate of one of them.
                                HistoryRow {
                                    Layout.fillWidth: true
                                    entry: stack.modelData.entries[0]
                                    stackCount: stack.count
                                    stackExpanded: stack.expanded
                                    onDismissed: stack.count > 1 && !stack.expanded
                                        ? pane.notifs.clearCluster(grp.app, stack.modelData.summary)
                                        : pane.notifs.dismissHistoryEntry(stack.modelData.entries[0].id)
                                    onActivated: pane.notifs.toggleGroup(stack.modelData.key)
                                }
                                Repeater {
                                    model: stack.count > 1 && stack.expanded
                                        ? stack.modelData.entries.slice(1) : []
                                    delegate: HistoryRow {
                                        required property var modelData
                                        entry: modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: Theme.spacing.lg
                                        onDismissed: pane.notifs.dismissHistoryEntry(modelData.id)
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: grp.stacks > 3
                            Layout.fillWidth: true
                            implicitHeight: 26
                            radius: 8 * Theme.radiusScale
                            color: moreMa.containsMouse ? Theme.bgHover : "transparent"
                            border.color: Theme.borderSubtle
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: grp.expanded ? "Show less"
                                    : (grp.stacks - grp.shown) + " more…"
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

    component HistoryRow: Item {
        id: hist
        property var entry
        // Number of notifications this row stands for. 1 (or 0) is a plain
        // row; more than that draws the stack — chevron gutter, sheets, ×N.
        property int stackCount: 1
        property bool stackExpanded: false
        readonly property bool stacked: hist.stackCount > 1
        readonly property bool showSheets: hist.stacked && !hist.stackExpanded
        // Cards peeking out below the front one. Two is enough to read as
        // "several"; a taller pile just eats vertical space in the list.
        readonly property int sheets: hist.showSheets ? Math.min(2, hist.stackCount - 1) : 0
        readonly property int sheetStep: 7
        signal dismissed()
        signal activated()
        // The item reserves room for the sheets, so they peek into the gap
        // below rather than under the next row.
        implicitHeight: card.implicitHeight + hist.sheets * hist.sheetStep
        Behavior on implicitHeight { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }

        // The two cards behind, declared before the front one so it paints
        // over their tops. Each sits one step lower and one step narrower on
        // *both* sides — geometry is explicit rather than anchored so the
        // inset stays symmetric. They stay dark: the panel body behind them
        // is lighter than a card, so a lighter sheet would vanish into it.
        Rectangle {
            visible: hist.sheets >= 2
            x: 2 * hist.sheetStep
            y: 2 * hist.sheetStep
            width: Math.max(0, hist.width - 4 * hist.sheetStep)
            height: card.implicitHeight
            radius: 8 * Theme.radiusScale
            color: Theme.bgDeep
            border.color: Theme.borderStrong
            border.width: 1
        }
        Rectangle {
            visible: hist.sheets >= 1
            x: hist.sheetStep
            y: hist.sheetStep
            width: Math.max(0, hist.width - 2 * hist.sheetStep)
            height: card.implicitHeight
            radius: 8 * Theme.radiusScale
            color: Theme.bg
            border.color: Theme.borderStrong
            border.width: 1
        }

        Rectangle {
            id: card
            width: parent.width
            implicitHeight: cardRow.implicitHeight
            height: implicitHeight
            radius: 8 * Theme.radiusScale
            color: histHover.containsMouse ? Theme.bgHover : Theme.bg
            border.color: hist.stacked && histHover.containsMouse ? Theme.borderStrong : Theme.border
            border.width: 1

            RowLayout {
                id: cardRow
                anchors.fill: parent
                spacing: 0

                // Expand/collapse gutter: the chevron owns the whole left
                // edge of a stack, so the affordance is a column you can hit
                // anywhere rather than a glyph tucked into the title row.
                Rectangle {
                    visible: hist.stacked
                    Layout.preferredWidth: 30
                    Layout.fillHeight: true
                    color: histHover.containsMouse ? Theme.bgActive : Theme.bgDeep
                    // Outlined like the badge, so the gutter reads as a
                    // button. Its left/top/bottom edges trace the card's own
                    // border; the right edge is what divides it from the text.
                    border.color: histHover.containsMouse ? Theme.popupBorder : Theme.borderStrong
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                    // Square off the edge that meets the content so the
                    // gutter reads as part of the card, not a pill on it.
                    topRightRadius: 0
                    bottomRightRadius: 0
                    topLeftRadius: card.radius
                    bottomLeftRadius: card.radius
                    Text {
                        anchors.centerIn: parent
                        text: "󰍝"
                        color: hist.stackExpanded || histHover.containsMouse
                            ? Theme.accent.blue : Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xxl
                        font.bold: true
                        rotation: hist.stackExpanded ? 0 : -90
                        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                        Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
                    }
                }

                ColumnLayout {
                    id: histCol
                    Layout.fillWidth: true
                    Layout.margins: Theme.spacing.md
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
                        Rectangle {
                            visible: hist.stacked
                            implicitWidth: stackBadge.implicitWidth + 12
                            implicitHeight: 18
                            radius: 9 * Theme.radiusScale
                            color: histHover.containsMouse ? Theme.bgActive : Theme.bgDeep
                            border.color: Theme.borderSubtle
                            border.width: 1
                            Text {
                                id: stackBadge
                                anchors.centerIn: parent
                                text: "\u00d7" + hist.stackCount
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                            }
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
                                text: "\u00d7"
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
            }

            MouseArea {
                id: histHover
                anchors.fill: parent
                hoverEnabled: true
                // Only a stack is clickable; a lone notification keeps the
                // plain hover-highlight it had before.
                acceptedButtons: hist.stacked ? Qt.LeftButton : Qt.NoButton
                cursorShape: hist.stacked ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: hist.activated()
            }
        }
    }
}
