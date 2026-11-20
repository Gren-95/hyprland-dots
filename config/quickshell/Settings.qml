// Persisted user preferences. Instantiated ONCE in shell.qml as
// `settingsStore` (first child, so it exists before any consumer) — any
// component resolves it via the id scope chain and changes propagate
// everywhere. Values are stored as one tiny file per setting under
// ~/.config/quickshell/settings/ (gitignored).
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
    property bool activityIconsVisible: true
    property int toastTimeout: 10000           // hard ceiling: every toast, critical included, dies here
    property int notifHistoryCap: 50
    property real fontScale: 1.0               // multiplies every Theme.fontSize token
    property string fontFamily: "Iosevka Nerd Font"
    property int barHeight: 36
    property string accentPrimaryName: "orange"  // Theme.accentPrimary (highlights); "auto" = from wallpaper
    property string accentAutoHex: ""          // cached wallpaper-extracted accent
    property bool accentEverywhere: true       // accent replaces the decorative accents
    property int spotlightCap: 60              // launcher results shown
    property int osdDuration: 1500             // ms the volume/brightness OSD stays
    property bool osdVolume: true              // which changes show the OSD
    property bool osdMic: true
    property bool osdBrightness: true
    property bool osdKbBacklight: true
    property int sysmonInterval: 1500          // ms between system-monitor refreshes
    property int calendarFetchInterval: 10     // minutes between ICS fetches
    property string wallpaperDir: Quickshell.env("HOME") + "/Pictures/wallpapers"
    property var flyoutSizes: ({})             // flyout id -> { w, h } overrides
    property var barPlacement: ({})            // module id -> "bar"|"overflow"|"hidden"
    property var trayPlacement: ({})           // tray app id -> same
    property var qaPlacement: ({})             // quick-action key -> "bar"|"overflow"|"hidden"
    property var hiddenApps: ({})              // desktop id -> true; dropped from the launcher
    property var iconThemeRecents: []          // icon theme ids, most recently applied first
    property var cursorThemeRecents: []        // cursor theme ids, most recently applied first
    property var btLastConnected: ({})         // Bluetooth address -> epoch ms of its last connection
    property bool clock24h: true
    property bool clockShowSeconds: false
    property string clockDateFormat: "ddd, dd MMM"
    property real animScale: 1.0               // multiplies Theme.duration; 0 = instant
    property bool animations: true             // off: shell, Hyprland and GTK animations all off
    // Game mode: what it does (gamemode.sh reads the rest of these files).
    property bool gamemodeEffects: true
    property bool gamemodePerformance: true
    property bool gamemodeHideBar: true
    property bool gamemodeDnd: true
    property bool gamemodeSyncs: true
    property bool gamemodeNight: true
    property bool gamemodeDocker: true
    property bool gamemodeAwake: true
    property bool gamemodeTailscale: true
    property bool gamemodeFeral: false
    property bool gameLauncherGames: true      // the game mode launcher opens on the Games view
    property real radiusScale: 1.0             // multiplies Theme.radius
    property real barOpacity: 1.0
    property int batteryCriticalPct: 5         // countdown-to-action level; 0 = off
    property string batteryCriticalAction: "suspend"   // "suspend" | "none"
    property string toastPosition: "center"    // "center" | "right"
    property int toastMax: 5                   // visible toast stack cap
    property int toastWidth: 380
    property bool notifGroupByApp: true        // center groups history by app
    property bool notifAutoExpire: true        // matched notifications leave the center on their own
    property var notifAutoExpireRules: ["Claude Code"]   // texts; a notification whose appName or summary contains one expires
    property int notifAutoExpireDelay: 10000   // ms a matched notification survives in the center
    property bool dnd: false                   // do not disturb, switched by hand
    property bool dndSchedule: false           // also quiet between dndFrom and dndTo every day
    property string dndFrom: "22:00"
    property string dndTo: "07:00"
    property bool notifSounds: false           // a sound with each toast
    property var notifAppRules: ({})           // appName -> "quiet" (no toast) | "mute" (dropped)
    property var notifAppsSeen: []             // appNames that sent notifications, for the settings app
    property bool weekStartMonday: true
    property int windowTitleWidth: 400         // bar window-title cap; 0 = hidden
    property int osdBottomMargin: 60
    property bool sysmonShowCpu: true
    property bool sysmonShowRam: true
    property bool sysmonShowStorage: true
    property bool sysmonShowThermal: true
    property bool workspaceGlyphs: true        // icons vs plain numbers in the strip
    property bool workspaceWindowIcons: false  // tiny app icons inside each pill
    property bool spotlightCalc: true          // inline calculator row
    property bool spotlightActions: true       // quick actions (Do not disturb, Game mode…) among the results
    property bool clipboardThumbs: true        // image thumbnails in history
    property string barWheelAction: "workspace" // bar-background wheel: workspace|volume|none
    property int volumeStep: 5                 // % per wheel tick / arrow press
    property int brightnessStep: 5
    property int maxVolume: 100                // % ceiling for all volume paths
    property int alertVolume: 100              // % loudness of notification sounds
    property string powerOnAc: "performance"   // power-auto.sh: profile on the charger
    property string powerOnBattery: "balanced" // power-auto.sh: profile on battery
    property int powerSaverBelow: 30           // power-auto.sh: power saver below this %; 0 = never
    property bool idleInhibitOnMedia: false    // Stay Awake while media plays
    property bool idleInhibitOnPower: false    // Stay Awake while on AC
    property bool idleStayAwake: false         // the manual Stay Awake toggle
    property bool idleHoldClaude: true         // Claude Code at work holds idle (claude-activity.sh reads it)
    // Read by scripts, not the shell: lid.sh and the hyprlock text scripts.
    property string lidCloseAction: "lock"     // lock | suspend | nothing
    property bool lockShowMedia: true
    property bool lockShowWeather: true
    property bool lockShowBattery: true
    // Read by scripts: battery-notify.sh and night.sh.
    property int batteryLowPct: 20
    property int batteryWarnPct: 10
    property int nightTemperature: 4000
    property bool nightSchedule: false
    property string nightFrom: "21:00"
    property string nightTo: "07:00"
    property var eventToasts: ({ charger: true, vpn: true, audio: false, layout: false })
    property string weatherLocation: ""        // city name; empty = weather off
    property bool weatherFahrenheit: false
    // Screenshots: lib/screenshot.sh reads the shot-* files; the shell reads
    // shotActions (open the actions sheet after a region screenshot).
    property string shotDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
    property string shotFormat: "png"          // png | jpg
    property bool shotCursor: false
    property bool shotClipboard: true
    property bool shotActions: true
    // Screen recording, read by scripts/screenrecord.sh (not by the shell).
    property string recordDir: Quickshell.env("HOME") + "/Videos/Recordings"
    property string recordContainer: "mp4"     // mp4 | mkv | webm
    property int recordFps: 60
    property string recordQuality: "very_high" // medium | high | very_high | ultra
    property string recordCodec: "auto"       // auto | h264 | hevc | av1 | vp9
    property bool recordCursor: true
    property string recordAudio: "none"       // none | output | input | both

    // Reactive flyout-geometry lookup (reads flyoutSizes, so bindings track it).
    function flyoutSize(id, dim, def) {
        const e = flyoutSizes[id];
        return (e && e[dim]) ? e[dim] : def;
    }

    // ===== Bar item placement: "bar" | "overflow" | "hidden" =====
    // activityicons bridges to its legacy bool flag (2-state), so old cache
    // files and the Quick Actions toggle keep working.
    function placement(id) {
        if (id === "activityicons") return activityIconsVisible ? "bar" : "hidden";
        return barPlacement[id] ?? "bar";
    }
    function trayPlacementOf(tid)     { return trayPlacement[tid] ?? "bar"; }

    // ===== Quick Actions item placement =====
    // Same states as bar items, but "overflow" (the default) means the
    // Quick Actions panel itself; "bar" promotes the item to its own icon
    // in the bar's right group.
    //
    // Per-key defaults for anything the user has never placed. Clipboard is
    // reached by reflex often enough that opening a panel to find it is a
    // click too many; anything the user has actually placed still wins.
    readonly property var _qaPlacementDefaults: ({ clipboard: "bar" })
    function qaPlacementOf(key)     { return qaPlacement[key] ?? _qaPlacementDefaults[key] ?? "overflow"; }

    // ===== Launcher app visibility =====
    // Launcher-scoped, not a NoDisplay override written into
    // ~/.local/share/applications: hiding an app must never risk clobbering an
    // entry that is already there (the WinApps ones live exactly there), and
    // un-hiding must be a value change rather than a file deletion.
    function isAppHidden(id)        { return hiddenApps[id] === true; }
    readonly property int hiddenAppCount: Object.keys(hiddenApps).length
    function setAppHidden(id, hidden) {
        if (!id) return;
        const next = {};                       // reassigned, never mutated
        for (const k in hiddenApps) next[k] = hiddenApps[k];
        if (hidden) next[id] = true; else delete next[id];
        hiddenApps = next;
    }

    readonly property var _schema: [
        { name: "activityIconsVisible", file: "activity-icons.enabled", type: "bool" },
        { name: "toastTimeout",         file: "toast-timeout",          type: "int"  },
        { name: "notifHistoryCap",      file: "notif-history-cap",      type: "int"  },
        { name: "fontScale",            file: "font-scale",             type: "real" },
        { name: "fontFamily",           file: "font-family",            type: "string" },
        { name: "barHeight",            file: "bar-height",             type: "int"  },
        { name: "accentPrimaryName",    file: "accent-primary",         type: "string" },
        { name: "accentAutoHex",        file: "accent-auto-hex",        type: "string" },
        { name: "accentEverywhere",     file: "accent-everywhere",      type: "bool" },
        { name: "spotlightCap",         file: "spotlight-cap",          type: "int"  },
        { name: "osdDuration",          file: "osd-duration",           type: "int"  },
        { name: "osdVolume",            file: "osd-volume",             type: "bool" },
        { name: "osdMic",               file: "osd-mic",                type: "bool" },
        { name: "osdBrightness",        file: "osd-brightness",         type: "bool" },
        { name: "osdKbBacklight",       file: "osd-kb-backlight",       type: "bool" },
        { name: "sysmonInterval",       file: "sysmon-interval",        type: "int"  },
        { name: "calendarFetchInterval", file: "calendar-fetch-interval", type: "int" },
        { name: "wallpaperDir",         file: "wallpaper-dir",          type: "string" },
        { name: "flyoutSizes",          file: "flyout-sizes.json",      type: "json" },
        { name: "barPlacement",         file: "bar-placement.json",     type: "json" },
        { name: "trayPlacement",        file: "tray-placement.json",    type: "json" },
        { name: "qaPlacement",          file: "qa-placement.json",      type: "json" },
        { name: "hiddenApps",           file: "hidden-apps.json",       type: "json" },
        { name: "iconThemeRecents",     file: "icon-theme-recents.json", type: "json" },
        { name: "cursorThemeRecents",   file: "cursor-theme-recents.json", type: "json" },
        { name: "btLastConnected",      file: "bt-last-connected.json", type: "json" },
        { name: "clock24h",             file: "clock-24h",              type: "bool" },
        { name: "clockShowSeconds",     file: "clock-seconds",          type: "bool" },
        { name: "clockDateFormat",      file: "clock-date-format",      type: "string" },
        { name: "animScale",            file: "anim-scale",             type: "real" },
        { name: "animations",           file: "animations",             type: "bool" },
        { name: "gamemodeEffects", file: "gamemode-effects", type: "bool" },
        { name: "gamemodePerformance", file: "gamemode-performance", type: "bool" },
        { name: "gamemodeHideBar", file: "gamemode-hide-bar", type: "bool" },
        { name: "gamemodeDnd", file: "gamemode-dnd", type: "bool" },
        { name: "gamemodeSyncs", file: "gamemode-syncs", type: "bool" },
        { name: "gamemodeNight", file: "gamemode-night", type: "bool" },
        { name: "gamemodeDocker", file: "gamemode-docker", type: "bool" },
        { name: "gamemodeAwake", file: "gamemode-awake", type: "bool" },
        { name: "gamemodeTailscale", file: "gamemode-tailscale", type: "bool" },
        { name: "gamemodeFeral", file: "gamemode-feral", type: "bool" },
        { name: "gameLauncherGames", file: "game-launcher-games", type: "bool" },
        { name: "radiusScale",          file: "radius-scale",           type: "real" },
        { name: "barOpacity",           file: "bar-opacity",            type: "real" },
        { name: "batteryCriticalPct",   file: "battery-critical-pct",   type: "int"  },
        { name: "batteryCriticalAction", file: "battery-critical-action", type: "string" },
        { name: "toastPosition",        file: "toast-position",         type: "string" },
        { name: "toastMax",             file: "toast-max",              type: "int"  },
        { name: "toastWidth",           file: "toast-width",            type: "int"  },
        { name: "notifGroupByApp",      file: "notif-group-by-app",     type: "bool" },
        { name: "notifAutoExpire",      file: "notif-auto-expire",      type: "bool" },
        { name: "notifAutoExpireRules", file: "notif-auto-expire-rules.json", type: "json" },
        { name: "notifAutoExpireDelay", file: "notif-auto-expire-delay", type: "int"  },
        { name: "dnd",                  file: "dnd",                    type: "bool" },
        { name: "dndSchedule",          file: "dnd-schedule",           type: "bool" },
        { name: "dndFrom",              file: "dnd-from",               type: "string" },
        { name: "dndTo",                file: "dnd-to",                 type: "string" },
        { name: "notifSounds",          file: "notif-sounds",           type: "bool" },
        { name: "notifAppRules",        file: "notif-app-rules.json",   type: "json" },
        { name: "notifAppsSeen",        file: "notif-apps-seen.json",   type: "json" },
        { name: "weekStartMonday",      file: "week-start-monday",      type: "bool" },
        { name: "windowTitleWidth",     file: "window-title-width",     type: "int"  },
        { name: "osdBottomMargin",      file: "osd-bottom-margin",      type: "int"  },
        { name: "sysmonShowCpu",        file: "sysmon-show-cpu",        type: "bool" },
        { name: "sysmonShowRam",        file: "sysmon-show-ram",        type: "bool" },
        { name: "sysmonShowStorage",    file: "sysmon-show-storage",    type: "bool" },
        { name: "sysmonShowThermal",    file: "sysmon-show-thermal",    type: "bool" },
        { name: "workspaceGlyphs",      file: "workspace-glyphs",       type: "bool" },
        { name: "workspaceWindowIcons", file: "workspace-window-icons", type: "bool" },
        { name: "spotlightCalc",        file: "spotlight-calc",         type: "bool" },
        { name: "spotlightActions",     file: "spotlight-actions",      type: "bool" },
        { name: "clipboardThumbs",      file: "clipboard-thumbs",       type: "bool" },
        { name: "barWheelAction",       file: "bar-wheel-action",       type: "string" },
        { name: "volumeStep",           file: "volume-step",            type: "int"  },
        { name: "brightnessStep",       file: "brightness-step",        type: "int"  },
        { name: "maxVolume",            file: "max-volume",             type: "int"  },
        { name: "alertVolume",          file: "alert-volume",           type: "int"  },
        { name: "powerOnAc",            file: "power-on-ac",            type: "string" },
        { name: "powerOnBattery",       file: "power-on-battery",       type: "string" },
        { name: "powerSaverBelow",      file: "power-saver-below",      type: "int"  },
        { name: "idleInhibitOnMedia",   file: "idle-inhibit-media",     type: "bool" },
        { name: "idleInhibitOnPower",   file: "idle-inhibit-power",     type: "bool" },
        { name: "idleStayAwake",        file: "idle-stay-awake",        type: "bool" },
        { name: "idleHoldClaude",       file: "idle-hold-claude",       type: "bool" },
        { name: "lidCloseAction",       file: "lid-close-action",       type: "string" },
        { name: "lockShowMedia",        file: "lock-show-media",        type: "bool" },
        { name: "lockShowWeather",      file: "lock-show-weather",      type: "bool" },
        { name: "lockShowBattery",      file: "lock-show-battery",      type: "bool" },
        { name: "batteryLowPct",        file: "battery-low-pct",        type: "int"  },
        { name: "batteryWarnPct",       file: "battery-warn-pct",       type: "int"  },
        { name: "nightTemperature",     file: "night-temperature",      type: "int"  },
        { name: "nightSchedule",        file: "night-schedule",         type: "bool" },
        { name: "nightFrom",            file: "night-from",             type: "string" },
        { name: "nightTo",              file: "night-to",               type: "string" },
        { name: "eventToasts",          file: "event-toasts.json",      type: "json" },
        { name: "weatherLocation",      file: "weather-location",       type: "string" },
        { name: "weatherFahrenheit",    file: "weather-fahrenheit",     type: "bool" },
        { name: "shotDir",              file: "shot-dir",               type: "string" },
        { name: "shotFormat",           file: "shot-format",            type: "string" },
        { name: "shotCursor",           file: "shot-cursor",            type: "bool" },
        { name: "shotClipboard",        file: "shot-clipboard",         type: "bool" },
        { name: "shotActions",          file: "shot-actions",           type: "bool" },
        { name: "recordDir",            file: "record-dir",             type: "string" },
        { name: "recordContainer",      file: "record-container",       type: "string" },
        { name: "recordFps",            file: "record-fps",             type: "int"  },
        { name: "recordQuality",        file: "record-quality",         type: "string" },
        { name: "recordCodec",          file: "record-codec",           type: "string" },
        { name: "recordCursor",         file: "record-cursor",          type: "bool" },
        { name: "recordAudio",          file: "record-audio",           type: "string" },
    ]

    // Settings live under ~/.config (they're user prefs, not cache — a
    // cache wipe must not eat the bar layout). The dir is gitignored in
    // the dotfiles repo, like calendar.url.
    readonly property string _dir: Quickshell.env("HOME") + "/.config/quickshell/settings/"

    // Returns undefined when the text is not a valid value of the type.
    function _parse(type, text) {
        switch (type) {
        case "bool":   return text.trim() === "1";
        case "int":  { const n = parseInt(text.trim(), 10); return isFinite(n) ? n : undefined; }
        case "real": { const n = parseFloat(text.trim()); return isFinite(n) ? n : undefined; }
        case "json":   try { return JSON.parse(text); } catch (e) { return undefined; }
        default:       return text.endsWith("\n") ? text.slice(0, -1) : text;
        }
    }
    // A loaded JSON value must have the shape of the current one: an array
    // stays an array, an object stays an object.
    function _sameShape(current, value) {
        if (Array.isArray(current)) return Array.isArray(value);
        if (current !== null && typeof current === "object")
            return value !== null && typeof value === "object" && !Array.isArray(value);
        return true;
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
                const value = settings._parse(modelData.type, t);
                // An invalid file keeps the current value and is left on disk
                // untouched, so a typo in a hand edit does not wipe it.
                if (value === undefined || !settings._sameShape(settings[modelData.name], value))
                    console.warn("[Settings] ignoring invalid " + modelData.file);
                else
                    settings[modelData.name] = value;
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
