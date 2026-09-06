// IcsCalendar — ICS feed service and calendar state. Fetches the feeds listed
// in ~/.config/quickshell/calendar.url, parses their VEVENTs, and owns the
// selected date. The UI that reads it lives in CalendarPane.qml, inside the
// day panel.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var icsUrls: []         // ICS feed URLs, one per line in calendar.url
    property var events: []          // array of {start: Date, end: Date, summary, location, allDay: bool}
    property date selectedDate: new Date()

    // ====== Config file: ~/.config/quickshell/calendar.url ======
    // One ICS URL per line; blank lines and #-comments are ignored.
    FileView {
        id: urlFile
        path: Quickshell.env("HOME") + "/.config/quickshell/calendar.url"
        watchChanges: true
        onLoaded: root.icsUrls = root._parseUrlList(text())
        onFileChanged: reload()
    }

    // ====== Periodic fetch ======
    Process {
        id: fetcher
        // All feeds go through one curl call. curl concatenates the response
        // bodies and keeps going past a failing URL, and _parseIcs only looks
        // for VEVENT blocks, so back-to-back VCALENDARs parse correctly.
        command: root.icsUrls.length > 0
            ? ["curl", "-fsSL", "--max-time", "10"].concat(root.icsUrls)
            : []
        running: false
        stdout: StdioCollector {
            id: collector
            onStreamFinished: root._parseIcs(text)
        }
        onExited: (code) => { if (code !== 0) console.warn("calendar fetch failed:", code); }
    }
    Timer {
        interval: settingsStore.calendarFetchInterval * 60000
        running: root.icsUrls.length > 0
        repeat: true
        onTriggered: root.refetch()
    }

    // Fetch as soon as the feed list appears or changes, so editing
    // calendar.url takes effect immediately instead of at the next tick.
    onIcsUrlsChanged: root.refetch()

    function refetch() {
        if (root.icsUrls.length === 0) return;
        fetcher.running = false;
        fetcher.running = true;
    }

    function _parseUrlList(text) {
        if (!text) return [];
        return text.split(/\r?\n/)
            .map(l => l.trim())
            .filter(l => l !== "" && l.indexOf("#") !== 0);
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
}
