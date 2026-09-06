// Calendar column of the day panel: month header, month grid, then the
// selected day's events followed by what's coming up.
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
            Text {
                visible: weatherService.ready
                text: weatherService.glyph + " " + weatherService.display
                color: Theme.fgMuted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
            }
            NavBtn { glyph: "‹"; onClicked: pane.cal.prevMonth() }
            NavBtn { glyph: "·"; onClicked: pane.cal.today(); wide: false }
            NavBtn { glyph: "›"; onClicked: pane.cal.nextMonth() }
        }

        GridLayout {
            Layout.fillWidth: true
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
                    eventCount: pane.cal ? pane.cal.eventsOnDay(cellDate).length : 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    onClicked: pane.cal.selectDay(cellDate.getFullYear(),
                        cellDate.getMonth(), cellDate.getDate())
                }
            }
        }

        // ====== Divider between grid and events ======
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.border
        }

        // ====== Events for selected day + upcoming ======
        Text {
            text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "dddd, d MMMM yyyy") : ""
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: Theme.fontSize.md
            font.bold: true
        }

        Flickable {
            id: eventsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: eventsCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: eventsCol
                width: eventsFlick.width
                spacing: Theme.spacing.sm

                Text {
                    Layout.fillWidth: true
                    visible: pane.cal && pane.cal.eventsOnDay(pane.cal.selectedDate).length === 0
                    text: (pane.cal && pane.cal.icsUrls.length === 0)
                        ? "Set ~/.config/quickshell/calendar.url\nto enable"
                        : "No events"
                    color: Theme.disabled
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    horizontalAlignment: Text.AlignHCenter
                    Layout.topMargin: 16
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: pane.cal ? pane.cal.eventsOnDay(pane.cal.selectedDate) : []
                    delegate: EventRow {
                        required property var modelData
                        event: modelData
                        Layout.fillWidth: true
                    }
                }

                // Upcoming section (only shown if today has nothing
                // and the selected day is today)
                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    visible: pane.cal && pane.cal.icsUrls.length > 0 && upcomingRepeater.count > 0
                    text: "UPCOMING"
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.letterSpacing: 1
                    font.bold: true
                }
                Repeater {
                    id: upcomingRepeater
                    model: pane.cal ? pane.cal.upcomingEvents() : []
                    delegate: EventRow {
                        required property var modelData
                        event: modelData
                        showDate: true
                        Layout.fillWidth: true
                    }
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
                model: Math.min(cell.eventCount, 3)
                delegate: Rectangle {
                    width: 4; height: 4; radius: 2 * Theme.radiusScale
                    color: cell.outsideMonth ? Theme.border
                         : cell.isSelected ? Theme.accentPrimary
                         : Theme.accent.blue
                }
            }
            Text {
                visible: cell.eventCount > 3
                text: "+" + (cell.eventCount - 3)
                color: cell.outsideMonth ? Theme.border : Theme.accent.blue
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

    component EventRow: Rectangle {
        id: er
        property var event
        property bool showDate: false
        implicitHeight: erCol.implicitHeight + 14
        radius: 6 * Theme.radiusScale
        color: Theme.bgHover
        border.color: Theme.border
        border.width: 1

        ColumnLayout {
            id: erCol
            anchors.fill: parent
            anchors.margins: Theme.spacing.md
            spacing: 3
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.md
                Rectangle {
                    Layout.preferredWidth: 3
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                    radius: 1.5 * Theme.radiusScale
                    color: Theme.accent.blue
                }
                Text {
                    Layout.fillWidth: true
                    text: er.event ? (er.event.summary || "(no title)") : ""
                    color: Theme.fg
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.md
                    font.bold: true
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 11
                spacing: Theme.spacing.md
                Text {
                    text: {
                        if (!er.event) return "";
                        if (er.event.allDay) return "all day";
                        const start = Qt.formatTime(er.event.start, "HH:mm");
                        const end = er.event.end ? Qt.formatTime(er.event.end, "HH:mm") : "";
                        return end ? start + "–" + end : start;
                    }
                    color: Theme.accent.blue
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    font.bold: true
                }
                Text {
                    visible: er.showDate && er.event
                    text: er.event ? Qt.formatDate(er.event.start, "ddd d MMM") : ""
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                }
                Item { Layout.fillWidth: true }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 11
                visible: !!(er.event && er.event.location)
                text: er.event && er.event.location ? "󰍎  " + er.event.location : ""
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.sm
                elide: Text.ElideRight
            }
        }
    }
}
