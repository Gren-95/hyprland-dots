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
        if (key === "UID") cur.uid = value;
        else if (key === "RRULE") cur.rrule = parseRrule(value);
        else if (key === "EXDATE") {
            cur.exdates = (cur.exdates || []).concat(value.split(",").map(v => parseDate(v).date.getTime()));
        } else if (key === "RECURRENCE-ID") cur.recurrenceId = parseDate(value).date.getTime();
        else if (key === "SUMMARY") cur.summary = unescapeText(value);
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

// ====== Recurrence ======

const WEEKDAYS = { SU: 0, MO: 1, TU: 2, WE: 3, TH: 4, FR: 5, SA: 6 };
const DAY_MS = 86400000;
// Upper bound on generated occurrences per event, so a malformed rule can
// never loop for long.
const MAX_STEPS = 5000;

// "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20270101T000000Z" -> object.
// BYDAY entries keep an optional ordinal: "-1SU" -> {n: -1, day: 0}.
function parseRrule(value) {
    const r = { freq: "", interval: 1, count: 0, until: null, byDay: [], byMonthDay: [], byMonth: [] };
    for (const part of value.split(";")) {
        const eq = part.indexOf("=");
        if (eq < 0) continue;
        const k = part.slice(0, eq), v = part.slice(eq + 1);
        if (k === "FREQ") r.freq = v;
        else if (k === "INTERVAL") r.interval = Math.max(1, parseInt(v, 10) || 1);
        else if (k === "COUNT") r.count = parseInt(v, 10) || 0;
        else if (k === "UNTIL") r.until = parseDate(v).date.getTime();
        else if (k === "BYDAY") r.byDay = v.split(",").map(d => {
            const m = /^([+-]?\d+)?([A-Z]{2})$/.exec(d);
            return m ? { n: m[1] ? parseInt(m[1], 10) : 0, day: WEEKDAYS[m[2]] } : null;
        }).filter(d => d && d.day !== undefined);
        else if (k === "BYMONTHDAY") r.byMonthDay = v.split(",").map(x => parseInt(x, 10)).filter(isFinite);
        else if (k === "BYMONTH") r.byMonth = v.split(",").map(x => parseInt(x, 10) - 1).filter(isFinite);
    }
    return r;
}

// Same wall-clock time as `base` on the given calendar day, so DST changes do
// not shift recurring events by an hour.
function atDay(base, y, m, d) {
    return new Date(y, m, d, base.getHours(), base.getMinutes(), base.getSeconds());
}

// Days in a month matching BYDAY entries, honouring ordinals (2MO, -1FR).
function monthDaysForByDay(y, m, byDay) {
    const last = new Date(y, m + 1, 0).getDate();
    const days = [];
    for (const bd of byDay) {
        const matches = [];
        for (let d = 1; d <= last; d++) if (new Date(y, m, d).getDay() === bd.day) matches.push(d);
        if (bd.n === 0) days.push(...matches);
        else {
            const pick = bd.n > 0 ? matches[bd.n - 1] : matches[matches.length + bd.n];
            if (pick) days.push(pick);
        }
    }
    return days;
}

// Candidate start dates of one period (a day, week, month or year), in order.
function periodCandidates(start, r, step) {
    const y = start.getFullYear(), m = start.getMonth(), d = start.getDate();
    switch (r.freq) {
    case "DAILY":
        return [atDay(start, y, m, d + step * r.interval)];
    case "WEEKLY": {
        const weekStart = new Date(y, m, d - start.getDay() + 7 * step * r.interval);
        const days = r.byDay.length ? r.byDay.map(b => b.day) : [start.getDay()];
        return days.slice().sort((a, b) => a - b).map(wd =>
            atDay(start, weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + wd));
    }
    case "MONTHLY": {
        const first = new Date(y, m + step * r.interval, 1);
        const yy = first.getFullYear(), mm = first.getMonth();
        const last = new Date(yy, mm + 1, 0).getDate();
        let days = r.byDay.length ? monthDaysForByDay(yy, mm, r.byDay)
            : r.byMonthDay.length ? r.byMonthDay.map(x => x < 0 ? last + 1 + x : x)
            : [d];
        days = days.filter(x => x >= 1 && x <= last).sort((a, b) => a - b);
        return days.map(x => atDay(start, yy, mm, x));
    }
    case "YEARLY": {
        const yy = y + step * r.interval;
        const months = r.byMonth.length ? r.byMonth : [m];
        const out = [];
        for (const mm of months.slice().sort((a, b) => a - b)) {
            const last = new Date(yy, mm + 1, 0).getDate();
            const days = r.byDay.length ? monthDaysForByDay(yy, mm, r.byDay)
                : r.byMonthDay.length ? r.byMonthDay.map(x => x < 0 ? last + 1 + x : x)
                : [d];
            for (const x of days.filter(x => x >= 1 && x <= last).sort((a, b) => a - b))
                out.push(atDay(start, yy, mm, x));
        }
        return out;
    }
    }
    return [];
}

