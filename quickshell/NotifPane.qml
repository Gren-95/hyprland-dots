// Notification column of the day panel: the quiet-mode switches, the
// now-playing card, then the notification history (flat, or one card per app).
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

    implicitHeight: scroll.naturalHeight

    DayScroll {
        id: scroll
        anchors.fill: parent

        // Quiet toggles. Both belong to this panel rather than the Quick
        // Actions grid: DND governs what lands in the list below it, and
        // Stay Awake is the other "stop interrupting me" switch.
        DayCard {
            Layout.fillWidth: true
            title: "Quiet mode"
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
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
            }
        }

        // MPRIS now-playing card. Present while something is playing; out of
        // the layout when nothing is.
        MediaCard {
            Layout.fillWidth: true
        }

        // ====== History header ======
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            Text {
                text: "NOTIFICATIONS"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                font.letterSpacing: 1
                font.bold: true
            }
            CountChip { count: pane.history.length }
            Item { Layout.fillWidth: true }
            Rectangle {
                visible: pane.history.length > 0
                implicitWidth: clearText.implicitWidth + Theme.spacing.xl * 2
                implicitHeight: 34
                radius: 10 * Theme.radiusScale
                color: clearMouse.pressed ? Theme.alpha(Theme.accent.red, 0.3)
                     : clearMouse.containsMouse ? Theme.accent.redDeep : "transparent"
                border.color: Theme.accent.redDeep
                border.width: 1
                scale: clearMouse.pressed ? 0.94 : 1.0
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                Text {
                    id: clearText
                    anchors.centerIn: parent
                    text: "Clear all"
                    color: clearMouse.containsMouse ? Theme.fg : Theme.accent.redSoft
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
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

        // Flat list when grouping is off.
        DayCard {
            Layout.fillWidth: true
            visible: !settingsStore.notifGroupByApp && pane.history.length > 0
            spacing: Theme.spacing.md
            Repeater {
                model: settingsStore.notifGroupByApp ? [] : pane.history
                delegate: HistoryRow {
                    required property var modelData
                    entry: modelData
                    Layout.fillWidth: true
                    onDismissed: pane.notifs.dismissHistoryEntry(modelData.id)
                }
            }
        }

        // Grouped by app: a card per app (name · count · clear), max 3 stacks
        // until expanded.
        Repeater {
            model: settingsStore.notifGroupByApp && pane.notifs ? pane.notifs.groupedHistory : []
            delegate: DayCard {
                id: grp
                required property var modelData
                readonly property string app: modelData.app
                readonly property int total: modelData.entries.length
                // The cap counts stacks, not notifications: three rows
                // of "Screenshot" are one stack and take one slot.
                readonly property int stacks: modelData.clusters.length
                readonly property bool expanded: pane.notifs.expandedGroups[app] === true
                readonly property int cap: 3

                Layout.fillWidth: true
                title: app

                headerData: [
                    CountChip { visible: grp.total > 1; count: grp.total },
                    IconButton {
                        visible: grp.total > 1
                        onClicked: pane.notifs.clearApp(grp.app)
                    }
                ]

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Repeater {
                        model: grp.modelData.clusters.slice(0, grp.cap)
                        delegate: ClusterStack {
                            required property var modelData
                            required property int index
                            cluster: modelData
                            app: grp.app
                            Layout.fillWidth: true
                            Layout.topMargin: index > 0 ? Theme.spacing.md : 0
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: grp.expanded && grp.stacks > grp.cap
                            ? moreCol.implicitHeight : 0
                        clip: true
                        opacity: grp.expanded ? 1.0 : 0.0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                        Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }
                        ColumnLayout {
                            id: moreCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            spacing: 0
                            Repeater {
                                model: grp.modelData.clusters.slice(grp.cap)
                                delegate: ClusterStack {
                                    required property var modelData
                                    cluster: modelData
                                    app: grp.app
                                    Layout.fillWidth: true
                                    Layout.topMargin: Theme.spacing.md
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    visible: grp.stacks > grp.cap
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 10 * Theme.radiusScale
                    color: moreMa.pressed ? Theme.bgActive : moreMa.containsMouse ? Theme.bgHover : "transparent"
                    border.color: moreMa.containsMouse ? Theme.borderStrong : Theme.borderSubtle
                    border.width: 1
                    scale: moreMa.pressed ? 0.98 : 1.0
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacing.sm
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: grp.expanded ? "Show less" : (grp.stacks - grp.cap) + " more…"
                            color: Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰅀"
                            color: grp.expanded || moreMa.containsMouse ? Theme.accentPrimary : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.md
                            rotation: grp.expanded ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                            Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
                        }
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

        DayCard {
            Layout.fillWidth: true
            visible: pane.history.length === 0
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.lg
                Layout.bottomMargin: Theme.spacing.lg
                spacing: Theme.spacing.md
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰂜"
                    color: Theme.disabled
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.huge
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No notifications"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                }
            }
        }
    }

    // Small pill with a number in it.
    component CountChip: Rectangle {
        property int count: 0
        implicitWidth: Math.max(26, chipText.implicitWidth + 14)
        implicitHeight: 22
        radius: height / 2
        color: Theme.bgInset
        border.color: Theme.borderSubtle
        border.width: 1
        Text {
            id: chipText
            anchors.centerIn: parent
            text: parent.count
            color: Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            font.bold: true
        }
    }

    // Round "×" button used for dismiss and per-app clear.
    component IconButton: Rectangle {
        id: ib
        signal clicked()
        implicitWidth: 34
        implicitHeight: 34
        radius: width / 2
        color: ibMa.pressed ? Theme.alpha(Theme.accent.red, 0.3)
             : ibMa.containsMouse ? Theme.alpha(Theme.accent.red, 0.16) : "transparent"
        scale: ibMa.pressed ? 0.9 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        Text {
            anchors.centerIn: parent
            text: "×"
            color: ibMa.containsMouse ? Theme.accent.redSoft : Theme.muted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xl
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        MouseArea {
            id: ibMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
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
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 56
        radius: 10 * Theme.radiusScale
        color: tgl.on ? Theme.alpha(tgl.accent, 0.18)
             : (tglMa.containsMouse ? Theme.bgActive : Theme.bgInset)
        border.color: tgl.on ? tgl.accent : (tglMa.containsMouse ? Theme.borderStrong : Theme.borderSubtle)
        border.width: 1
        scale: tglMa.pressed ? 0.96 : 1.0
        Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.lg
            anchors.rightMargin: Theme.spacing.lg
            spacing: Theme.spacing.md
            Text {
                text: tgl.glyph
                color: tgl.on ? tgl.accent : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
            }
            ColumnLayout {
                id: tglCol
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tgl.label
                    color: tgl.on ? Theme.fg : Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    font.bold: tgl.on
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: tgl.note !== ""
                    text: tgl.note
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    elide: Text.ElideRight
                }
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

    // One stack of identical notifications. The newest entry stands for the
    // whole stack: collapsed it carries the ×N badge and the dismiss hits
    // every entry behind it; expanded the rest unfold underneath, so this row
    // is never a duplicate of one of them.
    component ClusterStack: ColumnLayout {
        id: stack
        property var cluster
        property string app: ""
        readonly property int count: cluster.entries.length
        readonly property bool expanded: pane.notifs.expandedGroups[cluster.key] === true
        spacing: 0

        HistoryRow {
            Layout.fillWidth: true
            entry: stack.cluster.entries[0]
            stackCount: stack.count
            stackExpanded: stack.expanded
            onDismissed: stack.count > 1 && !stack.expanded
                ? pane.notifs.clearCluster(stack.app, stack.cluster.summary)
                : pane.notifs.dismissHistoryEntry(stack.cluster.entries[0].id)
            onActivated: pane.notifs.toggleGroup(stack.cluster.key)
        }
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: stack.count > 1 && stack.expanded ? rest.implicitHeight : 0
            clip: true
            opacity: stack.expanded ? 1.0 : 0.0
            Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
            Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }
            ColumnLayout {
                id: rest
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.spacing.md
                Repeater {
                    model: stack.count > 1 ? stack.cluster.entries.slice(1) : []
                    delegate: HistoryRow {
                        required property var modelData
                        required property int index
                        entry: modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: Theme.spacing.xl
                        Layout.topMargin: index === 0 ? Theme.spacing.md : 0
                        onDismissed: pane.notifs.dismissHistoryEntry(modelData.id)
                    }
                }
            }
        }
    }

    component HistoryRow: Rectangle {
        id: hist
        property var entry
        // Number of notifications this row stands for. 1 (or 0) is a plain
        // row; more than that draws the stack: chevron, ×N badge.
        property int stackCount: 1
        property bool stackExpanded: false
        readonly property bool stacked: hist.stackCount > 1
        signal dismissed()
        signal activated()

        implicitHeight: Math.max(56, rowContent.implicitHeight + Theme.spacing.lg * 2)
        radius: 10 * Theme.radiusScale
        color: histHover.pressed && hist.stacked ? Theme.bgActive
             : histHover.containsMouse ? (hist.stacked ? Theme.bgActive : Theme.bgHover)
             : Theme.bgInset
        border.color: hist.stacked && histHover.containsMouse ? Theme.borderStrong : Theme.borderSubtle
        border.width: 1
        scale: hist.stacked && histHover.pressed ? 0.985 : 1.0
        Behavior on color        { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation  { duration: Theme.duration.fast } }
        Behavior on scale        { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

        // Row-wide hit area under the contents, so the dismiss button above
        // it keeps its own clicks.
        MouseArea {
            id: histHover
            anchors.fill: parent
            hoverEnabled: true
            // Only a stack is clickable; a lone notification keeps the
            // plain hover-highlight.
            acceptedButtons: hist.stacked ? Qt.LeftButton : Qt.NoButton
            cursorShape: hist.stacked ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: hist.activated()
        }

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.lg
            anchors.rightMargin: Theme.spacing.sm
            spacing: Theme.spacing.md

            Text {
                visible: hist.stacked
                text: "󰅂"
                color: hist.stackExpanded || histHover.containsMouse ? Theme.accentPrimary : Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.lg
                rotation: hist.stackExpanded ? 90 : 0
                Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
            }
            IconImage {
                Layout.alignment: Qt.AlignVCenter
                visible: source != ""
                source: pane.notifs ? pane.notifs.iconFor(hist.entry) : ""
                implicitSize: 24
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
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
            Rectangle {
                visible: hist.stacked
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: stackBadge.implicitWidth + 14
                implicitHeight: 22
                radius: height / 2
                color: Theme.bgDeep
                border.color: Theme.borderSubtle
                border.width: 1
                Text {
                    id: stackBadge
                    anchors.centerIn: parent
                    text: "×" + hist.stackCount
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
            }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: hist.entry ? Qt.formatTime(hist.entry.time, "hh:mm") : ""
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
            }
            IconButton {
                Layout.alignment: Qt.AlignVCenter
                onClicked: hist.dismissed()
            }
        }
    }
}
