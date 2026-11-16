// Unit tests for config/quickshell/KeybindSearch.js. Run: node --test tests/*.test.js
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function load() {
    const file = path.join(__dirname, "..", "config", "quickshell", "KeybindSearch.js");
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*$/m, "");
    const sandbox = { String };
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    return sandbox;
}
const KS = load();
const plain = x => JSON.parse(JSON.stringify(x));

const e = (mods, key, rawKey, name) => ({ mods, key, rawKey: rawKey || key, name });
const ENTRIES = [
    e(["Super"], "S", "S", "sound"),
    e(["Shift", "Super"], "S", "S", "screenshot"),
    e(["Ctrl", "Shift", "Super"], "S", "S", "ocr"),
    e(["Super"], "R", "R", "launcher"),
    e(["Ctrl", "Alt"], "Delete", "Delete", "powermenu"),
    e(["Super"], "[", "bracketleft", "prev"),
    e(["Super"], "Return", "Return", "terminal"),
];
const names = list => Array.from(list).map(x => x.name);

test("modifier words plus one key parse as a combo", () => {
    assert.deepStrictEqual(plain(KS.parseComboQuery("super s")), { mods: ["Super"], key: "s" });
    assert.deepStrictEqual(plain(KS.parseComboQuery("Super+Shift+S")), { mods: ["Super", "Shift"], key: "s" });
    assert.deepStrictEqual(plain(KS.parseComboQuery("win enter")), { mods: ["Super"], key: "return" });
    assert.deepStrictEqual(plain(KS.parseComboQuery("ctrl alt")), { mods: ["Ctrl", "Alt"], key: "" });
});

test("text queries are not combos", () => {
    assert.strictEqual(KS.parseComboQuery("volume"), null);
    assert.strictEqual(KS.parseComboQuery("s"), null);
    assert.strictEqual(KS.parseComboQuery("super open terminal"), null);
});

test("super s finds Super+S first, then wider combos on S", () => {
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("super s"))), ["sound", "screenshot", "ocr"]);
});

test("super shift s puts Super+Shift+S first", () => {
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("super shift s"))), ["screenshot", "ocr"]);
});

test("key names match the shown key or Hyprland's keysym", () => {
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("super ["))), ["prev"]);
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("super bracketleft"))), ["prev"]);
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("super enter"))), ["terminal"]);
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("ctrl alt del"))), ["powermenu"]);
});

test("modifiers only lists every bind using them", () => {
    assert.deepStrictEqual(names(KS.filterByCombo(ENTRIES, KS.parseComboQuery("ctrl"))), ["ocr", "powermenu"]);
});
