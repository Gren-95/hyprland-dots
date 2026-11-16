// Unit tests for config/quickshell/IcsParse.js. Run: node --test tests/
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

// IcsParse.js is a QML JavaScript library: drop the ".pragma library" line
// and evaluate the rest into a sandbox.
function loadIcs() {
    const file = path.join(__dirname, "..", "config", "quickshell", "IcsParse.js");
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const sandbox = { Date, Math, parseInt, isFinite, Number, Set, Object };
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    return sandbox;
}
const Ics = loadIcs();

function cal(...events) {
    return ["BEGIN:VCALENDAR", ...events.flat(), "END:VCALENDAR"].join("\r\n");
}

test("event title and description ignore nested VALARM", () => {
    const text = cal([
        "BEGIN:VEVENT", "DTSTART:20261120T090000Z", "DTEND:20261120T100000Z",
        "SUMMARY:Standup", "DESCRIPTION:Daily sync",
        "BEGIN:VALARM", "ACTION:EMAIL", "SUMMARY:Alarm notification",
        "DESCRIPTION:This is an event reminder", "END:VALARM",
        "LOCATION:Room 1", "END:VEVENT",
    ]);
    const evs = Ics.parseFeed(text, 0);
    assert.strictEqual(evs.length, 1);
    assert.strictEqual(evs[0].summary, "Standup");
    assert.strictEqual(evs[0].description, "Daily sync");
    assert.strictEqual(evs[0].location, "Room 1");
});

test("all-day event is marked all day", () => {
    const evs = Ics.parseFeed(cal(["BEGIN:VEVENT", "DTSTART;VALUE=DATE:20261120", "SUMMARY:Holiday", "END:VEVENT"]), 2);
    assert.strictEqual(evs[0].allDay, true);
    assert.strictEqual(evs[0].calIndex, 2);
});

const day = (y, m, d) => new Date(y, m - 1, d);
const starts = evs => evs.map(e => e.start.toISOString().slice(0, 10));
const FAR = new Date(2030, 0, 1).getTime();
const FROM = new Date(2026, 0, 1).getTime();

function recurring(lines) {
    return Ics.parseFeed(cal(["BEGIN:VEVENT", "UID:r1", "SUMMARY:Meet", ...lines, "END:VEVENT"]), 0);
}

test("weekly rule with COUNT expands to that many occurrences", () => {
    const evs = Ics.expandRecurrences(recurring(["DTSTART:20261102T090000", "DTEND:20261102T100000", "RRULE:FREQ=WEEKLY;COUNT=3"]), FROM, FAR);
    assert.deepStrictEqual(Array.from(evs).map(e => e.start.getDate()), [2, 9, 16]);
    assert.strictEqual(evs[1].end.getHours(), 10);
});

test("weekly BYDAY with UNTIL and EXDATE", () => {
    const evs = Ics.expandRecurrences(recurring([
        "DTSTART:20261102T090000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261111T235959Z",
        "EXDATE:20261104T090000"]), FROM, FAR);
    assert.deepStrictEqual(Array.from(evs).map(e => e.start.getDate()), [2, 9, 11]);
});

test("monthly last Friday", () => {
    const evs = Ics.expandRecurrences(recurring(["DTSTART:20261127T120000", "RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3"]), FROM, FAR);
    assert.deepStrictEqual(Array.from(evs).map(e => [e.start.getMonth() + 1, e.start.getDate()]), [[11, 27], [12, 25], [1, 29]]);
});

test("daily with interval stops at the window end", () => {
    const evs = Ics.expandRecurrences(recurring(["DTSTART:20261201T080000", "RRULE:FREQ=DAILY;INTERVAL=2"]), FROM, new Date(2026, 11, 7, 23).getTime());
    assert.deepStrictEqual(Array.from(evs).map(e => e.start.getDate()), [1, 3, 5, 7]);
});

test("yearly birthday all-day", () => {
    const evs = Ics.expandRecurrences(recurring(["DTSTART;VALUE=DATE:20000315", "RRULE:FREQ=YEARLY"]), FROM, FAR);
    assert.deepStrictEqual(Array.from(evs).map(e => e.start.getFullYear()), [2026, 2027, 2028, 2029]);
    assert.ok(evs.every(e => e.allDay && e.start.getMonth() === 2 && e.start.getDate() === 15));
});

test("a moved instance replaces its original occurrence", () => {
    const text = cal(
        ["BEGIN:VEVENT", "UID:m1", "SUMMARY:Sync", "DTSTART:20261102T090000", "RRULE:FREQ=WEEKLY;COUNT=3", "END:VEVENT"],
        ["BEGIN:VEVENT", "UID:m1", "SUMMARY:Sync (moved)", "RECURRENCE-ID:20261109T090000", "DTSTART:20261110T140000", "END:VEVENT"]);
    const evs = Ics.expandRecurrences(Ics.parseFeed(text, 0), FROM, FAR).sort((a, b) => a.start - b.start);
    assert.deepStrictEqual(Array.from(evs).map(e => [e.start.getDate(), e.summary]), [[2, "Sync"], [10, "Sync (moved)"], [16, "Sync"]]);
});

test("occurrences before the window are dropped", () => {
    const evs = Ics.expandRecurrences(recurring(["DTSTART:20200106T090000", "RRULE:FREQ=WEEKLY"]), new Date(2026, 10, 1).getTime(), new Date(2026, 10, 15).getTime());
    assert.ok(evs.length === 2 && evs.every(e => e.start.getMonth() === 10));
});

test("multi-day all-day event covers every day, end exclusive", () => {
    const [e] = Ics.parseFeed(cal(["BEGIN:VEVENT", "DTSTART;VALUE=DATE:20261120", "DTEND;VALUE=DATE:20261123", "SUMMARY:Trip", "END:VEVENT"]), 0);
    assert.deepStrictEqual([19, 20, 21, 22, 23].map(d => Ics.occursOn(e, day(2026, 11, d))), [false, true, true, true, false]);
});

test("timed event ending at midnight stays on its own day", () => {
    const [e] = Ics.parseFeed(cal(["BEGIN:VEVENT", "DTSTART:20261120T220000", "DTEND:20261121T000000", "END:VEVENT"]), 0);
    assert.strictEqual(Ics.occursOn(e, day(2026, 11, 20)), true);
    assert.strictEqual(Ics.occursOn(e, day(2026, 11, 21)), false);
});

test("all-day event without DTEND lasts one day", () => {
    const [e] = Ics.parseFeed(cal(["BEGIN:VEVENT", "DTSTART;VALUE=DATE:20261120", "END:VEVENT"]), 0);
    assert.strictEqual(Ics.occursOn(e, day(2026, 11, 20)), true);
    assert.strictEqual(Ics.occursOn(e, day(2026, 11, 21)), false);
});
