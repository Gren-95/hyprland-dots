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
    const sandbox = { Date, Math, parseInt, isFinite, Number };
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
