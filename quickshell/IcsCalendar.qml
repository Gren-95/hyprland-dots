import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

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
        interval: 600000  // 10 minutes
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

    // ====== Popup ======
    PopupWindow {
        id: popup
        visible: root.open && root.anchorBar !== null
        color: "transparent"
        anchor.window: root.anchorBar
        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 0
        implicitWidth: 320
        implicitHeight: gridCol.implicitHeight + 24

        SproutBg { anchors.fill: parent; fillColor: "#292524"; borderColor: "#78716c"; tailX: width / 2 }
        Item {
            anchors.fill: parent
            focus: root.open
            Keys.onPressed: (e) => {
                const ctrl = (e.modifiers & Qt.ControlModifier) !== 0;
                if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
                else if (ctrl && (e.key === Qt.Key_Right || e.key === Qt.Key_L)) {
                    root.navigateNext(); e.accepted = true;
                }
                else if (ctrl && (e.key === Qt.Key_Left || e.key === Qt.Key_H)) {
                    root.navigatePrev(); e.accepted = true;
                }
                else if (e.key === Qt.Key_Left) { root.prevMonth(); e.accepted = true; }
                else if (e.key === Qt.Key_Right) { root.nextMonth(); e.accepted = true; }
                else if (e.key === Qt.Key_T) { root.today(); e.accepted = true; }
            }

            ColumnLayout {
                id: gridCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    PinButton {
                        pinned: root.pinned
                        onToggled: root.pinned = !root.pinned
                    }
                    NavBtn {
                        glyph: "‹"
                        onClicked: root.prevMonth()
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.selectedDate, "MMMM yyyy")
                        color: "#f5f5f4"
                        font.family: "FiraCode Nerd Font"
                        font.pixelSize: 14
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    NavBtn {
                        glyph: "›"
                        onClicked: root.nextMonth()
                    }
                    NavBtn {
                        glyph: "Today"
                        wide: true
                        onClicked: root.today()
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 7
                    columnSpacing: 0
                    rowSpacing: 2

                    Repeater {
                        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData
                            color: "#78716c"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 10
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
                                // Adjust so Monday is column 0
                                const offset = (first.getDay() + 6) % 7;
                                return new Date(first.getFullYear(), first.getMonth(),
                                    1 - offset + index);
                            }
                            day: cellDate.getDate()
                            outsideMonth: cellDate.getMonth() !== root.selectedDate.getMonth()
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
                            hasEvent: root.hasEvents(cellDate)
                            Layout.fillWidth: true
                            onClicked: root.selectDay(cellDate.getFullYear(),
                                cellDate.getMonth(), cellDate.getDate())
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: "#44403c" }

                Text {
                    text: Qt.formatDate(root.selectedDate, "dddd, dd MMMM")
                    color: "#a8a29e"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.eventsOnDay(root.selectedDate).length === 0
                    text: root.icsUrl === "" ? "Set ~/.config/quickshell/calendar.url to enable"
                        : "No events"
                    color: "#78716c"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: root.eventsOnDay(root.selectedDate)
                        delegate: EventRow {
                            required property var modelData
                            event: modelData
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }

    HyprlandFocusGrab {
        active: root.open && !root.pinned
        windows: [popup]
        onCleared: root.close()
    }

    component NavBtn: Rectangle {
        id: nav
        property string glyph: ""
        property bool wide: false
        signal clicked()
        implicitWidth: nav.wide ? lbl.implicitWidth + 14 : 24
        implicitHeight: 22
        radius: 4
        color: ma.containsMouse ? "#292524" : "transparent"
        border.color: nav.wide ? "#44403c" : "transparent"
        border.width: nav.wide ? 1 : 0
        Text {
            id: lbl
            anchors.centerIn: parent
            text: nav.glyph
            color: "#d6d3d1"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: nav.wide ? 10 : 14
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
        property bool isToday: false
        property bool isSelected: false
        property bool hasEvent: false
        signal clicked()
        implicitHeight: 28
        radius: 4
        color: cell.isSelected ? "#3b3531"
             : (cellMa.containsMouse ? "#262220" : "transparent")
        border.color: cell.isToday ? "#3b82f6" : "transparent"
        border.width: cell.isToday ? 1 : 0

        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: cell.hasEvent ? -2 : 0
            text: cell.day
            color: cell.outsideMonth ? "#57534e"
                 : cell.isToday ? "#fafaf9"
                 : "#e7e5e4"
            font.family: "FiraCode Nerd Font"
            font.pixelSize: 11
            font.bold: cell.isToday || cell.isSelected
        }
        Rectangle {
            visible: cell.hasEvent
            width: 4; height: 4; radius: 2
            color: cell.outsideMonth ? "#78716c" : "#3b82f6"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
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
        implicitHeight: erCol.implicitHeight + 10
        radius: 4
        color: "#231f1d"
        border.color: "#3a3633"
        border.width: 1

        ColumnLayout {
            id: erCol
            anchors.fill: parent
            anchors.margins: 6
            spacing: 1
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.preferredWidth: 3
                    Layout.preferredHeight: 14
                    radius: 1.5
                    color: "#3b82f6"
                }
                Text {
                    Layout.fillWidth: true
                    text: er.event ? (er.event.summary || "(no title)") : ""
                    color: "#f5f5f4"
                    elide: Text.ElideRight
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }
                Text {
                    text: er.event && er.event.allDay ? "all day"
                        : er.event ? Qt.formatTime(er.event.start, "HH:mm") : ""
                    color: "#a8a29e"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 10
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 9
                visible: er.event && er.event.location
                text: er.event && er.event.location ? "@ " + er.event.location : ""
                color: "#a8a29e"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }
    }
}
