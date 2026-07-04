// Windows-style hidden-tray chevron. Sits before the tray; its flyout hosts
// (a) tray apps placed in "overflow" and (b) launcher rows for bar modules
// placed in "overflow" — clicking a module row opens that module's flyout
// re-anchored to this chevron (via openTab(tab, from) / flyoutAnchor).
// Only visible when something is actually in overflow.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: chev
    property var parentBar
    property bool popupOpen: false
    // Open tray context menus inside the flyout; while any is open the
    // flyout pins itself so the focus grab doesn't dismiss it (the menu is
    // a separate window and would be destroyed mid-use).
    property int menusOpen: 0

    // Module entries wired from shell.qml:
    //   { id, glyph: () => string, color: () => color, label,
    //     when?: () => bool, open: (anchorItem) => void }
    // glyph/color are thunks so the row live-tracks the hidden bar icon's
    // state (battery %, wifi strength...) — reading notifiable properties
    // inside the binding keeps it reactive.
    property var entries: []

    readonly property var overflowEntries: entries.filter(e =>
        settingsStore.placement(e.id) === "overflow" && (!e.when || e.when()))
    readonly property var overflowTray: {
        const list = (SystemTray.items && SystemTray.items.values) || [];
        return list.filter(t => settingsStore.trayPlacementOf(t.id || t.title) === "overflow");
    }

    visible: overflowEntries.length > 0 || overflowTray.length > 0
    onVisibleChanged: if (!visible) popupOpen = false

    Layout.fillHeight: true
    implicitWidth: visible ? 24 : 0

    Text {
        anchors.centerIn: parent
        text: "󰅃"
        color: chev.popupOpen ? Theme.accentPrimary : Theme.fgMuted
        font.family: Theme.font
        font.pixelSize: Theme.fontSize.lg
        rotation: chev.popupOpen ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
    }

    HoverHandler { id: chevHover }
    BarTooltip {
        bar: chev.parentBar
        target: chev
        text: "Hidden items"
        active: chevHover.hovered && !chev.popupOpen
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: chev.popupOpen = !chev.popupOpen
    }

    BarFlyout {
        parentBar: chev.parentBar
        anchorItem: chev
        open: chev.popupOpen
        pinned: chev.menusOpen > 0
        cardWidth: 300
        cardHeight: content.implicitHeight + 2 * Theme.spacing.lg
        onDismissed: chev.popupOpen = false

        ColumnLayout {
            id: content
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.sm

            // Overflow tray icons in a row
            Text {
                visible: chev.overflowTray.length > 0
                text: "TRAY"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.letterSpacing: 1
                font.bold: true
            }
            RowLayout {
                visible: chev.overflowTray.length > 0
                Layout.fillWidth: true
                spacing: Theme.spacing.sm
                Repeater {
                    model: chev.overflowTray
                    delegate: TrayItem {
                        required property var modelData
                        item: modelData
                        anchorWindow: chev.parentBar
                        implicitHeight: 28
                        onMenuOpenChanged: chev.menusOpen += menuOpen ? 1 : -1
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Overflow module rows
            Text {
                visible: chev.overflowEntries.length > 0
                text: "MODULES"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                font.letterSpacing: 1
                font.bold: true
            }
            Repeater {
                model: chev.overflowEntries
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 8
                    color: rowMa.containsMouse ? Theme.bgHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: Theme.spacing.md
                        Text {
                            text: modelData.glyph()
                            color: modelData.color()
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.md
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            elide: Text.ElideRight
                        }
                        Text {
                            text: "󰅂"
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                        }
                    }
                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Close the chevron flyout, then open the module's
                        // flyout anchored here (PopupManager close-then-open).
                        onClicked: {
                            chev.popupOpen = false;
                            modelData.open(chev);
                        }
                    }
                }
            }
        }
    }
}
