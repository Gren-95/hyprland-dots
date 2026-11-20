// Day panel — the calendar and the notification center as one flyout.
//
// Left column is the month grid with the selected day's events under it,
// the right one the quiet switches, now-playing card and notification
// history. Clicking a day shows its events under the grid. Opened from the clock
// (Super+D) or from the bell (Super+N) — both land on the same surface, so
// "what's on today" and "what just happened" are one glance instead of two.
//
// This owns the open/pinned state and the keyboard map; CalendarPane,
// EventsPane and NotifPane are pure views over the IcsCalendar and
// Notifications services.
import QtQuick
import QtQuick.Layouts
import Quickshell

Scope {
    id: root

    property var cal        // IcsCalendar service
    property var notifs     // Notifications service
    property bool open: false
    property bool pinned: false
    property var anchorBar: null
    property var anchorItem: null
    signal navigateNext()
    signal navigatePrev()

    // Column widths, sized from what they hold: seven 48px day cells with
    // their gaps, event rows that read at two lines, notification bodies that
    // wrap at about 40 characters. Each includes its card padding.
    readonly property int calendarWidth: 420
    readonly property int notifWidth: 460
    readonly property int columnGap: Theme.spacing.md
    readonly property int margin: Theme.spacing.md
    readonly property int fitWidth: calendarWidth + notifWidth + columnGap + margin * 2
    // The popup is sized to the calendar plus room for a few events, and
    // stays that size: more events or notifications scroll inside their
    // column instead of growing the popup.
    readonly property int eventsRoom: 180
    readonly property real fitHeight: Math.min(
        root.anchorBar && root.anchorBar.screen ? root.anchorBar.screen.height - 160 : 720,
        dayHeader.implicitHeight + contentCol.spacing + calPane.implicitHeight
            + Theme.spacing.md + eventsRoom + margin * 2)

    // Opening re-centres the calendar on today, so the panel always comes up
    // showing now rather than wherever the month grid was left.
    function openFrom(item) {
        if (item) root.anchorItem = item;
        if (!root.open && root.cal) root.cal.today();
        root.open = true;
    }
    function toggleFrom(item) {
        if (root.open) root.close();
        else root.openFrom(item);
    }
    function close() { root.open = false; }
    // Nav-ring entry point (Ctrl+←/→ cycles between flyouts); keeps whatever
    // anchor the panel already had.
    function openAt(idx) { root.openFrom(null); }

    // Unread count and group expansion follow the panel: reading it here is
    // what marks the history seen.
    Binding {
        target: root.notifs
        property: "panelOpen"
        value: root.open
    }

    BarFlyout {
        id: panel
        parentBar: root.anchorBar
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("daypanel", "w", root.fitWidth)
        cardHeight: settingsStore.flyoutSize("daypanel", "h", root.fitHeight)
        pinned: root.pinned
        onDismissed: root.close()
        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) { root.navigateNext(); e.accepted = true; return; }
            if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) { root.navigatePrev(); e.accepted = true; return; }
            if (!root.cal) return;
            // Everything else is date navigation, driving the calendar column.
            if (e.key === Qt.Key_PageDown) { root.cal.nextMonth(); e.accepted = true; }
            else if (e.key === Qt.Key_PageUp)   { root.cal.prevMonth(); e.accepted = true; }
            else if (e.key === Qt.Key_Left)     { root.cal.shiftDay(-1); e.accepted = true; }
            else if (e.key === Qt.Key_Right)    { root.cal.shiftDay(1);  e.accepted = true; }
            else if (e.key === Qt.Key_Up)       { root.cal.shiftDay(-7); e.accepted = true; }
            else if (e.key === Qt.Key_Down)     { root.cal.shiftDay(7);  e.accepted = true; }
            else if (e.key === Qt.Key_T || e.key === Qt.Key_Home) { root.cal.today(); e.accepted = true; }
        }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: root.margin
            spacing: Theme.spacing.md

            RowLayout {
                id: dayHeader
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                PinButton {
                    pinned: root.pinned
                    onToggled: root.pinned = !root.pinned
                }
                Text {
                    Layout.fillWidth: true
                    // Re-read on open so the title is never yesterday's date.
                    text: root.open ? Qt.formatDate(new Date(), "dddd, d MMMM") : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
                // Balances the pin button so the title stays centered.
                Item { implicitWidth: 22; implicitHeight: 22 }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.columnGap

                ColumnLayout {
                    Layout.preferredWidth: root.calendarWidth
                    Layout.maximumWidth: root.calendarWidth
                    Layout.fillHeight: true
                    spacing: Theme.spacing.md
                    CalendarPane {
                        id: calPane
                        cal: root.cal
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                    }
                    EventsPane {
                        cal: root.cal
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
                NotifPane {
                    notifs: root.notifs
                    Layout.preferredWidth: root.notifWidth
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }
}
