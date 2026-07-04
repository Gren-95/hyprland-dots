// Shell settings flyout: tabbed panel (General | Bar | Appearance | Tuning)
// hanging under the Quick Actions chevron. Opened from the Quick Actions
// gear tile or the `quickshell:settings` global shortcut (Super+,).
import QtQuick
import QtQuick.Layouts
import Quickshell

Scope {
    id: root

    property bool open: false
    property bool pinned: false
    property string activeTab: "general"
    // Set from the bar (shell.qml Component.onCompleted).
    property var anchorBar: null
    property var anchorItem: null

    readonly property var tabs: [
        { glyph: "󰒓", label: "General",    accent: Theme.accent.blue,   id: "general" },
        { glyph: "󰍜", label: "Bar",        accent: Theme.accent.teal,   id: "bar" },
        { glyph: "󰏘", label: "Appearance", accent: Theme.accent.purple, id: "appearance" },
        { glyph: "󰢻", label: "Tuning",     accent: Theme.accent.orange, id: "tuning" },
    ]

    function toggle() { open = !open; if (open) activeTab = "general"; }
    function close() { open = false; }
    function cycleTab(delta) {
        const ids = tabs.map(t => t.id);
        const i = ids.indexOf(activeTab);
        activeTab = ids[((i + delta) % ids.length + ids.length) % ids.length];
    }

    BarFlyout {
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: 560
        cardHeight: 640
        pinned: root.pinned
        onDismissed: root.open = false
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) {
                root.cycleTab(e.key === Qt.Key_Backtab || (e.modifiers & Qt.ShiftModifier) ? -1 : 1);
                e.accepted = true;
            }
        }

        Item {
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.md
                    PinButton {
                        pinned: root.pinned
                        onToggled: root.pinned = !root.pinned
                    }
                    Text {
                        text: "Settings"
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.md
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Tab tabs · Esc close"
                        color: Theme.disabled
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xs
                    }
                }

                TabStrip {
                    Layout.fillWidth: true
                    tabs: root.tabs
                    activeId: root.activeTab
                    onPicked: (id) => root.activeTab = id
                }

                // ===== Tab content =====
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: tabCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: tabCol
                        width: parent.width
                        spacing: Theme.spacing.sm

                        // ---------- GENERAL ----------
                        ColumnLayout {
                            visible: root.activeTab === "general"
                            Layout.fillWidth: true
                            spacing: Theme.spacing.sm

                            SectionLabel { text: "BAR WIDGETS" }
                            SettingRow {
                                Layout.fillWidth: true
                                glyph: "󰎈"; offGlyph: "󰎈"
                                accent: Theme.accent.purple
                                label: "Media keys"
                                desc: on ? "Prev / play / next in bar" : "Hidden"
                                on: settingsStore.mediaKeysVisible
                                onPicked: settingsStore.mediaKeysVisible = !settingsStore.mediaKeysVisible
                            }
                            SettingRow {
                                Layout.fillWidth: true
                                glyph: "󰈈"; offGlyph: "󰈉"
                                accent: Theme.accent.teal
                                label: "Activity icons"
                                desc: on ? "Camera/mic/sync icons shown" : "Hidden"
                                on: settingsStore.activityIconsVisible
                                onPicked: settingsStore.activityIconsVisible = !settingsStore.activityIconsVisible
                            }

                            SectionLabel { text: "NOTIFICATIONS" }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Toast timeout"
                                desc: "Auto-dismiss when the app sets no timeout"
                                value: settingsStore.toastTimeout
                                step: 1000; min: 2000; max: 15000
                                display: (settingsStore.toastTimeout / 1000) + "s"
                                onStepped: (v) => settingsStore.toastTimeout = v
                            }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "History size"
                                desc: "Notifications kept in the center"
                                value: settingsStore.notifHistoryCap
                                step: 10; min: 10; max: 200
                                display: String(settingsStore.notifHistoryCap)
                                onStepped: (v) => settingsStore.notifHistoryCap = v
                            }
                        }

                        // ---------- APPEARANCE ----------
                        ColumnLayout {
                            visible: root.activeTab === "appearance"
                            Layout.fillWidth: true
                            spacing: Theme.spacing.sm

                            SectionLabel { text: "HIGHLIGHT ACCENT" }
                            // Swatch row: pick the accent used for selections,
                            // highlights and active states shell-wide.
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: 10
                                color: "#1a1716"
                                border.color: Theme.borderSubtle
                                border.width: 1
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacing.md
                                    Repeater {
                                        model: ["blue", "green", "red", "orange", "yellow", "purple", "pink", "teal", "slate"]
                                        delegate: Rectangle {
                                            required property string modelData
                                            readonly property bool active: settingsStore.accentPrimaryName === modelData
                                            implicitWidth: 30
                                            implicitHeight: 30
                                            radius: 15
                                            color: Theme.accent[modelData]
                                            border.color: active ? Theme.fg : "transparent"
                                            border.width: active ? 3 : 0
                                            scale: swMa.containsMouse ? 1.12 : 1.0
                                            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
                                            MouseArea {
                                                id: swMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: settingsStore.accentPrimaryName = parent.modelData
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "TYPE & BAR" }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Font scale"
                                desc: "Scales every text size in the shell"
                                value: Math.round(settingsStore.fontScale * 100)
                                step: 5; min: 80; max: 130
                                display: Math.round(settingsStore.fontScale * 100) + "%"
                                onStepped: (v) => settingsStore.fontScale = v / 100
                            }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Bar height"
                                desc: "Height of the top bar in pixels"
                                value: settingsStore.barHeight
                                step: 2; min: 28; max: 48
                                display: settingsStore.barHeight + "px"
                                onStepped: (v) => settingsStore.barHeight = v
                            }

                            SectionLabel { text: "FONT FAMILY" }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 44
                                radius: 10
                                color: "#1a1716"
                                border.color: fontInput.activeFocus ? Theme.accentPrimary : Theme.borderSubtle
                                border.width: 1
                                TextInput {
                                    id: fontInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: settingsStore.fontFamily
                                    color: Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontSize.base
                                    selectByMouse: true
                                    clip: true
                                    // Commit on Enter / focus loss, not per keystroke.
                                    onEditingFinished: settingsStore.fontFamily = text
                                }
                            }
                        }

                        // ---------- PLACEHOLDERS (filled in later phases) ----------
                        Text {
                            visible: root.activeTab !== "general" && root.activeTab !== "appearance"
                            Layout.fillWidth: true
                            Layout.topMargin: 24
                            text: "Coming in a later phase"
                            color: Theme.disabled
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }

    // Uppercase section header, matching the shell convention.
    component SectionLabel: Text {
        Layout.topMargin: 6
        color: Theme.mutedDeep
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.xs
        font.letterSpacing: 1
        font.bold: true
    }

    // Numeric setting row: label + description left, − value + right.
    component StepperRow: Rectangle {
        id: srow
        property string label: ""
        property string desc: ""
        property int value: 0
        property int step: 1
        property int min: 0
        property int max: 100
        property string display: String(value)
        signal stepped(int v)

        implicitHeight: 54
        radius: 10
        color: "#1a1716"
        border.color: Theme.borderSubtle
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.lg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: srow.label
                    color: Theme.fgDim
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                }
                Text {
                    Layout.fillWidth: true
                    text: srow.desc
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    elide: Text.ElideRight
                }
            }

            StepBtn { glyph: "−"; onClicked: srow.stepped(Math.max(srow.min, srow.value - srow.step)) }
            Text {
                Layout.preferredWidth: 48
                text: srow.display
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }
            StepBtn { glyph: "+"; onClicked: srow.stepped(Math.min(srow.max, srow.value + srow.step)) }
        }
    }

    component StepBtn: Rectangle {
        property string glyph: ""
        signal clicked()
        implicitWidth: 26
        implicitHeight: 26
        radius: 6
        color: sbMa.containsMouse ? Theme.bgHover : Theme.bgDeep
        border.color: Theme.borderStrong
        border.width: 1
        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
        }
        MouseArea {
            id: sbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
