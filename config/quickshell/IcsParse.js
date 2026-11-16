.pragma library
// ICS parsing for IcsCalendar.qml. Plain JavaScript with no QML types, so
// tests/ics-parse.test.js can run it under node.

// Parses one feed's body into events. calIndex is the feed's line number in
// calendar.url. Each event: {start, end, summary, location, description,
// allDay, calIndex}.
function parseFeed(text, calIndex) {
    if (!text) return [];
    // Unfold continuation lines (lines starting with space or tab).
    const unfolded = text.replace(/\r?\n[ \t]/g, "");
    const lines = unfolded.split(/\r?\n/);
    const out = [];
    let cur = null;
    // Components nested inside the event (VALARM and the like) carry their
    // own SUMMARY and DESCRIPTION, such as Google's "This is an event
    // reminder". Only lines directly inside the VEVENT belong to the event.
    let nested = 0;
    for (const line of lines) {
        if (line === "BEGIN:VEVENT") { cur = { calIndex: calIndex }; nested = 0; continue; }
        if (line === "END:VEVENT") {
            if (cur && cur.start) out.push(cur);
            cur = null;
            continue;
        }
        if (!cur) continue;
        if (line.indexOf("BEGIN:") === 0) { nested++; continue; }
        if (line.indexOf("END:") === 0) { nested = Math.max(0, nested - 1); continue; }
        if (nested > 0) continue;
        const idx = line.indexOf(":");
        if (idx < 0) continue;
        const keyPart = line.slice(0, idx);
        const value = line.slice(idx + 1);
        const key = keyPart.split(";")[0];
        const params = keyPart.split(";").slice(1).join(";");
        if (key === "SUMMARY") cur.summary = unescapeText(value);
        else if (key === "LOCATION") cur.location = unescapeText(value);
        else if (key === "DESCRIPTION") cur.description = unescapeText(value);
        else if (key === "DTSTART") {
            const d = parseDate(value);
            cur.start = d.date;
            cur.allDay = d.allDay || params.indexOf("VALUE=DATE") >= 0;
        } else if (key === "DTEND") {
            cur.end = parseDate(value).date;
        }
    }
    return out;
}

function unescapeText(s) {
    return s.replace(/\\n/gi, "\n").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\");
}

// Date-only YYYYMMDD, UTC YYYYMMDDTHHMMSSZ, or floating/local YYYYMMDDTHHMMSS.
function parseDate(v) {
    const y = parseInt(v.slice(0, 4), 10);
    const m = parseInt(v.slice(4, 6), 10) - 1;
    const d = parseInt(v.slice(6, 8), 10);
    if (v.length === 8) return { date: new Date(y, m, d), allDay: true };
    if (v.length >= 15) {
        const hh = parseInt(v.slice(9, 11), 10);
        const mm = parseInt(v.slice(11, 13), 10);
        const ss = parseInt(v.slice(13, 15), 10);
        if (v.endsWith("Z")) return { date: new Date(Date.UTC(y, m, d, hh, mm, ss)), allDay: false };
        return { date: new Date(y, m, d, hh, mm, ss), allDay: false };
    }
    return { date: new Date(NaN), allDay: false };
}
