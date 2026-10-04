// Calendar column of the day panel: a month card (header, nav, grid) and the
// weather card under it. The selected day's events render in EventsPane, the
// column next to this one.
//
// Pure view. Every piece of state (selected date, parsed events, month
// navigation) lives in the IcsCalendar service handed in as `cal`, so the
// pane can be rebuilt or moved without touching the ICS plumbing.
import QtQuick
import QtQuick.Layouts

Item {
    id: pane
    property var cal

    implicitHeight: scroll.naturalHeight

    // Month the grid is showing; a change slides the new month in from the
    // side it was navigated to.
    readonly property int monthIndex: cal
        ? cal.selectedDate.getFullYear() * 12 + cal.selectedDate.getMonth() : 0
    property int _shownMonth: monthIndex
    onMonthIndexChanged: {
        const dir = monthIndex > _shownMonth ? 1 : -1;
        _shownMonth = monthIndex;
        slide.x = dir * 28;
        monthGrid.opacity = 0;
        monthTitle.opacity = 0;
        monthSwap.restart();
    }
    ParallelAnimation {
        id: monthSwap
        NumberAnimation { target: slide; property: "x"; to: 0; duration: Theme.duration.slow; easing.type: Theme.easing.standard }
        NumberAnimation { target: monthGrid; property: "opacity"; to: 1; duration: Theme.duration.slow; easing.type: Theme.easing.standard }
        NumberAnimation { target: monthTitle; property: "opacity"; to: 1; duration: Theme.duration.slow; easing.type: Theme.easing.standard }
    }

    DayScroll {
        id: scroll
        anchors.fill: parent

        WeatherCard {
            Layout.fillWidth: true
            visible: weatherService.ready
        }

        DayCard {
            Layout.fillWidth: true
            title: "Calendar"

            // ====== Month header ======
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                Text {
                    id: monthTitle
                    Layout.fillWidth: true
                    text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "MMMM yyyy") : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xl
                    font.bold: true
                    elide: Text.ElideRight
                }
                NavBtn { glyph: "‹"; onClicked: pane.cal.prevMonth() }
                NavBtn { label: "Today"; onClicked: pane.cal.today() }
                NavBtn { glyph: "›"; onClicked: pane.cal.nextMonth() }
            }

            // ====== Month grid ======
            Item {
                Layout.fillWidth: true
                implicitHeight: monthGrid.implicitHeight

                GridLayout {
                    id: monthGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    columns: 7
                    columnSpacing: Theme.spacing.xs
                    rowSpacing: Theme.spacing.xs
                    transform: Translate { id: slide }

                    Repeater {
                        model: settingsStore.weekStartMonday
                            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                        delegate: Text {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.bottomMargin: Theme.spacing.xs
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
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 44
                            onClicked: pane.cal.selectDay(cellDate.getFullYear(),
                                cellDate.getMonth(), cellDate.getDate())
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "←/→ day · ↑/↓ week · PgUp/PgDn month · T today · Esc close"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xs
                horizontalAlignment: Text.AlignHCenter
                opacity: 0.65
                elide: Text.ElideRight
            }
        }
    }

    component NavBtn: Rectangle {
        id: nav
        property string glyph: ""
        property string label: ""
        signal clicked()
        implicitWidth: nav.label !== "" ? lbl.implicitWidth + Theme.spacing.xl * 2 : 36
        implicitHeight: 36
        radius: 10 * Theme.radiusScale
        color: ma.pressed ? Theme.bgActive : ma.containsMouse ? Theme.bgHover : Theme.bgInset
        border.color: ma.containsMouse ? Theme.borderStrong : Theme.borderSubtle
        border.width: 1
        scale: ma.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }
        Text {
            id: lbl
            anchors.centerIn: parent
            text: nav.label !== "" ? nav.label : nav.glyph
            color: ma.containsMouse ? Theme.fg : Theme.fgMuted
            font.family: Theme.font
            font.pixelSize: nav.label !== "" ? Theme.fontSize.base : Theme.fontSize.xl
            font.bold: nav.label !== ""
            Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }
}
