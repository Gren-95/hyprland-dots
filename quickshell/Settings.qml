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
    property bool mediaKeysVisible: true
    property bool activityIconsVisible: true
    property int toastTimeout: 6000
    property int notifHistoryCap: 50
    property real fontScale: 1.0               // multiplies every Theme.fontSize token
    property string fontFamily: "FiraCode Nerd Font"
    property int barHeight: 36
    property string accentPrimaryName: "blue"  // Theme.accentPrimary (highlights); "auto" = from wallpaper
    property string accentAutoHex: ""          // cached wallpaper-extracted accent
    property int spotlightCap: 60              // launcher results shown
    property int osdDuration: 1500             // ms the volume/brightness OSD stays
    property int sysmonInterval: 1500          // ms between system-monitor refreshes
    property int calendarFetchInterval: 10     // minutes between ICS fetches
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/wallpapers"
    property var flyoutSizes: ({})             // flyout id -> { w, h } overrides
    property var barPlacement: ({})            // module id -> "bar"|"overflow"|"hidden"
    property var trayPlacement: ({})           // tray app id -> same
    property var qaPlacement: ({})             // quick-action key -> "bar"|"overflow"|"hidden"
    property bool clock24h: true
    property bool clockShowSeconds: false
    property string clockDateFormat: "ddd, dd MMM"
    property real animScale: 1.0               // multiplies Theme.duration; 0 = instant
    property real radiusScale: 1.0             // multiplies Theme.radius
    property real barOpacity: 1.0
    property var batteryWarnLevels: [20, 10]   // toast at each level while discharging
    property int batteryCriticalPct: 5         // countdown-to-action level; 0 = off
    property string batteryCriticalAction: "suspend"   // "suspend" | "none"
    property string toastPosition: "center"    // "center" | "right"
    property int toastMax: 5                   // visible toast stack cap
    property int toastWidth: 380
    property bool notifGroupByApp: true        // center groups history by app
    property bool weekStartMonday: true
    property int windowTitleWidth: 400         // bar window-title cap; 0 = hidden
    property int osdBottomMargin: 60
    property int mediaTitleWidth: 260          // media chip track title; 0 = icons only
    property bool sysmonShowCpu: true
    property bool sysmonShowRam: true
    property bool sysmonShowStorage: true
    property bool sysmonShowThermal: true
    property bool workspaceGlyphs: true        // icons vs plain numbers in the strip
    property bool workspaceWindowIcons: false  // tiny app icons inside each pill
    property bool spotlightCalc: true          // inline calculator row
    property bool clipboardThumbs: true        // image thumbnails in history
    property string barWheelAction: "workspace" // bar-background wheel: workspace|volume|none
    property int volumeStep: 5                 // % per wheel tick / arrow press
    property int brightnessStep: 5
    property int maxVolume: 100                // % ceiling for all volume paths
    property bool idleInhibitOnMedia: false    // Stay Awake while media plays
    property bool idleInhibitOnPower: false    // Stay Awake while on AC
    property var eventToasts: ({ charger: true, vpn: true, audio: false, layout: false })
    property string weatherLocation: ""        // city name; empty = weather off
    property bool weatherFahrenheit: false

    // Reactive flyout-geometry lookup (reads flyoutSizes, so bindings track it).
    function flyoutSize(id, dim, def) {
        const e = flyoutSizes[id];
        return (e && e[dim]) ? e[dim] : def;
    }

    // ===== Bar item placement: "bar" | "overflow" | "hidden" =====
    // mediakeys/activityicons bridge to their legacy bool flags (2-state),
    // so old cache files and the Quick Actions toggles keep working.
    function placement(id) {
        if (id === "mediakeys")     return mediaKeysVisible ? "bar" : "hidden";
        if (id === "activityicons") return activityIconsVisible ? "bar" : "hidden";
        return barPlacement[id] ?? "bar";
    }
    function trayPlacementOf(tid)     { return trayPlacement[tid] ?? "bar"; }

    // ===== Quick Actions item placement =====
    // Same states as bar items, but "overflow" (the default) means the
    // Quick Actions panel itself; "bar" promotes the item to its own icon
    // in the bar's right group.
    function qaPlacementOf(key)     { return qaPlacement[key] ?? "overflow"; }

    readonly property var _schema: [
        { name: "mediaKeysVisible",     file: "media-keys.enabled",     type: "bool" },
        { name: "activityIconsVisible", file: "activity-icons.enabled", type: "bool" },
        { name: "toastTimeout",         file: "toast-timeout",          type: "int"  },
        { name: "notifHistoryCap",      file: "notif-history-cap",      type: "int"  },
        { name: "fontScale",            file: "font-scale",             type: "real" },
        { name: "fontFamily",           file: "font-family",            type: "string" },
        { name: "barHeight",            file: "bar-height",             type: "int"  },
        { name: "accentPrimaryName",    file: "accent-primary",         type: "string" },
        { name: "accentAutoHex",        file: "accent-auto-hex",        type: "string" },
        { name: "spotlightCap",         file: "spotlight-cap",          type: "int"  },
        { name: "osdDuration",          file: "osd-duration",           type: "int"  },
        { name: "sysmonInterval",       file: "sysmon-interval",        type: "int"  },
        { name: "calendarFetchInterval", file: "calendar-fetch-interval", type: "int" },
        { name: "wallpaperDir",         file: "wallpaper-dir",          type: "string" },
        { name: "flyoutSizes",          file: "flyout-sizes.json",      type: "json" },
        { name: "barPlacement",         file: "bar-placement.json",     type: "json" },
        { name: "trayPlacement",        file: "tray-placement.json",    type: "json" },
        { name: "qaPlacement",          file: "qa-placement.json",      type: "json" },
        { name: "clock24h",             file: "clock-24h",              type: "bool" },
        { name: "clockShowSeconds",     file: "clock-seconds",          type: "bool" },
        { name: "clockDateFormat",      file: "clock-date-format",      type: "string" },
        { name: "animScale",            file: "anim-scale",             type: "real" },
        { name: "radiusScale",          file: "radius-scale",           type: "real" },
        { name: "barOpacity",           file: "bar-opacity",            type: "real" },
        { name: "batteryWarnLevels",    file: "battery-warn-levels.json", type: "json" },
        { name: "batteryCriticalPct",   file: "battery-critical-pct",   type: "int"  },
        { name: "batteryCriticalAction", file: "battery-critical-action", type: "string" },
        { name: "toastPosition",        file: "toast-position",         type: "string" },
        { name: "toastMax",             file: "toast-max",              type: "int"  },
        { name: "toastWidth",           file: "toast-width",            type: "int"  },
        { name: "notifGroupByApp",      file: "notif-group-by-app",     type: "bool" },
        { name: "weekStartMonday",      file: "week-start-monday",      type: "bool" },
        { name: "windowTitleWidth",     file: "window-title-width",     type: "int"  },
        { name: "osdBottomMargin",      file: "osd-bottom-margin",      type: "int"  },
        { name: "mediaTitleWidth",      file: "media-title-width",      type: "int"  },
        { name: "sysmonShowCpu",        file: "sysmon-show-cpu",        type: "bool" },
        { name: "sysmonShowRam",        file: "sysmon-show-ram",        type: "bool" },
        { name: "sysmonShowStorage",    file: "sysmon-show-storage",    type: "bool" },
        { name: "sysmonShowThermal",    file: "sysmon-show-thermal",    type: "bool" },
        { name: "workspaceGlyphs",      file: "workspace-glyphs",       type: "bool" },
        { name: "workspaceWindowIcons", file: "workspace-window-icons", type: "bool" },
        { name: "spotlightCalc",        file: "spotlight-calc",         type: "bool" },
        { name: "clipboardThumbs",      file: "clipboard-thumbs",       type: "bool" },
        { name: "barWheelAction",       file: "bar-wheel-action",       type: "string" },
        { name: "volumeStep",           file: "volume-step",            type: "int"  },
        { name: "brightnessStep",       file: "brightness-step",        type: "int"  },
        { name: "maxVolume",            file: "max-volume",             type: "int"  },
        { name: "idleInhibitOnMedia",   file: "idle-inhibit-media",     type: "bool" },
        { name: "idleInhibitOnPower",   file: "idle-inhibit-power",     type: "bool" },
        { name: "eventToasts",          file: "event-toasts.json",      type: "json" },
        { name: "weatherLocation",      file: "weather-location",       type: "string" },
        { name: "weatherFahrenheit",    file: "weather-fahrenheit",     type: "bool" },
    ]

    // Settings live under ~/.config (they're user prefs, not cache — a
    // cache wipe must not eat the bar layout). The dir is gitignored in
    // the dotfiles repo, like calendar.url.
    readonly property string _dir: Quickshell.env("HOME") + "/.config/quickshell/settings/"

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
