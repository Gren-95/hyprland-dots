import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property string icsUrl: ""
    property var events: []          // array of {start: Date, end: Date, summary, location, allDay: bool}
    property date selectedDate: new Date()
    property bool open: false
    property bool pinned: false
    property var anchorBar: null
    property var anchorItem: null

    // ====== Config file: ~/.config/quickshell/calendar.url ======
    FileView {
        id: urlFile
        path: Quickshell.env("HOME") + "/.config/quickshell/calendar.url"
        watchChanges: true
        onLoaded: root.icsUrl = text().trim()
        onFileChanged: reload()
    }

    // ====== Periodic fetch ======
    Process {
        id: fetcher
        command: root.icsUrl ? ["curl", "-fsSL", "--max-time", "10", root.icsUrl] : []
        running: false
        stdout: StdioCollector {
            id: collector
            onStreamFinished: root._parseIcs(text)
        }
        onExited: (code) => { if (code !== 0) console.warn("calendar fetch failed:", code); }
    }
    Timer {
        interval: settingsStore.calendarFetchInterval * 60000
        running: root.icsUrl !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (root.icsUrl) { fetcher.running = false; fetcher.running = true; } }
    }

    function _parseIcs(text) {
        if (!text) return;
        // Unfold continuation lines (lines starting with space or tab)
        const unfolded = text.replace(/\r?\n[ \t]/g, "");
        const lines = unfolded.split(/\r?\n/);
        const out = [];
        let cur = null;
        for (const line of lines) {
            if (line === "BEGIN:VEVENT") { cur = {}; continue; }
            if (line === "END:VEVENT") {
                if (cur && cur.start) out.push(cur);
                cur = null;
                continue;
            }
            if (!cur) continue;
            const idx = line.indexOf(":");
            if (idx < 0) continue;
            const keyPart = line.slice(0, idx);
            const value = line.slice(idx + 1);
            const key = keyPart.split(";")[0];
            const params = keyPart.split(";").slice(1).join(";");
            if (key === "SUMMARY") cur.summary = _unescape(value);
            else if (key === "LOCATION") cur.location = _unescape(value);
            else if (key === "DESCRIPTION") cur.description = _unescape(value);
            else if (key === "DTSTART") {
                const d = _parseIcsDate(value);
                cur.start = d.date;
                cur.allDay = d.allDay || params.indexOf("VALUE=DATE") >= 0;
            } else if (key === "DTEND") {
                const d = _parseIcsDate(value);
                cur.end = d.date;
            }
        }
        // Sort by start ascending
        out.sort((a, b) => a.start - b.start);
        root.events = out;
    }

    function _unescape(s) {
        return s.replace(/\\n/g, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\");
    }

    function _parseIcsDate(v) {
        // Date-only: YYYYMMDD
        // Datetime UTC: YYYYMMDDTHHMMSSZ
        // Datetime local: YYYYMMDDTHHMMSS
        if (v.length === 8) {
            const y = parseInt(v.slice(0, 4));
            const m = parseInt(v.slice(4, 6)) - 1;
            const d = parseInt(v.slice(6, 8));
            return { date: new Date(y, m, d), allDay: true };
        }
        if (v.length >= 15) {
            const y = parseInt(v.slice(0, 4));
            const m = parseInt(v.slice(4, 6)) - 1;
            const d = parseInt(v.slice(6, 8));
            const hh = parseInt(v.slice(9, 11));
            const mm = parseInt(v.slice(11, 13));
            const ss = parseInt(v.slice(13, 15));
            if (v.endsWith("Z")) return { date: new Date(Date.UTC(y, m, d, hh, mm, ss)), allDay: false };
            return { date: new Date(y, m, d, hh, mm, ss), allDay: false };
        }
        return { date: new Date(NaN), allDay: false };
    }

    // ====== Public API ======
    function eventsOnDay(day) {
        const y = day.getFullYear(), m = day.getMonth(), d = day.getDate();
        return root.events.filter(e => {
            const es = e.start;
            return es.getFullYear() === y && es.getMonth() === m && es.getDate() === d;
        });
    }
    function hasEvents(day) {
        return eventsOnDay(day).length > 0;
    }
    signal navigateNext()
    signal navigatePrev()

    function toggle() {
        open = !open;
        if (open) selectedDate = new Date();
    }
    function close() { open = false; }
    function openAt(idx) {
        open = true;
        selectedDate = new Date();
    }
    function prevMonth() {
        const d = new Date(selectedDate);
        d.setDate(1);
        d.setMonth(d.getMonth() - 1);
        selectedDate = d;
    }
    function nextMonth() {
        const d = new Date(selectedDate);
        d.setDate(1);
        d.setMonth(d.getMonth() + 1);
        selectedDate = d;
    }
    function today() { selectedDate = new Date(); }
    function selectDay(y, m, d) { selectedDate = new Date(y, m, d); }
    function shiftDay(delta) {
        const d = new Date(selectedDate);
        d.setDate(d.getDate() + delta);
        selectedDate = d;
    }
    // Aggregated upcoming events from today onward, capped at 8.
    function upcomingEvents() {
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        return root.events.filter(e => e.start >= today).slice(0, 8);
    }

    // ====== Popup ======
    BarFlyout {
        id: popup
        parentBar: root.anchorBar
        anchorItem: root.anchorItem
        open: root.open && root.anchorBar !== null
        cardWidth: settingsStore.flyoutSize("calendar", "w", 400)
        cardHeight: settingsStore.flyoutSize("calendar", "h", 660)
        pinned: root.pinned
        onDismissed: root.close()
        onKeyPressed: (e) => {
            const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
            if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
            else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                root.navigateNext(); e.accepted = true;
            }
            else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                root.navigatePrev(); e.accepted = true;
            }
            else if (e.key === Qt.Key_PageDown) { root.nextMonth(); e.accepted = true; }
            else if (e.key === Qt.Key_PageUp) { root.prevMonth(); e.accepted = true; }
            else if (e.key === Qt.Key_Left)  { root.shiftDay(-1); e.accepted = true; }
            else if (e.key === Qt.Key_Right) { root.shiftDay(1);  e.accepted = true; }
            else if (e.key === Qt.Key_Up)    { root.shiftDay(-7); e.accepted = true; }
            else if (e.key === Qt.Key_Down)  { root.shiftDay(7);  e.accepted = true; }
            else if (e.key === Qt.Key_T || e.key === Qt.Key_Home) { root.today(); e.accepted = true; }
        }

            // Stacked flyout layout: month header + grid up top, then the
            // selected day's events below (Windows clock-flyout style).
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                    // ====== Month header ======
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.md
                        PinButton {
                            pinned: root.pinned
                            onToggled: root.pinned = !root.pinned
                        }
                        Text {
                            Layout.fillWidth: true
                            text: Qt.formatDate(root.selectedDate, "MMMM yyyy")
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
                        NavBtn { glyph: "‹"; onClicked: root.prevMonth() }
                        NavBtn { glyph: "·"; onClicked: root.today(); wide: false }
                        NavBtn { glyph: "›"; onClicked: root.nextMonth() }
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
                                    const first = new Date(root.selectedDate.getFullYear(),
                                        root.selectedDate.getMonth(), 1);
                                    const offset = settingsStore.weekStartMonday
                                        ? (first.getDay() + 6) % 7 : first.getDay();
                                    return new Date(first.getFullYear(), first.getMonth(),
                                        1 - offset + index);
                                }
                                day: cellDate.getDate()
                                outsideMonth: cellDate.getMonth() !== root.selectedDate.getMonth()
                                isWeekend: settingsStore.weekStartMonday
                                    ? index % 7 >= 5 : (index % 7 === 0 || index % 7 === 6)
                                isToday: {
                                    const t = new Date();
                                    return cellDate.getFullYear() === t.getFullYear() &&
                                        cellDate.getMonth() === t.getMonth() &&
                                        cellDate.getDate() === t.getDate();
                                }
                                isSelected: {
                                    return cellDate.getFullYear() === root.selectedDate.getFullYear() &&
                                        cellDate.getMonth() === root.selectedDate.getMonth() &&
                                        cellDate.getDate() === root.selectedDate.getDate();
                                }
                                eventCount: root.eventsOnDay(cellDate).length
                                Layout.fillWidth: true
                                Layout.preferredHeight: 48
                                onClicked: root.selectDay(cellDate.getFullYear(),
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
                        text: Qt.formatDate(root.selectedDate, "dddd, d MMMM yyyy")
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
                                visible: root.eventsOnDay(root.selectedDate).length === 0
                                text: root.icsUrl === ""
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
                                model: root.eventsOnDay(root.selectedDate)
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
                                visible: root.icsUrl !== "" && upcomingRepeater.count > 0
                                text: "UPCOMING"
                                color: Theme.mutedDeep
                                font.family: Theme.font
                                font.pixelSize: Theme.fontSize.xs
                                font.letterSpacing: 1
                                font.bold: true
                            }
                            Repeater {
                                id: upcomingRepeater
                                model: root.upcomingEvents()
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
