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

    implicitHeight: scroll.naturalHeight

    DayScroll {
        id: scroll
        anchors.fill: parent

        // ====== The selected day, and how much is on it ======
        DayCard {
            Layout.fillWidth: true
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.lg
                Text {
                    text: "󰃭"
                    color: Theme.accentPrimary
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.hero
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "dddd") : ""
                        color: Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.xl
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: pane.cal ? Qt.formatDate(pane.cal.selectedDate, "d MMMM yyyy") : ""
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        elide: Text.ElideRight
                    }
                }
                Rectangle {
                    visible: pane.dayEvents.length > 0
                    implicitWidth: Math.max(28, dayCount.implicitWidth + 16)
                    implicitHeight: 28
                    radius: height / 2
                    color: Theme.alpha(Theme.accentPrimary, 0.16)
                    border.color: Theme.alpha(Theme.accentPrimary, 0.45)
                    border.width: 1
                    Text {
                        id: dayCount
                        anchors.centerIn: parent
                        text: pane.dayEvents.length
                        color: Theme.accentPrimary
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.base
                        font.bold: true
                    }
                }
            }
        }

        // ====== Events of the day ======
        DayCard {
            Layout.fillWidth: true
            title: "Events"
            spacing: Theme.spacing.md

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.md
                Layout.bottomMargin: Theme.spacing.md
                visible: pane.dayEvents.length === 0
                text: pane.configured
                    ? "Nothing on this day"
                    : "Set ~/.config/quickshell/calendar.url\nto enable"
                color: Theme.mutedDeep
                font.family: Theme.font
                font.pixelSize: Theme.fontSize.md
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
        }

        // ====== Upcoming, behind a toggle ======
        DayCard {
            Layout.fillWidth: true
            visible: pane.configured && pane.upcoming.length > 0
            title: "Upcoming"

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Rectangle {
                    id: upBtn
                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: 10 * Theme.radiusScale
                    color: upMa.pressed ? Theme.bgActive : upMa.containsMouse ? Theme.bgHover : Theme.bgInset
                    border.color: pane.showUpcoming ? Theme.accentPrimary : upMa.containsMouse ? Theme.borderStrong : Theme.borderSubtle
                    border.width: 1
                    scale: upMa.pressed ? 0.98 : 1.0
                    Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }
                    Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spacing.lg
                        anchors.rightMargin: Theme.spacing.lg
                        spacing: Theme.spacing.md
                        Text {
                            text: "󰅀"
                            color: pane.showUpcoming ? Theme.accentPrimary : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.lg
                            rotation: pane.showUpcoming ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                            Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: pane.showUpcoming ? "Hide upcoming" : "Show upcoming"
                            color: Theme.fgMuted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            font.bold: true
                        }
                        Text {
                            text: pane.upcoming.length + (pane.upcoming.length === 1 ? " day" : " days")
                            color: Theme.mutedDeep
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.sm
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

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: pane.showUpcoming ? upCol.implicitHeight + Theme.spacing.lg : 0
                    clip: true
                    opacity: pane.showUpcoming ? 1.0 : 0.0
                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                    Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }

                    // One block per day, headed by its date, so the rows
                    // below it don't each have to repeat it.
                    ColumnLayout {
                        id: upCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: Theme.spacing.lg
                        spacing: Theme.spacing.lg

                        Repeater {
                            model: pane.upcoming
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacing.md

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacing.md
                                    Text {
                                        text: Qt.formatDate(modelData.date, "ddd d MMMM").toUpperCase()
                                        color: Theme.muted
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontSize.sm
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
        }
    }

    // One event: title, time and place, with a chevron and a reveal for the
    // description when the feed carries one.
    component EventRow: Rectangle {
        id: er
        property var event
        property color accentColor: Theme.accent.blue   // color of the event's feed
        property bool expanded: false
        readonly property bool hasDetail: !!(er.event && er.event.description)

        implicitHeight: erCol.implicitHeight
        radius: 10 * Theme.radiusScale
        clip: true
        color: er.hasDetail && erMa.containsMouse ? Theme.bgHover : Theme.bgInset
        border.color: er.expanded ? Theme.borderStrong : Theme.borderSubtle
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.duration.fast } }

        ColumnLayout {
            id: erCol
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(52, erText.implicitHeight + Theme.spacing.lg * 2)
                scale: er.hasDetail && erMa.pressed ? 0.985 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.duration.fast; easing.type: Theme.easing.standard } }

                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: parent.height - 18
                    radius: 1.5 * Theme.radiusScale
                    color: er.accentColor
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.xl
                    anchors.rightMargin: Theme.spacing.lg
                    spacing: Theme.spacing.md
                    ColumnLayout {
                        id: erText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
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
                            font.pixelSize: Theme.fontSize.base
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: !!(er.event && er.event.location)
                            text: er.event && er.event.location ? "󰍎  " + er.event.location : ""
                            color: Theme.muted
                            font.family: Theme.font
                            font.pixelSize: Theme.fontSize.base
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: er.hasDetail
                        text: "󰅀"
                        color: er.expanded || erMa.containsMouse ? Theme.accentPrimary : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: Theme.fontSize.lg
                        rotation: er.expanded ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.duration.normal; easing.type: Theme.easing.standard } }
                        Behavior on color    { ColorAnimation  { duration: Theme.duration.fast } }
                    }
                }
            }

            Item {
                id: reveal
                Layout.fillWidth: true
                Layout.preferredHeight: er.expanded && er.hasDetail ? detail.implicitHeight + Theme.spacing.lg : 0
                clip: true
                opacity: er.expanded ? 1.0 : 0.0
                Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.duration.slow; easing.type: Theme.easing.standard } }
                Behavior on opacity { NumberAnimation { duration: Theme.duration.normal } }
                Text {
                    id: detail
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.spacing.xl
                    anchors.rightMargin: Theme.spacing.lg
                    text: er.event && er.event.description ? er.event.description : ""
                    color: Theme.fgMuted
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize.base
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    maximumLineCount: 12
                    elide: Text.ElideRight
                }
            }
        }

        MouseArea {
            id: erMa
            anchors.fill: parent
            enabled: er.hasDetail
            hoverEnabled: true
            cursorShape: er.hasDetail ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: er.expanded = !er.expanded
        }
    }
}
