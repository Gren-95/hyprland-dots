// Icons & cursors popup: two tabs, each listing every installed theme with
// the same row of samples drawn from it, so packs can be compared side by
// side. Recently applied themes come first, then the rest by name. Enter or
// a click applies the theme (scripts/icon-theme.sh, scripts/cursor-theme.sh,
// through ThemeSource). Opened from the Quick Actions "Icons & cursors" tile.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

Scope {
    id: root

    property bool open: false
    property var anchorBar: null
    property string tab: "icons"
    property int selectedIndex: 0

    readonly property var source: tab === "icons" ? icons : cursors
    readonly property var themes: source.themes

    function toggle() { if (open) close(); else openMenu(); }
    function openMenu() {
        icons.load();
        cursors.load();
        selectedIndex = source.currentIndex();
        open = true;
    }
    function close() { open = false; }
    function switchTab(next) {
        if (next === tab) return;
        tab = next;
        selectedIndex = source.currentIndex();
    }

    ThemeSource {
        id: icons
        script: "icon-theme.sh"
        recentsSetting: "iconThemeRecents"
        parseGet: text => ({ [text.trim()]: "In use" })
    }
    ThemeSource {
        id: cursors
        script: "cursor-theme.sh"
        recentsSetting: "cursorThemeRecents"
        // An XCursor theme serves apps and, unless a Hyprcursor theme is
        // picked, Hyprland too.
        parseGet: text => {
            const t = JSON.parse(text);
            if (t.apps === t.hyprland) return { [t.apps]: "Apps · Hyprland" };
            return { [t.apps]: "Apps", [t.hyprland]: "Hyprland" };
        }
    }
    // Put the keyboard cursor on the theme in use once it is known, and
    // again after an apply reorders the list.
    Connections {
        target: root.source
        function onInUseChanged() { root.selectedIndex = root.source.currentIndex(); }
        function onLoadingChanged() { if (!root.source.loading) root.selectedIndex = root.source.currentIndex(); }
    }

    LazyView {
        shown: root.open
        BarFlyout {
            id: card
            parentBar: root.anchorBar
            open: root.open && root.anchorBar !== null
            cardWidth: 620
            // Sized for the longer tab, so switching tabs does not resize it.
            cardHeight: Math.min(640, 170 + Math.max(1, icons.themes.length, cursors.themes.length) * 84)
            onDismissed: root.open = false
            onKeyPressed: (e) => {
                const n = root.themes.length;
                if (e.key === Qt.Key_Down || e.key === Qt.Key_J) {
                    if (n > 0) root.selectedIndex = (root.selectedIndex + 1) % n;
                } else if (e.key === Qt.Key_Up || e.key === Qt.Key_K) {
                    if (n > 0) root.selectedIndex = (root.selectedIndex - 1 + n) % n;
                } else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab
                           || e.key === Qt.Key_Left || e.key === Qt.Key_Right) {
                    root.switchTab(root.tab === "icons" ? "cursors" : "icons");
                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) {
                    root.source.apply(root.themes[root.selectedIndex]);
                } else {
                    return;
                }
                e.accepted = true;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                Text {
                    Layout.fillWidth: true
                    text: "Icons & cursors"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Theme.spacing.sm
                    LauncherChipButton {
                        glyph: "󰀻"
                        text: "Icons"
                        active: root.tab === "icons"
                        onClicked: root.switchTab("icons")
                    }
                    LauncherChipButton {
                        glyph: "󰇀"
                        text: "Cursors"
                        active: root.tab === "cursors"
                        onClicked: root.switchTab("cursors")
                    }
                }

                Text {
                    text: "INSTALLED"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.letterSpacing: 1
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    RowLayout {
                        anchors.centerIn: parent
                        visible: root.source.loading
                        spacing: Theme.spacing.sm
                        Spinner { color: Theme.accentPrimary }
                        Text {
                            text: root.tab === "icons" ? "Looking for icon themes…" : "Looking for cursor themes…"
                            color: Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.source.loading && root.themes.length === 0
                        text: root.tab === "icons" ? "No icon themes found" : "No cursor themes found"
                        color: Theme.fgMuted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.sm
                    }

                    ListView {
                        id: list
                        anchors.fill: parent
                        visible: !root.source.loading
                        clip: true
                        spacing: Theme.spacing.xs
                        model: root.themes
                        currentIndex: root.selectedIndex
                        boundsBehavior: Flickable.StopAtBounds
                        highlightFollowsCurrentItem: false
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                        ScrollBar.vertical: ThinScrollBar {}

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property string badge: root.source.inUse[modelData.id] ?? ""
                            readonly property bool isCurrent: badge !== ""
                            readonly property bool highlighted: root.selectedIndex === index
                            readonly property string sublabel: modelData.kind === "hyprcursor"
                                ? "Hyprcursor · Hyprland only" + (modelData.comment ? " · " + modelData.comment : "")
                                : modelData.comment
                            width: list.width
                            height: 80
                            radius: 10 * Theme.radiusScale
                            color: row.highlighted ? Theme.bgActive
                                 : (row.isCurrent || rowMa.containsMouse) ? Theme.bgHover : "transparent"
                            border.color: row.highlighted ? Theme.borderStrong : "transparent"
                            border.width: 1
                            scale: rowMa.pressed ? 0.985 : 1.0
                            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                            Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

                            // Accent rail on a theme in use.
                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3
                                height: parent.height - 16
                                radius: 1.5 * Theme.radiusScale
                                color: Theme.accentPrimary
                                opacity: row.isCurrent ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: Theme.duration.fast } }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacing.md
                                anchors.rightMargin: Theme.spacing.md
                                anchors.topMargin: Theme.spacing.sm
                                anchors.bottomMargin: Theme.spacing.sm
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.sm
                                    Text {
                                        text: row.modelData.name
                                        textFormat: Text.PlainText   // external text: never render markup
                                        color: row.isCurrent ? Theme.fg : Theme.fgMuted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.base
                                        font.bold: true
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.sublabel
                                        textFormat: Text.PlainText   // external text: never render markup
                                        color: Theme.mutedDeep
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.xs
                                        elide: Text.ElideRight
                                    }
                                    Spinner {
                                        visible: root.source.applying === row.modelData.id
                                        color: Theme.accentPrimary
                                    }
                                    Text {
                                        visible: row.isCurrent
                                        text: "󰄬 " + row.badge
                                        color: Theme.accentPrimary
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.sm
                                        font.bold: true
                                    }
                                }

                                // The samples: a plain Image on each file, as
                                // in VolumeLine (IconImage drew nothing when its
                                // source arrived through a binding).
                                Row {
                                    spacing: Theme.spacing.md
                                    Repeater {
                                        model: row.modelData.samples
                                        delegate: Image {
                                            required property string modelData
                                            width: 36
                                            height: 36
                                            sourceSize.width: 72
                                            sourceSize.height: 72
                                            source: "file://" + modelData
                                            asynchronous: true
                                            fillMode: Image.PreserveAspectFit
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.selectedIndex = row.index
                                onClicked: root.source.apply(row.modelData)
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "↑↓ move · Tab switch tab · ↵ apply · open apps keep the old theme until restarted"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
