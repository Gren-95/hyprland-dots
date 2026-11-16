// IcsCalendar — ICS feed service and calendar state. Fetches the feeds listed
// in ~/.config/quickshell/calendar.url, parses their VEVENTs, and owns the
// selected date. The UI that reads it lives in CalendarPane.qml, inside the
// day panel.
import QtQuick
import Quickshell
import Quickshell.Io
import "IcsParse.js" as Ics

Scope {
    id: root

    property var icsUrls: []         // ICS feed URLs, one per line in calendar.url
    property var events: []          // array of {start: Date, end: Date, summary, location, allDay: bool, calIndex: int}
    property date selectedDate: new Date()

    // Per-feed accent colors, indexed by the feed's position in calendar.url,
    // so each subscription reads as its own color in the grid and event rows.
    readonly property var feedColors: [
        Theme.accent.blue,
        Theme.accent.orange,
        Theme.accent.red,
        Theme.accent.green,
        Theme.accent.purple,
        Theme.accent.pink,
        Theme.accent.teal
    ]

    // Marker curl writes after every transfer, used to split the concatenated
    // response back into one chunk per feed.
    readonly property string feedBoundary: "__QS_FEED_BOUNDARY__"

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
        // bodies and keeps going past a failing URL; --write-out appends the
        // boundary marker after every transfer — including failed ones, whose
        // body -f suppresses — so the chunks stay aligned with icsUrls and
        // each event can be attributed to the feed it came from.
        command: root.icsUrls.length > 0
            ? ["curl", "-fsSL", "--max-time", "10",
               "-w", "\n" + root.feedBoundary + "\n"].concat(root.icsUrls)
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
        const chunks = text.split(new RegExp("\\r?\\n" + root.feedBoundary + "\\r?\\n"));
        let all = [];
        for (let i = 0; i < chunks.length; i++)
            all = all.concat(Ics.parseFeed(chunks[i], i));
        // Sort by start ascending
        all.sort((a, b) => a.start - b.start);
        root.events = all;
    }

    // ====== Public API ======
    // Accent color of the feed an event came from.
    function colorFor(calIndex) {
        if (calIndex === undefined || calIndex < 0) return root.feedColors[0];
        return root.feedColors[calIndex % root.feedColors.length];
    }
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
    // Events on the days *after* the selected one, bucketed by day so the
    // events pane can head each bucket with its date instead of repeating it
    // on every row. The selected day is excluded — it already has the column
    // above. Capped at six days so "upcoming" stays a preview, not the year.
    function upcomingByDay() {
        const sel = new Date(root.selectedDate.getFullYear(),
                             root.selectedDate.getMonth(),
                             root.selectedDate.getDate());
        const groups = [];
        const idx = {};
        // root.events is sorted by start, so the buckets come out in order.
        for (const e of root.events) {
            const d = new Date(e.start.getFullYear(), e.start.getMonth(), e.start.getDate());
            if (d <= sel) continue;
            const k = d.getTime();
            if (idx[k] === undefined) {
                if (groups.length >= 6) break;
                idx[k] = groups.length;
                groups.push({ key: k, date: d, events: [] });
            }
            groups[idx[k]].events.push(e);
        }
        return groups;
    }
}
