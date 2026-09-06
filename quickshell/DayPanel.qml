// Day panel — the calendar and the notification center as one flyout.
//
// Left column is the month grid and its events; right column is the
// now-playing card and the notification history. Opened from the clock
// (Super+D) or from the bell (Super+N) — both land on the same surface, so
// "what's on today" and "what just happened" are one glance instead of two.
//
// This owns the open/pinned state and the keyboard map; CalendarPane and
// NotifPane are pure views over the IcsCalendar and Notifications services.
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

    // Width given to the calendar column; the notification column takes the
    // rest of the card.
    readonly property int calendarWidth: 400

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
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("daypanel", "w", 860)
        cardHeight: settingsStore.flyoutSize("daypanel", "h", 660)
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

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing.lg
            spacing: Theme.spacing.lg

            CalendarPane {
                cal: root.cal
                pinned: root.pinned
                onPinToggled: root.pinned = !root.pinned
                Layout.preferredWidth: root.calendarWidth
                Layout.fillHeight: true
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: Theme.border
            }

            NotifPane {
                notifs: root.notifs
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }
}
