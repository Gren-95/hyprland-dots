.pragma library
// Key-combo search for the keybinds viewer (Keybinds.qml). Plain JavaScript,
// so tests/keybind-search.test.js can run it under node.
//
// A query made of modifier words and at most one key, separated by spaces or
// "+", is read as a key combo: "super s", "Super+Shift+S", "ctrl alt delete".
// Anything else is left to the viewer's text search.
//
// The settings app's Keyboard shortcuts panel has the same rules in Rust
// (apps/settings/src/keysearch.rs, same test cases); keep the two in step.

const MODIFIERS = {
    super: "Super", win: "Super", windows: "Super", meta: "Super", mod: "Super", mainmod: "Super",
    shift: "Shift",
    ctrl: "Ctrl", control: "Ctrl",
    alt: "Alt",
};

// Other names people type for a key, mapped to the name the viewer shows.
const KEY_ALIASES = {
    enter: "return",
    esc: "escape",
    del: "delete",
    spacebar: "space",
    printscreen: "prtsc", print: "prtsc",
    left: "left", right: "right", up: "up", down: "down",
};

function _normKey(k) {
    const low = String(k).toLowerCase();
    return KEY_ALIASES[low] || low;
}

// Returns {mods: [...], key: "s" | ""} for a combo query, or null when the
// query is not one (no modifier word, or more than one non-modifier word).
function parseComboQuery(query) {
    const tokens = String(query).trim().split(/[\s+]+/).filter(t => t.length > 0);
    if (tokens.length === 0) return null;
    const mods = [];
    const rest = [];
    for (const t of tokens) {
        const m = MODIFIERS[t.toLowerCase()];
        if (m) { if (mods.indexOf(m) < 0) mods.push(m); }
        else rest.push(t);
    }
    if (mods.length === 0 || rest.length > 1) return null;
    return { mods: mods, key: rest.length === 1 ? _normKey(rest[0]) : "" };
}

// Rank of an entry against a parsed combo: 0 = exactly these modifiers and
// key, 1 = these plus more modifiers, -1 = no match. An entry has `mods` (as
// shown, e.g. ["Super", "Shift"]), `key` (as shown) and `rawKey` (Hyprland's
// keysym, e.g. "bracketleft").
function comboRank(entry, combo) {
    for (const m of combo.mods)
        if (entry.mods.indexOf(m) < 0) return -1;
    if (combo.key !== "") {
        const k = combo.key;
        if (_normKey(entry.key) !== k && _normKey(entry.rawKey) !== k) return -1;
    }
    // Lock-type modifiers (Caps, Mod2 = NumLock) do not count as extra.
    const extra = entry.mods.filter(m => combo.mods.indexOf(m) < 0
        && m !== "Caps" && m !== "Mod2").length;
    return extra === 0 ? 0 : 1;
}

// Entries matching the combo, exact matches first; the input order is kept
// within each rank.
function filterByCombo(entries, combo) {
    const exact = [], wider = [];
    for (const e of entries) {
        const r = comboRank(e, combo);
        if (r === 0) exact.push(e);
        else if (r === 1) wider.push(e);
    }
    return exact.concat(wider);
}
