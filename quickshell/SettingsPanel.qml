// Shell settings flyout: tabbed panel (General | Bar | Appearance | Tuning)
// hanging under the Quick Actions chevron. Opened from the Quick Actions
// gear tile or the `quickshell:settings` global shortcut (Super+,).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

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
        cardWidth: settingsStore.flyoutSize("settings", "w", 560)
        cardHeight: settingsStore.flyoutSize("settings", "h", 640)
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

                        // ---------- TUNING ----------
                        ColumnLayout {
                            visible: root.activeTab === "tuning"
                            Layout.fillWidth: true
                            spacing: Theme.spacing.sm

                            SectionLabel { text: "MODULES" }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Launcher results"
                                desc: "Apps listed in Spotlight"
                                value: settingsStore.spotlightCap
                                step: 10; min: 20; max: 200
                                display: String(settingsStore.spotlightCap)
                                onStepped: (v) => settingsStore.spotlightCap = v
                            }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "OSD duration"
                                desc: "Volume/brightness popup linger"
                                value: settingsStore.osdDuration
                                step: 250; min: 500; max: 5000
                                display: (settingsStore.osdDuration / 1000).toFixed(2).replace(/\.?0+$/, "") + "s"
                                onStepped: (v) => settingsStore.osdDuration = v
                            }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Monitor refresh"
                                desc: "System-monitor update interval"
                                value: settingsStore.sysmonInterval
                                step: 500; min: 500; max: 10000
                                display: (settingsStore.sysmonInterval / 1000).toFixed(1) + "s"
                                onStepped: (v) => settingsStore.sysmonInterval = v
                            }
                            StepperRow {
                                Layout.fillWidth: true
                                label: "Calendar refresh"
                                desc: "Minutes between ICS fetches"
                                value: settingsStore.calendarFetchInterval
                                step: 5; min: 5; max: 120
                                display: settingsStore.calendarFetchInterval + "m"
                                onStepped: (v) => settingsStore.calendarFetchInterval = v
                            }

                            SectionLabel { text: "CALENDAR URL" }
                            PathField {
                                Layout.fillWidth: true
                                text: calUrlFile.loadedText
                                placeholder: "https://…/basic.ics"
                                onCommitted: (t) => calUrlFile.write(t)
                            }

                            SectionLabel { text: "WALLPAPER FOLDER" }
                            PathField {
                                Layout.fillWidth: true
                                text: settingsStore.wallpaperDir
                                placeholder: "~/Pictures/wallpapers"
                                onCommitted: (t) => settingsStore.wallpaperDir = t
                            }

                            SectionLabel { text: "FLYOUT SIZES" }
                            Repeater {
                                model: [
                                    { id: "spotlight",     label: "Launcher",       w: 560, h: 560 },
                                    { id: "clipboard",     label: "Clipboard",      w: 560, h: 620 },
                                    { id: "keybinds",      label: "Keybinds",       w: 640, h: 620 },
                                    { id: "calendar",      label: "Calendar",       w: 400, h: 660 },
                                    { id: "notifications", label: "Notifications",  w: 420, h: 620 },
                                    { id: "sysmon",        label: "System monitor", w: 620, h: 640 },
                                    { id: "wallpaper",     label: "Wallpaper",      w: 560, h: 560 },
                                    { id: "quickactions",  label: "Quick actions",  w: 420, h: 0 },
                                    { id: "audiopower",    label: "Audio & Power",  w: 380, h: 480 },
                                    { id: "network",       label: "Network",        w: 360, h: 460 },
                                    { id: "settings",      label: "Settings",       w: 560, h: 640 },
                                ]
                                delegate: SizeRow {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    def: modelData
                                }
                            }
                        }

                        // ---------- PLACEHOLDERS (filled in later phases) ----------
                        Text {
                            visible: root.activeTab === "bar"
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

    // Calendar URL lives in its own config file (IcsCalendar watches it).
    FileView {
        id: calUrlFile
        property string loadedText: ""
        path: Quickshell.env("HOME") + "/.config/quickshell/calendar.url"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: loadedText = text().trim()
        onFileChanged: reload()
        function write(t) { setText(t.trim() + "\n"); loadedText = t.trim(); }
    }

    // Editable path/URL field committing on Enter or focus loss.
    component PathField: Rectangle {
        id: pf
        property string text: ""
        property string placeholder: ""
        signal committed(string t)
        implicitHeight: 44
        radius: 10
        color: "#1a1716"
        border.color: pfInput.activeFocus ? Theme.accentPrimary : Theme.borderSubtle
        border.width: 1
        TextInput {
            id: pfInput
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            text: pf.text
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.sm
            selectByMouse: true
            clip: true
            onEditingFinished: pf.committed(text)
            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: pfInput.text === "" && !pfInput.activeFocus
                text: pf.placeholder
                color: Theme.disabled
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
            }
        }
    }

    // Width/height steppers for one flyout. def: { id, label, w, h } —
    // h === 0 means the height is content-driven and not adjustable.
    component SizeRow: Rectangle {
        id: sz
        property var def
        implicitHeight: 44
        radius: 10
        color: "#1a1716"
        border.color: Theme.borderSubtle
        border.width: 1
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: Theme.spacing.sm
            Text {
                Layout.fillWidth: true
                text: sz.def ? sz.def.label : ""
                color: Theme.fgDim
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.base
                elide: Text.ElideRight
            }
            StepBtn { glyph: "−"; onClicked: settingsStore.setFlyoutSize(sz.def.id, "w", Math.max(280, settingsStore.flyoutSize(sz.def.id, "w", sz.def.w) - 40)) }
            Text {
                Layout.preferredWidth: 44
                text: settingsStore.flyoutSize(sz.def.id, "w", sz.def ? sz.def.w : 0) + "w"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                horizontalAlignment: Text.AlignHCenter
            }
            StepBtn { glyph: "+"; onClicked: settingsStore.setFlyoutSize(sz.def.id, "w", Math.min(1200, settingsStore.flyoutSize(sz.def.id, "w", sz.def.w) + 40)) }
            Item { implicitWidth: 6 }
            StepBtn { visible: sz.def && sz.def.h > 0; glyph: "−"; onClicked: settingsStore.setFlyoutSize(sz.def.id, "h", Math.max(240, settingsStore.flyoutSize(sz.def.id, "h", sz.def.h) - 40)) }
            Text {
                visible: sz.def && sz.def.h > 0
                Layout.preferredWidth: 44
                text: settingsStore.flyoutSize(sz.def.id, "h", sz.def && sz.def.h ? sz.def.h : 0) + "h"
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                horizontalAlignment: Text.AlignHCenter
            }
            StepBtn { visible: sz.def && sz.def.h > 0; glyph: "+"; onClicked: settingsStore.setFlyoutSize(sz.def.id, "h", Math.min(1100, settingsStore.flyoutSize(sz.def.id, "h", sz.def.h) + 40)) }
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
