// Calendar column of the day panel: month header, weather, month grid. The
// selected day's events render in EventsPane, the column next to this one.
//
// Pure view. Every piece of state (selected date, parsed events, month
// navigation) lives in the IcsCalendar service handed in as `cal`, so the
// pane can be rebuilt or moved without touching the ICS plumbing.
import QtQuick
import QtQuick.Layouts

Item {
    id: pane
    property var cal
    // The pin sits here because this pane is the panel's leading edge; the
    // panel owns the actual state.
    property bool pinned: false
    signal pinToggled()

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing.md

        // ====== Month header ======
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            PinButton {
                pinned: pane.pinned
                onToggled: pane.pinToggled()
            }
            Text {
                Layout.fillWidth: true
                text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "MMMM yyyy") : ""
                color: Theme.fg
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xl
                font.bold: true
                elide: Text.ElideRight
            }
            NavBtn { glyph: "‹"; onClicked: pane.cal.prevMonth() }
            NavBtn { glyph: "·"; onClicked: pane.cal.today(); wide: false }
            NavBtn { glyph: "›"; onClicked: pane.cal.nextMonth() }
        }

        // ====== Weather ======
        // Under the header rather than in it: the header row is already
        // title plus four controls, and the reading has more to say than
        // fits between them.
        WeatherCard {
            Layout.fillWidth: true
            visible: weatherService.ready
        }

        GridLayout {
            Layout.fillWidth: true
            // Takes the height the events strip used to occupy, so the cells
            // grow into it instead of leaving a gap above the hint line.
            Layout.fillHeight: true
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            Repeater {
                model: settingsStore.weekStartMonday
                    ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                delegate: Text {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData
                    color: (settingsStore.weekStartMonday ? index >= 5 : (index === 0 || index === 6))
                        ? Theme.disabled : Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Repeater {
                model: 42
                delegate: DayCell {
                    required property int index
                    readonly property date cellDate: {
                        const sel = pane.cal ? pane.cal.selectedDate : new Date();
                        const first = new Date(sel.getFullYear(), sel.getMonth(), 1);
                        const offset = settingsStore.weekStartMonday
                            ? (first.getDay() + 6) % 7 : first.getDay();
                        return new Date(first.getFullYear(), first.getMonth(),
                            1 - offset + index);
                    }
                    day: cellDate.getDate()
                    outsideMonth: pane.cal
                        ? cellDate.getMonth() !== pane.cal.selectedDate.getMonth() : false
                    isWeekend: settingsStore.weekStartMonday
                        ? index % 7 >= 5 : (index % 7 === 0 || index % 7 === 6)
                    isToday: {
                        const t = new Date();
                        return cellDate.getFullYear() === t.getFullYear() &&
                            cellDate.getMonth() === t.getMonth() &&
                            cellDate.getDate() === t.getDate();
                    }
                    isSelected: {
                        if (!pane.cal) return false;
                        const sel = pane.cal.selectedDate;
                        return cellDate.getFullYear() === sel.getFullYear() &&
                            cellDate.getMonth() === sel.getMonth() &&
                            cellDate.getDate() === sel.getDate();
                    }
                    readonly property var dayEvents: pane.cal ? pane.cal.eventsOnDay(cellDate) : []
                    eventCount: dayEvents.length
                    eventColors: dayEvents.slice(0, 3)
                        .map(e => pane.cal.colorFor(e.calIndex))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
                    onClicked: pane.cal.selectDay(cellDate.getFullYear(),
                        cellDate.getMonth(), cellDate.getDate())
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "←/→ day · ↑/↓ week · PgUp/PgDn month · T today · Esc close"
            color: Theme.disabled
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.xs
        }
    }

    component NavBtn: Rectangle {
        id: nav
        property string glyph: ""
        property bool wide: false
        signal clicked()
        implicitWidth: nav.wide ? lbl.implicitWidth + 14 : 24
        implicitHeight: 26
        radius: 4 * Theme.radiusScale
        color: ma.containsMouse ? Theme.bgAlt : "transparent"
        border.color: nav.wide ? Theme.borderStrong : "transparent"
        border.width: nav.wide ? 1 : 0
        Text {
            id: lbl
            anchors.centerIn: parent
            text: nav.glyph
            color: Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: nav.wide ? Theme.fontSize.sm : Theme.fontSize.lg
            font.bold: nav.wide
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }

    component DayCell: Rectangle {
        id: cell
        property int day: 0
        property bool outsideMonth: false
        property bool isWeekend: false
        property bool isToday: false
        property bool isSelected: false
        property int eventCount: 0
        property var eventColors: []   // feed color per dot, up to 3
        readonly property bool hasEvent: eventCount > 0
        signal clicked()
        implicitHeight: 48
        radius: 8 * Theme.radiusScale
        color: cell.isSelected ? Theme.bgActive
             : (cellMa.containsMouse ? Theme.bgHover : "transparent")
        border.color: cell.isSelected ? Theme.accentPrimary
                    : cell.isToday ? Theme.accent.blue
                    : "transparent"
        border.width: (cell.isSelected || cell.isToday) ? 2 : 0
        scale: cell.isSelected ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 6
            text: cell.day
            color: cell.outsideMonth ? Theme.border
                 : cell.isToday ? Theme.fg
                 : cell.isWeekend ? Theme.muted
                 : Theme.fgDim
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.lg
            font.bold: cell.isToday || cell.isSelected
        }
        // Event indicator dots (up to 3, then "+N")
        RowLayout {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 5
            spacing: 2
            visible: cell.hasEvent
            Repeater {
                model: cell.eventColors
                delegate: Rectangle {
                    required property var modelData
                    width: 4; height: 4; radius: 2 * Theme.radiusScale
                    color: cell.outsideMonth ? Theme.border : modelData
                }
            }
            Text {
                visible: cell.eventCount > 3
                text: "+" + (cell.eventCount - 3)
                color: cell.outsideMonth ? Theme.border : Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: 7
                font.bold: true
            }
        }

        MouseArea {
            id: cellMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.clicked()
        }
    }

}
