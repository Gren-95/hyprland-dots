// Events column of the day panel: everything on the day the calendar grid has
// selected, then what's coming up after it.
//
// Split out of CalendarPane so clicking a day has somewhere to put its events
// other than the strip under the month grid — the grid keeps its own column,
// this one fills with whatever that day holds.
//
// Pure view over the IcsCalendar service handed in as `cal`; the selected date
// and the parsed feeds both live over there.
import QtQuick
import QtQuick.Layouts

Item {
    id: pane
    property var cal

    readonly property var dayEvents:
        pane.cal ? pane.cal.eventsOnDay(pane.cal.selectedDate) : []
    readonly property var upcoming: pane.cal ? pane.cal.upcomingByDay() : []
    readonly property bool configured: pane.cal && pane.cal.icsUrls.length > 0
    // Upcoming sits behind a button: this column is about the day you clicked,
    // and tipping the next six days into it buries that day's events.
    property bool showUpcoming: false

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacing.md

        // ====== Header: the selected day, and how much is on it ======
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.md
            Text {
                text: "󰃭"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.xxl
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "dddd") : ""
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.lg
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "d MMMM yyyy") : ""
                    color: Theme.mutedDeep
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.sm
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                visible: pane.dayEvents.length > 0
                implicitWidth: dayCount.implicitWidth + 14
                implicitHeight: 20
                radius: 10 * Theme.radiusScale
                color: Theme.bgDeep
                border.color: Theme.borderSubtle
                border.width: 1
                Text {
                    id: dayCount
                    anchors.centerIn: parent
                    text: pane.dayEvents.length
                    color: Theme.muted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.xs
                    font.bold: true
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.borderStrong }

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
                    Layout.topMargin: 24
                    visible: pane.dayEvents.length === 0
                    text: pane.configured
                        ? "Nothing on this day"
                        : "Set ~/.config/quickshell/calendar.url\nto enable"
                    color: Theme.disabled
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: pane.dayEvents
                    delegate: EventRow {
                        required property var modelData
                        event: modelData
                        accentColor: pane.cal.colorFor(modelData.calIndex)
                        Layout.fillWidth: true
                    }
                }

                // ====== Upcoming, behind a toggle ======
                Rectangle {
                    id: upBtn
                    visible: pane.configured && pane.upcoming.length > 0
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.md
                    implicitHeight: 30
                    radius: 6 * Theme.radiusScale
                    color: upMa.containsMouse ? Theme.bgHover : "transparent"
                    border.color: upMa.containsMouse ? Theme.borderStrong : Theme.border
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing.md
                        anchors.rightMargin: Theme.spacing.md
                        spacing: Theme.spacing.md
                        Text {
                            text: "󰍝"
                            color: pane.showUpcoming || upMa.containsMouse
                                ? Theme.accent.blue : Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                            font.bold: true
                            rotation: pane.showUpcoming ? 0 : -90
                            Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                            Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: pane.showUpcoming ? "Hide upcoming" : "Show upcoming"
                            color: Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
                            font.bold: true
                        }
                        Text {
                            text: pane.upcoming.length + (pane.upcoming.length === 1 ? " day" : " days")
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.xs
                        }
                    }
                    MouseArea {
                        id: upMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pane.showUpcoming = !pane.showUpcoming
                    }
                }

                // One block per day, headed by its date, so the rows below it
                // don't each have to repeat it.
                Repeater {
                    model: pane.showUpcoming ? pane.upcoming : []
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.sm
                        spacing: Theme.spacing.sm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacing.md
                            Text {
                                text: Qt.formatDate(modelData.date, "ddd d MMMM").toUpperCase()
                                color: Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                                font.letterSpacing: 1
                                font.bold: true
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Theme.borderSubtle
                            }
                        }
                        Repeater {
                            model: modelData.events
                            delegate: EventRow {
                                required property var modelData
                                event: modelData
                                accentColor: pane.cal.colorFor(modelData.calIndex)
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }
    }

    component EventRow: Rectangle {
        id: er
        property var event
        property bool showDate: false
        property color accentColor: Theme.accent.blue   // color of the event's feed
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
                    color: er.accentColor
                }
                Text {
                    Layout.fillWidth: true
                    text: er.event ? (er.event.summary || "(no title)") : ""
                    color: Theme.fg
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
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
                    color: er.accentColor
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
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
