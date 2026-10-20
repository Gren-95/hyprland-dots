// Minimal app launcher for game mode. The Spotlight launcher is a BarFlyout
// (a PopupWindow anchored to the bar window); game mode hides every bar, so
// that popup has no visible parent surface to map against and never appears.
// This is a self-contained overlay window instead — it does not depend on the
// bar, so it opens whether or not game mode is on.
//
// Scope is deliberately small: search and launch applications. No calculator,
// shell actions, hidden-app management or default-app picking (that all lives
// in Spotlight, which is reachable the moment game mode is off).
//
// shell.qml routes the `quickshell:spotlight` shortcut here while game mode is
// active, so Super+R / Alt+space open this with the same muscle memory.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    property bool open: false
    property string query: ""
    property int selectedIndex: 0

    readonly property var filtered: {
        if (!DesktopEntries.applications) return [];
        const all = DesktopEntries.applications.values || [];
        const q = root.query.toLowerCase();
        return all
            .filter(a => !a.noDisplay)
            .filter(a => !settingsStore.isAppHidden(a.id))
            .filter(a => {
                if (!q) return true;
                const name = (a.name || "").toLowerCase();
                const gen = (a.genericName || "").toLowerCase();
                const cmt = (a.comment || "").toLowerCase();
                return name.includes(q) || gen.includes(q) || cmt.includes(q);
            })
            .sort((a, b) => {
                if (q) {
                    const an = (a.name || "").toLowerCase();
                    const bn = (b.name || "").toLowerCase();
                    const aStarts = an.startsWith(q) ? 0 : 1;
                    const bStarts = bn.startsWith(q) ? 0 : 1;
                    if (aStarts !== bStarts) return aStarts - bStarts;
                }
                return (a.name || "").localeCompare(b.name || "");
            });
    }
    readonly property var shown: root.filtered.slice(0, settingsStore.spotlightCap)
    readonly property int totalRows: root.shown.length

    function openLauncher() { root.query = ""; root.selectedIndex = 0; root.open = true; }
    function close() { root.open = false; }
    function toggle() { if (root.open) root.close(); else root.openLauncher(); }
    function activate(i) {
        const item = root.shown[i];
        if (item) item.execute();
        root.close();
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // Open on the focused monitor only, so a multi-monitor setup does
            // not stack one launcher per screen.
            readonly property bool onFocused: Hyprland.focusedMonitor
                && Hyprland.focusedMonitor.name === modelData.name
            visible: root.open && onFocused
            color: "transparent"

            anchors { top: true; left: true; right: true; bottom: true }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.open && onFocused)
                ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Dim backdrop; a click anywhere off the card closes.
            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.bg, 0.35)
                opacity: root.open ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                MouseArea { anchors.fill: parent; onClicked: root.close() }
            }

            HyprlandFocusGrab {
                active: root.open && win.onFocused
                windows: [win]
                onCleared: root.close()
            }

            FocusScope {
                id: cardScope
                anchors.centerIn: parent
                width: 560
                height: Math.max(340, Math.min(win.screen ? win.screen.height - 160 : 600,
                                               contentCol.implicitHeight))
                focus: root.open
                scale: root.open ? 1.0 : 0.96
                opacity: root.open ? 1.0 : 0.0
                transformOrigin: Item.Center
                Behavior on scale   { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                onVisibleChanged: if (visible) Qt.callLater(cardScope.forceActiveFocus)

                Rectangle {
                    anchors.fill: parent
                    radius: 16 * Theme.radiusScale
                    color: Theme.bgAlt
                    border.color: Theme.popupBorder
                    border.width: 1
                }

                Keys.onPressed: (e) => {
                    const n = root.totalRows;
                    if (e.key === Qt.Key_Escape) {
                        root.close(); e.accepted = true;
                    } else if (e.key === Qt.Key_Down) {
                        if (n > 0) root.selectedIndex = Math.min(n - 1, root.selectedIndex + 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Up) {
                        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                        e.accepted = true;
                    } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        root.activate(root.selectedIndex); e.accepted = true;
                    } else if (e.key === Qt.Key_Backspace) {
                        root.query = root.query.slice(0, -1);
                        root.selectedIndex = 0;
                        e.accepted = true;
                    } else if (e.text && e.text.length > 0 && e.text.charCodeAt(0) >= 32) {
                        root.query += e.text;
                        root.selectedIndex = 0;
                        e.accepted = true;
                    }
                }

                ColumnLayout {
                    id: contentCol
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.xl
                    spacing: Theme.spacing.lg

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.md
                        Text {
                            Layout.fillWidth: true
                            text: "Launcher"
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "󰊖"
                            color: Theme.accent.green
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                        }
                    }

                    LauncherSearchBar {
                        Layout.fillWidth: true
                        text: root.query
                        placeholder: "Search apps"
                        countText: root.totalRows > 0 ? String(root.totalRows) : ""
                        onCleared: { root.query = ""; root.selectedIndex = 0; }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: listBox.height + 2
                        radius: 10 * Theme.radiusScale
                        color: Theme.bg
                        border.color: Theme.border
                        border.width: 1
                        clip: true

                        Flickable {
                            id: results
                            anchors.fill: parent
                            anchors.margins: 1
                            contentWidth: width
                            contentHeight: listBox.height
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            ScrollBar.vertical: ThinScrollBar {}

                            NumberAnimation {
                                id: scrollAnim
                                target: results
                                property: "contentY"
                                duration: Theme.duration.normal
                                easing.type: Theme.easing.standard
                            }

                            Item {
                                id: listBox
                                readonly property int pad: Theme.spacing.md
                                width: results.width
                                height: root.totalRows === 0 ? 230 : resultsCol.implicitHeight + pad * 2

                                LauncherSelection {
                                    id: selection
                                    inset: listBox.pad
                                    offsetY: listBox.pad
                                }

                                ColumnLayout {
                                    id: resultsCol
                                    x: listBox.pad
                                    y: listBox.pad
                                    width: parent.width - listBox.pad * 2
                                    spacing: 2
                                    onImplicitHeightChanged: Qt.callLater(contentCol.syncSelection)

                                    Repeater {
                                        id: appsRepeater
                                        model: root.shown
                                        onItemAdded: Qt.callLater(contentCol.syncSelection)
                                        delegate: SpotlightAppRow {
                                            required property var modelData
                                            required property int index
                                            entry: modelData
                                            highlighted: root.selectedIndex === index
                                            Layout.fillWidth: true
                                            onPicked: root.activate(index)
                                            onHovered: root.selectedIndex = index
                                        }
                                    }
                                }

                                LauncherEmptyState {
                                    anchors.centerIn: parent
                                    visible: root.totalRows === 0
                                    title: "No apps found"
                                    subtitle: root.query !== ""
                                        ? "Nothing matches “" + root.query + "”" : ""
                                }
                            }
                        }
                    }

                    LauncherFooter {
                        Layout.fillWidth: true
                        hints: [{ key: "↑↓", label: "navigate" },
                                { key: "↵", label: "launch" },
                                { key: "Esc", label: "close" }]
                    }

                    Connections {
                        target: root
                        function onSelectedIndexChanged() { Qt.callLater(contentCol.syncSelection) }
                    }

                    // Point the selection plate at the highlighted row and keep
                    // that row inside the viewport.
                    function syncSelection() {
                        const idx = root.selectedIndex;
                        const item = idx >= 0 && idx < appsRepeater.count ? appsRepeater.itemAt(idx) : null;
                        selection.target = item;
                        if (!item) return;
                        const top = item.y + listBox.pad;
                        const bottom = top + item.height;
                        if (top < results.contentY) {
                            scrollAnim.to = Math.max(0, top - listBox.pad);
                            scrollAnim.restart();
                        } else if (bottom > results.contentY + results.height) {
                            scrollAnim.to = Math.min(listBox.height - results.height,
                                                     bottom - results.height + listBox.pad);
                            scrollAnim.restart();
                        }
                    }
                }
            }
        }
    }
}