// Start times of every occurrence of a recurring event up to `to` (ms),
// honouring COUNT, UNTIL and EXDATE.
function occurrenceStarts(ev, to) {
    const r = ev.rrule, startMs = ev.start.getTime();
    const excluded = new Set(ev.exdates || []);
    const out = [];
    let produced = 0;
    for (let step = 0; step < MAX_STEPS; step++) {
        const candidates = periodCandidates(ev.start, r, step);
        if (candidates.length === 0) break;
        for (const c of candidates) {
            const t = c.getTime();
            if (t < startMs) continue;
            if (r.until !== null && t > r.until) return out;
            if (t > to) return out;
            produced++;
            if (r.count && produced > r.count) return out;
            if (!excluded.has(t)) out.push(t);
        }
    }
    return out;
}

// Replaces recurring events with their occurrences that fall inside
// [from, to] (ms). An instance moved with RECURRENCE-ID replaces the
// occurrence it was moved from. Events without a rule pass through unchanged.
function expandRecurrences(events, from, to) {
    const moved = new Set();
    for (const e of events)
        if (e.recurrenceId !== undefined && e.uid) moved.add(e.uid + "@" + e.recurrenceId);
    const out = [];
    for (const e of events) {
        if (!e.rrule || !e.rrule.freq) { out.push(e); continue; }
        const duration = e.end ? e.end.getTime() - e.start.getTime() : null;
        for (const t of occurrenceStarts(e, to)) {
            if (moved.has(e.uid + "@" + t)) continue;
            const s = new Date(t);
            const endMs = duration === null ? null : t + duration;
            if ((endMs === null ? t : endMs) < from) continue;
            const occ = Object.assign({}, e, { start: s, end: endMs === null ? undefined : new Date(endMs) });
            delete occ.rrule;
            out.push(occ);
        }
    }
    return out;
}

// True when the event covers any part of the local calendar day. End is
// exclusive; an all-day event without DTEND lasts one day, a timed one
// without DTEND is a point in time.
function occursOn(e, day) {
    const dayStart = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
    const dayEnd = dayStart + DAY_MS;
    const s = e.start.getTime();
    let end = e.end ? e.end.getTime() : (e.allDay ? s + DAY_MS : s);
    if (end <= s) return s >= dayStart && s < dayEnd;
    return s < dayEnd && end > dayStart;
}

// The feeds in calendar.url that are on, in order: [{url, color, name}].
// A line is "<url>[ #color=<name>][ #name=<text>]"; a feed switched off is
// written as "#off <url> …" and, like any other #-comment or blank line, is
// skipped. color is "" when the line names none; name runs to the end of the
// line. The settings app's Calendar panel writes this format.
function parseFeedList(text) {
    if (!text) return [];
    const feeds = [];
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim();
        if (line === "" || line.indexOf("#") === 0) continue;
        const url = line.split(/\s+/)[0];
        const color = (line.match(/\s#color=(\w+)/) || [])[1] || "";
        const name = ((line.match(/\s#name=(.*)$/) || [])[1] || "").trim();
        feeds.push({ url: url, color: color, name: name });
    }
    return feeds;
}
