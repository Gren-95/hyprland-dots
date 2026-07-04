// Persisted user preferences. Instantiated ONCE in shell.qml as
// `settingsStore` (first child, so it exists before any consumer) — any
// component resolves it via the id scope chain and changes propagate
// everywhere. Values are stored as one tiny file per setting under
// ~/.cache/quickshell.
//
// NOT a `pragma Singleton`: config singletons don't reliably instantiate
// on cold start (consumer binding reads return undefined until a change
// notification heals them) — a root-scope instance has guaranteed order.
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
// breaks the load->assign->save cycle; `json` (var) settings always notify
// on assignment, so persist() compares against `lastText` before writing.
// Maps must be REASSIGNED (clone-and-set), never mutated in place.
//
// WARNING: do NOT use `required property var modelData` in the Instantiator
// delegate — it silently aborts construction of the entire singleton on a
// cold start (every consumer then reads undefined). Use the classic context
// `modelData` as below.

import QtQuick
import QtQml.Models   // Instantiator (not provided by QtQuick in Qt 6)
import Quickshell
import Quickshell.Io

Scope {
    id: settings
    property bool mediaKeysVisible: false
    property bool activityIconsVisible: true
    property int toastTimeout: 6000
    property int notifHistoryCap: 50

    readonly property var _schema: [
        { name: "mediaKeysVisible",     file: "media-keys.enabled",     type: "bool" },
        { name: "activityIconsVisible", file: "activity-icons.enabled", type: "bool" },
        { name: "toastTimeout",         file: "toast-timeout",          type: "int"  },
        { name: "notifHistoryCap",      file: "notif-history-cap",      type: "int"  },
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
            property bool ready: false
            property bool dirty: false
            property string lastText: ""

            path: settings._dir + modelData.file
            watchChanges: true
            atomicWrites: true
            printErrors: false

            readonly property var current: settings[modelData.name]
            onCurrentChanged: ready ? persist() : dirty = true

            function persist() {
                const s = settings._serialize(modelData.type, current);
                if (s === lastText) return;
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
            onLoadFailed: {
                ready = true;
                if (dirty) { dirty = false; persist(); }
            }
            onFileChanged: reload()
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", _dir])
}
