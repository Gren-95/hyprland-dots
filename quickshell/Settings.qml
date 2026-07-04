// Persisted user preferences. Singleton so any component can bind to a
// setting and changes propagate everywhere. Values are stored as one tiny
// file per setting under ~/.cache/quickshell.
//
// To add a setting:
//   1. Declare a typed property with its default below.
//   2. Add one `_schema` row: { name, file, type } where type is
//      "bool" | "int" | "real" | "string" | "json".
// The Instantiator creates a watching FileView per row: external edits load
// into the property, property writes persist via FileView.setText (atomic,
// no shell quoting). Absent file = QML default.
//
// Loop safety: typed scalar properties only notify on real change, which
// breaks the load→assign→save cycle; `json` (var) settings always notify on
// assignment, so persist() compares against `lastText` before writing.
// Maps must be REASSIGNED (clone-and-set), never mutated in place — in-place
// mutation neither notifies consumers nor persists.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: settings

    // ===== Settings (defaults live here) =====
    property bool mediaKeysVisible: false
    property bool activityIconsVisible: true   // bar's camera/mic/sync status icons

    // ===== Schema: name must match a property above =====
    readonly property var _schema: [
        { name: "mediaKeysVisible",     file: "media-keys.enabled",     type: "bool" },
        { name: "activityIconsVisible", file: "activity-icons.enabled", type: "bool" },
    ]

    readonly property string _dir: Quickshell.env("HOME") + "/.cache/quickshell/"

    function _parse(type, text) {
        switch (type) {
        case "bool":   return text.trim() === "1";
        case "int":    return parseInt(text.trim(), 10);
        case "real":   return parseFloat(text.trim());
        case "json":   try { return JSON.parse(text); } catch (e) { return ({}); }
        default:       return text.endsWith("\n") ? text.slice(0, -1) : text;
        }
    }
    function _serialize(type, val) {
        switch (type) {
        case "bool":   return val ? "1" : "0";
        case "json":   return JSON.stringify(val, null, 2);
        default:       return String(val);
        }
    }

    Instantiator {
        model: settings._schema
        delegate: FileView {
            required property var modelData
            // First load attempt (success or file-absent) finished. Changes
            // made before that are held in `dirty` and flushed after, so a
            // fast post-login toggle isn't lost and the boot-time load
            // doesn't bounce straight back into a write.
            property bool ready: false
            property bool dirty: false
            property string lastText: ""   // last content seen or written

            path: settings._dir + modelData.file
            watchChanges: true
            atomicWrites: true
            printErrors: false

            // Reading settings[name] inside a binding dependency-tracks the
            // named property, so this re-evaluates on every settings change.
            readonly property var current: settings[modelData.name]
            onCurrentChanged: ready ? persist() : dirty = true

            function persist() {
                const s = settings._serialize(modelData.type, current);
                if (s === lastText) return;   // breaks the json echo loop
                lastText = s;
                setText(s);
            }

            onLoaded: {
                const t = text();
                lastText = t;
                settings[modelData.name] = settings._parse(modelData.type, t);
                ready = true;
                if (dirty) { dirty = false; persist(); }
            }
            onLoadFailed: {   // file absent → keep the QML default
                ready = true;
                if (dirty) { dirty = false; persist(); }
            }
            onFileChanged: reload()
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", _dir])
}
