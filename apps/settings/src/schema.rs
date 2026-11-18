//! The panels, and the Quickshell settings each one shows. Files, types and
//! defaults mirror the `_schema` table and property defaults in
//! config/quickshell/Settings.qml; a test checks every file here exists there.

use crate::store::{Kind, Value, home};
use lucide_iced::bytes as ico;

pub struct Panel {
    /// Name for `settings --panel <id>`.
    pub id: &'static str,
    pub title: &'static str,
    /// Lucide icon for the sidebar.
    pub glyph: crate::ui::Icon,
    /// The sidebar group it is listed under.
    pub group: Group,
    /// What the panel shows.
    pub page: Page,
    /// More words search finds the panel by.
    pub keywords: &'static str,
    /// The settings of a `Page::Settings` panel.
    pub sections: &'static [Section],
}

/// Sidebar groups, in sidebar order (like KDE System Settings).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Group {
    Connections,
    InputOutput,
    Appearance,
    Workspace,
    System,
}

impl Group {
    pub fn title(self) -> &'static str {
        match self {
            Group::Connections => "Connections",
            Group::InputOutput => "Input & output",
            Group::Appearance => "Appearance",
            Group::Workspace => "Workspace",
            Group::System => "System",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Page {
    /// Settings from the Quickshell settings store.
    Settings,
    /// Wi-Fi, wired and VPN (network.rs).
    Network,
    /// Bluetooth devices (bluetooth.rs).
    Bluetooth,
    /// Audio devices and app volumes (audio.rs).
    Sound,
    /// Calendar feeds (calendar.rs), then the panel's settings.
    Calendar,
    /// Keyboard layouts and repeat in Hyprland (keyboard.rs, hypr.rs).
    Keyboard,
    /// Mouse, touchpad and gesture options in Hyprland (mouse.rs).
    Mouse,
    /// Where bar, Quick Actions and tray items show (placement.rs).
    BarItems,
    /// Idle timings from hypridle.conf (idle.rs), then the panel's settings.
    Lock,
    /// Icon and cursor themes (themes.rs).
    Themes,
    /// Key binds moved to other keys (shortcuts.rs).
    Shortcuts,
    /// Launcher settings followed by the hidden apps (hiddenapps.rs).
    Launcher,
    /// Notification settings followed by per-app rules (notifapps.rs).
    Notifications,
    /// Which app fills each role (defaultapps.rs).
    DefaultApps,
    /// Window gaps, borders, effects and focus in Hyprland (windows.rs).
    Windows,
    /// What the system is (about.rs).
    About,
    /// The battery above the power settings (power.rs).
    Power,
}

pub struct Section {
    pub title: &'static str,
    pub settings: &'static [Setting],
}

pub struct Setting {
    /// File name in the settings store.
    pub file: &'static str,
    pub label: &'static str,
    pub help: &'static str,
    pub control: Control,
    pub default: Default,
}

pub enum Control {
    Toggle,
    /// Integer slider.
    Number {
        min: i64,
        max: i64,
        step: i64,
        unit: &'static str,
    },
    /// Real slider, shown as a multiplier (1.25×) or a percentage.
    Scale {
        min: f64,
        max: f64,
        step: f64,
        percent: bool,
    },
    /// One of a fixed set of strings: (stored value, label).
    Choice(&'static [(&'static str, &'static str)]),
    /// Free text, applied on Enter.
    Entry {
        placeholder: &'static str,
    },
    /// JSON object of named on/off flags: (key, label); a multi-select
    /// button group.
    Flags(&'static [(&'static str, &'static str)]),
    /// Several on/off settings, each in its own file, as one multi-select
    /// button group. The setting's own `file` is the first one's.
    Toggles(&'static [Toggle]),
    /// An installed font family, picked from a search list.
    Font,
    /// A folder: a text field with a Browse button (zenity).
    Folder {
        placeholder: &'static str,
    },
    /// A list of texts (JSON array), shown as removable pills with an input
    /// group to add one.
    Pills {
        placeholder: &'static str,
    },
    /// One of a few numbers, as a button group: (value, label).
    NumberChoice(&'static [(i64, &'static str)]),
    /// Two options that can each be on, stored in one text file as `none`,
    /// either option's value, or `both` (a multi-select of two).
    Pair {
        options: [(&'static str, &'static str); 2],
        none: &'static str,
        both: &'static str,
    },
}

/// One button of a `Control::Toggles` group.
pub struct Toggle {
    pub file: &'static str,
    pub label: &'static str,
    pub default: bool,
}

pub enum Default {
    Bool(bool),
    Int(i64),
    Real(f64),
    Text(&'static str),
    /// A path under $HOME.
    HomePath(&'static str),
    Flags(&'static [(&'static str, bool)]),
    List(&'static [&'static str]),
}

impl Control {
    pub fn name(&self) -> &'static str {
        match self {
            Control::Toggle => "a toggle",
            Control::Number { .. } => "a number",
            Control::Scale { .. } => "a scale",
            Control::Choice(_) => "a choice",
            Control::Entry { .. } => "a text entry",
            Control::Flags(_) => "a list of flags",
            Control::Toggles(_) => "a group of switches",
            Control::NumberChoice(_) => "a choice of numbers",
            Control::Font => "a font picker",
            Control::Folder { .. } => "a folder",
            Control::Pills { .. } => "a list of texts",
            Control::Pair { .. } => "a pair of switches",
        }
    }
}

impl Setting {
    pub fn kind(&self) -> Kind {
        match self.control {
            Control::Toggle => Kind::Bool,
            Control::Number { .. } | Control::NumberChoice(_) => Kind::Int,
            Control::Scale { .. } => Kind::Real,
            Control::Choice(_)
            | Control::Entry { .. }
            | Control::Pair { .. }
            | Control::Font
            | Control::Folder { .. } => Kind::Text,
            Control::Toggles(_) => Kind::Bool,
            Control::Flags(_) | Control::Pills { .. } => Kind::Json,
        }
    }

    /// Every file this setting stores, with its type and default: one, or
    /// one per button of a `Toggles` group.
    pub fn files(&self) -> Vec<(&'static str, Kind, Value)> {
        match self.control {
            Control::Toggles(toggles) => toggles
                .iter()
                .map(|t| (t.file, Kind::Bool, Value::Bool(t.default)))
                .collect(),
            _ => vec![(self.file, self.kind(), self.default_value())],
        }
    }

    pub fn default_value(&self) -> Value {
        match self.default {
            Default::Bool(b) => Value::Bool(b),
            Default::Int(n) => Value::Int(n),
            Default::Real(n) => Value::Real(n),
            Default::Text(s) => Value::Text(s.to_string()),
            Default::HomePath(p) => Value::Text(home().join(p).to_string_lossy().into_owned()),
            Default::List(items) => Value::Json(serde_json::Value::Array(
                items.iter().map(|i| serde_json::Value::String(i.to_string())).collect(),
            )),
            Default::Flags(flags) => Value::Json(serde_json::Value::Object(
                flags
                    .iter()
                    .map(|(k, v)| (k.to_string(), serde_json::Value::Bool(*v)))
                    .collect(),
            )),
        }
    }
}

const fn toggle(file: &'static str, label: &'static str, help: &'static str, default: bool) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Toggle,
        default: Default::Bool(default),
    }
}

#[allow(clippy::too_many_arguments)]
const fn number(
    file: &'static str,
    label: &'static str,
    help: &'static str,
    min: i64,
    max: i64,
    step: i64,
    unit: &'static str,
    default: i64,
) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Number { min, max, step, unit },
        default: Default::Int(default),
    }
}

const fn scale(
    file: &'static str,
    label: &'static str,
    help: &'static str,
    min: f64,
    max: f64,
    step: f64,
    percent: bool,
) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Scale {
            min,
            max,
            step,
            percent,
        },
        default: Default::Real(1.0),
    }
}

/// Whole hours of a day, for do not disturb times.
const HOURS: &[(&str, &str)] = &[
    ("00:00", "00:00"),
    ("01:00", "01:00"),
    ("02:00", "02:00"),
    ("03:00", "03:00"),
    ("04:00", "04:00"),
    ("05:00", "05:00"),
    ("06:00", "06:00"),
    ("07:00", "07:00"),
    ("08:00", "08:00"),
    ("09:00", "09:00"),
    ("10:00", "10:00"),
    ("11:00", "11:00"),
    ("12:00", "12:00"),
    ("13:00", "13:00"),
    ("14:00", "14:00"),
    ("15:00", "15:00"),
    ("16:00", "16:00"),
    ("17:00", "17:00"),
    ("18:00", "18:00"),
    ("19:00", "19:00"),
    ("20:00", "20:00"),
    ("21:00", "21:00"),
    ("22:00", "22:00"),
    ("23:00", "23:00"),
];

const fn choice(
    file: &'static str,
    label: &'static str,
    help: &'static str,
    options: &'static [(&'static str, &'static str)],
    default: &'static str,
) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Choice(options),
        default: Default::Text(default),
    }
}

const fn entry(
    file: &'static str,
    label: &'static str,
    help: &'static str,
    placeholder: &'static str,
    default: Default,
) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Entry { placeholder },
        default,
    }
}

/// Times of day in half hours, for the night light schedule.
const HALF_HOURS: &[(&str, &str)] = &[
    ("00:00", "00:00"),
    ("00:30", "00:30"),
    ("01:00", "01:00"),
    ("01:30", "01:30"),
    ("02:00", "02:00"),
    ("02:30", "02:30"),
    ("03:00", "03:00"),
    ("03:30", "03:30"),
    ("04:00", "04:00"),
    ("04:30", "04:30"),
    ("05:00", "05:00"),
    ("05:30", "05:30"),
    ("06:00", "06:00"),
    ("06:30", "06:30"),
    ("07:00", "07:00"),
    ("07:30", "07:30"),
    ("08:00", "08:00"),
    ("08:30", "08:30"),
    ("09:00", "09:00"),
    ("09:30", "09:30"),
    ("10:00", "10:00"),
    ("10:30", "10:30"),
    ("11:00", "11:00"),
    ("11:30", "11:30"),
    ("12:00", "12:00"),
    ("12:30", "12:30"),
    ("13:00", "13:00"),
    ("13:30", "13:30"),
    ("14:00", "14:00"),
    ("14:30", "14:30"),
    ("15:00", "15:00"),
    ("15:30", "15:30"),
    ("16:00", "16:00"),
    ("16:30", "16:30"),
    ("17:00", "17:00"),
    ("17:30", "17:30"),
    ("18:00", "18:00"),
    ("18:30", "18:30"),
    ("19:00", "19:00"),
    ("19:30", "19:30"),
    ("20:00", "20:00"),
    ("20:30", "20:30"),
    ("21:00", "21:00"),
    ("21:30", "21:30"),
    ("22:00", "22:00"),
    ("22:30", "22:30"),
    ("23:00", "23:00"),
    ("23:30", "23:30"),
];

/// A folder setting under $HOME by default.
const fn folder(
    file: &'static str,
    label: &'static str,
    help: &'static str,
    placeholder: &'static str,
    default: &'static str,
) -> Setting {
    Setting {
        file,
        label,
        help,
        control: Control::Folder { placeholder },
        default: Default::HomePath(default),
    }
}

const ACCENTS: &[(&str, &str)] = &[
    ("auto", "From wallpaper"),
    ("orange", "Orange"),
    ("blue", "Blue"),
    ("green", "Green"),
    ("red", "Red"),
    ("yellow", "Yellow"),
    ("purple", "Purple"),
    ("pink", "Pink"),
    ("teal", "Teal"),
    ("slate", "Slate"),
];

pub const PANELS: &[Panel] = &[
    Panel {
        id: "network",
        title: "Network",
        glyph: ico::WIFI,
        group: Group::Connections,
        page: Page::Network,
        keywords: "wifi wi-fi wireless wlan internet ethernet wired vpn wireguard",
        sections: &[],
    },
    Panel {
        id: "bluetooth",
        title: "Bluetooth",
        glyph: ico::BLUETOOTH,
        group: Group::Connections,
        page: Page::Bluetooth,
        keywords: "devices headphones headset airpods speaker mouse keyboard pair",
        sections: &[],
    },
    Panel {
        id: "sound",
        title: "Sound",
        glyph: ico::SPEAKER,
        group: Group::InputOutput,
        page: Page::Sound,
        keywords: "audio speakers headphones microphone mic input output volume mute apps",
        sections: &[],
    },
    Panel {
        id: "keyboard",
        title: "Keyboard",
        glyph: ico::KEYBOARD,
        group: Group::InputOutput,
        page: Page::Keyboard,
        keywords: "layout language xkb input repeat delay caps lock num lock typing",
        sections: &[],
    },
    Panel {
        id: "shortcuts",
        title: "Keyboard shortcuts",
        glyph: ico::COMMAND,
        group: Group::InputOutput,
        page: Page::Shortcuts,
        keywords: "keybinds keys bind hotkeys shortcuts super rebind",
        sections: &[],
    },
    Panel {
        id: "mouse",
        title: "Mouse & touchpad",
        glyph: ico::MOUSE,
        group: Group::InputOutput,
        page: Page::Mouse,
        keywords: "pointer cursor speed acceleration scroll wheel touchpad trackpad tap click gestures swipe left-handed",
        sections: &[],
    },
    Panel {
        id: "osd",
        title: "Volume & OSD",
        glyph: ico::VOLUME_2,
        group: Group::InputOutput,
        page: Page::Settings,
        keywords: "",
        sections: &[
            Section {
                title: "Steps",
                settings: &[
                    number(
                        "volume-step",
                        "Volume step",
                        "Change per scroll tick or arrow press",
                        1,
                        20,
                        1,
                        "%",
                        5,
                    ),
                    number(
                        "brightness-step",
                        "Brightness step",
                        "Change per scroll tick or arrow press",
                        1,
                        20,
                        1,
                        "%",
                        5,
                    ),
                    number(
                        "max-volume",
                        "Maximum volume",
                        "Ceiling for every volume control",
                        50,
                        150,
                        5,
                        "%",
                        100,
                    ),
                ],
            },
            Section {
                title: "On-screen display",
                settings: &[
                    number(
                        "osd-duration",
                        "Time on screen",
                        "How long the volume and brightness display stays",
                        500,
                        5000,
                        100,
                        "ms",
                        1500,
                    ),
                    number(
                        "osd-bottom-margin",
                        "Distance from bottom",
                        "Gap between the display and the screen edge",
                        0,
                        300,
                        10,
                        "px",
                        60,
                    ),
                ],
            },
        ],
    },
    Panel {
        id: "appearance",
        title: "Appearance",
        glyph: ico::PALETTE,
        group: Group::Appearance,
        page: Page::Settings,
        keywords: "",
        sections: &[
            Section {
                title: "Colour",
                settings: &[
                    choice(
                        "accent-primary",
                        "Accent colour",
                        "Highlight colour of the shell",
                        ACCENTS,
                        "orange",
                    ),
                    toggle(
                        "accent-everywhere",
                        "Accent everywhere",
                        "Use the accent colour for every coloured icon and highlight; red, green and yellow keep their meaning",
                        true,
                    ),
                ],
            },
            Section {
                title: "Night light",
                settings: &[
                    number(
                        "night-temperature",
                        "Colour temperature",
                        "Lower is warmer; Super+Ctrl+N switches the night light",
                        2500,
                        6500,
                        100,
                        "K",
                        4000,
                    ),
                    toggle(
                        "night-schedule",
                        "On a schedule",
                        "Warm from the start time until the end time",
                        false,
                    ),
                    choice("night-from", "From", "When the warm colour starts", HALF_HOURS, "21:00"),
                    choice(
                        "night-to",
                        "Until",
                        "When the normal colour comes back",
                        HALF_HOURS,
                        "07:00",
                    ),
                ],
            },
            Section {
                title: "Text",
                settings: &[
                    Setting {
                        file: "font-family",
                        label: "Font",
                        help: "Font family of the shell; a Nerd Font keeps the icons",
                        control: Control::Font,
                        default: Default::Text("Iosevka Nerd Font"),
                    },
                    scale(
                        "font-scale",
                        "Text size",
                        "Multiplies every text size",
                        0.8,
                        1.5,
                        0.05,
                        false,
                    ),
                ],
            },
            Section {
                title: "Shape and motion",
                settings: &[
                    scale(
                        "radius-scale",
                        "Corner roundness",
                        "Multiplies every corner radius",
                        0.0,
                        2.0,
                        0.1,
                        false,
                    ),
                    toggle(
                        "animations",
                        "Animations",
                        "Animate the shell, windows and GTK apps; off makes everything instant",
                        true,
                    ),
                    scale(
                        "anim-scale",
                        "Animation speed",
                        "Multiplies every animation duration; 0 turns them off",
                        0.0,
                        2.0,
                        0.1,
                        false,
                    ),
                ],
            },
            Section {
                title: "Wallpaper",
                settings: &[folder(
                    "wallpaper-dir",
                    "Wallpaper folder",
                    "Where the wallpaper deck deals cards from",
                    "~/Pictures/wallpapers",
                    "Pictures/wallpapers",
                )],
            },
        ],
    },
    Panel {
        id: "themes",
        title: "Icons & cursors",
        glyph: ico::SHAPES,
        group: Group::Appearance,
        page: Page::Themes,
        keywords: "icon theme cursor pointer papirus breeze adwaita hyprcursor xcursor",
        sections: &[],
    },
    Panel {
        id: "windows",
        title: "Windows",
        glyph: ico::APP_WINDOW,
        group: Group::Appearance,
        page: Page::Windows,
        keywords: "gaps border rounding blur shadow animations opacity tiling dwindle master focus follows mouse",
        sections: &[],
    },
    Panel {
        id: "bar",
        title: "Bar",
        glyph: ico::PANEL_TOP,
        group: Group::Appearance,
        page: Page::Settings,
        keywords: "",
        sections: &[
            Section {
                title: "Size",
                settings: &[
                    number("bar-height", "Height", "Height of the bar", 24, 56, 1, "px", 36),
                    scale(
                        "bar-opacity",
                        "Opacity",
                        "Opacity of the bar background",
                        0.3,
                        1.0,
                        0.05,
                        true,
                    ),
                    number(
                        "window-title-width",
                        "Window title width",
                        "Longest window title in the bar; 0 hides it",
                        0,
                        800,
                        20,
                        "px",
                        400,
                    ),
                ],
            },
            Section {
                title: "Workspaces",
                settings: &[
                    toggle(
                        "workspace-glyphs",
                        "Workspace icons",
                        "Icons instead of numbers in the workspace strip",
                        true,
                    ),
                    toggle(
                        "workspace-window-icons",
                        "Window icons",
                        "Small app icons inside each workspace",
                        false,
                    ),
                ],
            },
            Section {
                title: "Behaviour",
                settings: &[choice(
                    "bar-wheel-action",
                    "Scroll on the bar",
                    "What the mouse wheel does over the bar background",
                    &[
                        ("workspace", "Switch workspace"),
                        ("volume", "Change volume"),
                        ("none", "Nothing"),
                    ],
                    "workspace",
                )],
            },
        ],
    },
    Panel {
        id: "baritems",
        title: "Bar items",
        glyph: ico::MENU,
        group: Group::Appearance,
        page: Page::BarItems,
        keywords: "bar modules quick actions tray icons hide show overflow placement layout",
        sections: &[],
    },
    Panel {
        id: "clock",
        title: "Clock & weather",
        glyph: ico::CLOCK,
        group: Group::Workspace,
        page: Page::Settings,
        keywords: "time date weather temperature forecast location fahrenheit",
        sections: &[
            Section {
                title: "Clock",
                settings: &[
                    toggle("clock-24h", "24-hour clock", "Show 13:00 instead of 1:00 PM", true),
                    toggle("clock-seconds", "Seconds", "Show seconds in the bar clock", false),
                    entry(
                        "clock-date-format",
                        "Date format",
                        "Qt date format of the bar date",
                        "ddd, dd MMM",
                        Default::Text("ddd, dd MMM"),
                    ),
                ],
            },
            Section {
                title: "Weather",
                settings: &[
                    entry(
                        "weather-location",
                        "Location",
                        "City name; empty turns the weather off",
                        "Tallinn",
                        Default::Text(""),
                    ),
                    toggle("weather-fahrenheit", "Fahrenheit", "Show temperatures in °F", false),
                ],
            },
        ],
    },
    Panel {
        id: "calendar",
        title: "Calendar",
        glyph: ico::CALENDAR,
        group: Group::Workspace,
        page: Page::Calendar,
        keywords: "ics webcal feeds events google outlook",
        sections: &[Section {
            title: "Options",
            settings: &[
                toggle(
                    "week-start-monday",
                    "Week starts on Monday",
                    "Otherwise on Sunday",
                    true,
                ),
                number(
                    "calendar-fetch-interval",
                    "Refresh feeds",
                    "Minutes between calendar feed downloads",
                    1,
                    120,
                    1,
                    "min",
                    10,
                ),
            ],
        }],
    },
    Panel {
        id: "notifications",
        title: "Notifications",
        glyph: ico::BELL,
        group: Group::Workspace,
        page: Page::Notifications,
        keywords: "dnd do not disturb quiet mute sound per app",
        sections: &[
            Section {
                title: "Do not disturb",
                settings: &[
                    toggle(
                        "dnd",
                        "Do not disturb",
                        "Hold toasts back; notifications still go to the history",
                        false,
                    ),
                    toggle(
                        "dnd-schedule",
                        "Every day",
                        "Turn do not disturb on between the times below",
                        false,
                    ),
                    choice("dnd-from", "From", "When the quiet time starts", HOURS, "22:00"),
                    choice(
                        "dnd-to",
                        "Until",
                        "When it ends, the next day if earlier",
                        HOURS,
                        "07:00",
                    ),
                ],
            },
            Section {
                title: "Toasts",
                settings: &[
                    choice(
                        "toast-position",
                        "Position",
                        "Where new notifications appear",
                        &[("center", "Top centre"), ("right", "Top right")],
                        "center",
                    ),
                    number(
                        "toast-timeout",
                        "Time on screen",
                        "Longest a toast stays, critical ones included",
                        2000,
                        30000,
                        1000,
                        "ms",
                        10000,
                    ),
                    number(
                        "toast-max",
                        "Toasts at once",
                        "Most toasts stacked on screen",
                        1,
                        10,
                        1,
                        "",
                        5,
                    ),
                    number("toast-width", "Width", "Width of a toast", 300, 600, 10, "px", 380),
                    toggle("notif-sounds", "Sound", "Play a sound with each toast", false),
                ],
            },
            Section {
                title: "History",
                settings: &[
                    number(
                        "notif-history-cap",
                        "History size",
                        "Notifications kept in the notification center",
                        10,
                        200,
                        10,
                        "",
                        50,
                    ),
                    toggle("notif-group-by-app", "Group by app", "Group the history by app", true),
                ],
            },
            Section {
                title: "Auto-dismiss",
                settings: &[
                    toggle(
                        "notif-auto-expire",
                        "Dismiss matching notifications",
                        "Remove matching notifications from the history on their own",
                        true,
                    ),
                    Setting {
                        file: "notif-auto-expire-rules.json",
                        label: "Rules",
                        help: "A notification whose app name or summary contains one of these is dismissed",
                        control: Control::Pills {
                            placeholder: "Add a rule, e.g. Claude Code",
                        },
                        default: Default::List(&["Claude Code"]),
                    },
                    number(
                        "notif-auto-expire-delay",
                        "After",
                        "How long a matching notification stays",
                        1000,
                        60000,
                        1000,
                        "ms",
                        10000,
                    ),
                ],
            },
            Section {
                title: "System events",
                settings: &[Setting {
                    file: "event-toasts.json",
                    label: "Show a toast for",
                    help: "Events that pop up a toast",
                    control: Control::Flags(&[
                        ("charger", "Charger"),
                        ("vpn", "VPN"),
                        ("audio", "Audio output"),
                        ("layout", "Keyboard layout"),
                    ]),
                    default: Default::Flags(&[("charger", true), ("vpn", true), ("audio", false), ("layout", false)]),
                }],
            },
        ],
    },
    Panel {
        id: "launcher",
        title: "Launcher & clipboard",
        glyph: ico::LAYOUT_GRID,
        group: Group::Workspace,
        page: Page::Launcher,
        keywords: "spotlight search hidden apps calculator quick actions clipboard",
        sections: &[
            Section {
                title: "Launcher",
                settings: &[
                    number(
                        "spotlight-cap",
                        "Results shown",
                        "Most results the launcher lists",
                        10,
                        200,
                        10,
                        "",
                        60,
                    ),
                    Setting {
                        file: "spotlight-calc",
                        label: "Also show",
                        help: "Besides apps: the answer when the search is a sum, and quick actions like Do not disturb",
                        control: Control::Toggles(&[
                            Toggle {
                                file: "spotlight-calc",
                                label: "Calculator",
                                default: true,
                            },
                            Toggle {
                                file: "spotlight-actions",
                                label: "Quick actions",
                                default: true,
                            },
                        ]),
                        default: Default::Bool(true),
                    },
                ],
            },
            Section {
                title: "Clipboard",
                settings: &[toggle(
                    "clipboard-thumbs",
                    "Image thumbnails",
                    "Show thumbnails of images in the clipboard history",
                    true,
                )],
            },
        ],
    },
    Panel {
        id: "apps",
        title: "Default apps",
        glyph: ico::APP_WINDOW,
        group: Group::Workspace,
        page: Page::DefaultApps,
        keywords: "default applications browser mail terminal editor files image viewer video music pdf open with",
        sections: &[],
    },
    Panel {
        id: "recording",
        title: "Screenshots & recording",
        glyph: ico::VIDEO,
        group: Group::System,
        page: Page::Settings,
        keywords: "screenshot capture grim picture record video gpu-screen-recorder screencast",
        sections: &[
            Section {
                title: "Screenshots",
                settings: &[
                    folder(
                        "shot-dir",
                        "Folder",
                        "Where screenshots are saved",
                        "~/Pictures/Screenshots",
                        "Pictures/Screenshots",
                    ),
                    choice(
                        "shot-format",
                        "File type",
                        "PNG keeps every pixel; JPEG makes smaller files",
                        &[("png", "PNG"), ("jpg", "JPEG")],
                        "png",
                    ),
                    Setting {
                        file: "shot-cursor",
                        label: "With every screenshot",
                        help: "Capture the cursor, copy it to the clipboard, offer Edit, OCR and Reveal after a region shot",
                        control: Control::Toggles(&[
                            Toggle {
                                file: "shot-cursor",
                                label: "Cursor",
                                default: false,
                            },
                            Toggle {
                                file: "shot-clipboard",
                                label: "Copy to clipboard",
                                default: true,
                            },
                            Toggle {
                                file: "shot-actions",
                                label: "Show actions",
                                default: true,
                            },
                        ]),
                        default: Default::Bool(false),
                    },
                ],
            },
            Section {
                title: "Recording files",
                settings: &[
                    folder(
                        "record-dir",
                        "Folder",
                        "Where recordings are saved",
                        "~/Videos/Recordings",
                        "Videos/Recordings",
                    ),
                    choice(
                        "record-container",
                        "File type",
                        "Container of the video file",
                        &[("mp4", "MP4"), ("mkv", "MKV"), ("webm", "WebM")],
                        "mp4",
                    ),
                ],
            },
            Section {
                title: "Recording video",
                settings: &[
                    Setting {
                        file: "record-fps",
                        label: "Frame rate",
                        help: "Frames per second",
                        control: Control::NumberChoice(&[
                            (30, "30 fps"),
                            (60, "60 fps"),
                            (120, "120 fps"),
                            (144, "144 fps"),
                        ]),
                        default: Default::Int(60),
                    },
                    choice(
                        "record-quality",
                        "Quality",
                        "Higher quality makes bigger files",
                        &[
                            ("medium", "Medium"),
                            ("high", "High"),
                            ("very_high", "Very high"),
                            ("ultra", "Ultra"),
                        ],
                        "very_high",
                    ),
                    choice(
                        "record-codec",
                        "Codec",
                        "Video codec; WebM needs VP9 or AV1",
                        &[
                            ("auto", "Automatic"),
                            ("h264", "H.264"),
                            ("hevc", "HEVC"),
                            ("av1", "AV1"),
                            ("vp9", "VP9"),
                        ],
                        "auto",
                    ),
                    toggle(
                        "record-cursor",
                        "Record the cursor",
                        "Show the mouse pointer in the video",
                        true,
                    ),
                ],
            },
            Section {
                title: "Recording audio",
                settings: &[Setting {
                    file: "record-audio",
                    label: "Sound",
                    help: "What sound goes into the recording; none when both are off",
                    control: Control::Pair {
                        options: [("output", "System sound"), ("input", "Microphone")],
                        none: "none",
                        both: "both",
                    },
                    default: Default::Text("none"),
                }],
            },
        ],
    },
    Panel {
        id: "sysmon",
        title: "System monitor",
        glyph: ico::CPU,
        group: Group::System,
        page: Page::Settings,
        keywords: "",
        sections: &[
            Section {
                title: "Refresh",
                settings: &[number(
                    "sysmon-interval",
                    "Interval",
                    "Time between refreshes",
                    500,
                    5000,
                    500,
                    "ms",
                    1500,
                )],
            },
            Section {
                title: "Sections",
                settings: &[Setting {
                    file: "sysmon-show-cpu",
                    label: "Shown",
                    help: "Sections of the system monitor: processor, memory, storage, temperatures and fans",
                    control: Control::Toggles(&[
                        Toggle {
                            file: "sysmon-show-cpu",
                            label: "CPU",
                            default: true,
                        },
                        Toggle {
                            file: "sysmon-show-ram",
                            label: "Memory",
                            default: true,
                        },
                        Toggle {
                            file: "sysmon-show-storage",
                            label: "Storage",
                            default: true,
                        },
                        Toggle {
                            file: "sysmon-show-thermal",
                            label: "Temperatures",
                            default: true,
                        },
                    ]),
                    default: Default::Bool(true),
                }],
            },
        ],
    },
    Panel {
        id: "lock",
        title: "Lock & idle",
        glyph: ico::LOCK,
        group: Group::System,
        page: Page::Lock,
        keywords: "idle dim lock screen off suspend sleep lid hyprlock hypridle stay awake timeout",
        sections: &[
            Section {
                title: "Stay awake",
                settings: &[
                    toggle("idle-stay-awake", "Stay awake", "Never dim, lock or sleep", false),
                    Setting {
                        file: "idle-inhibit-media",
                        label: "Also stay awake",
                        help: "While something is playing, or while the charger is plugged in",
                        control: Control::Toggles(&[
                            Toggle {
                                file: "idle-inhibit-media",
                                label: "While media plays",
                                default: false,
                            },
                            Toggle {
                                file: "idle-inhibit-power",
                                label: "On AC",
                                default: false,
                            },
                        ]),
                        default: Default::Bool(false),
                    },
                ],
            },
            Section {
                title: "Lid",
                settings: &[choice(
                    "lid-close-action",
                    "When the lid closes",
                    "Unless an external display is connected",
                    &[
                        ("lock", "Lock"),
                        ("suspend", "Suspend"),
                        ("nothing", "Turn the screen off"),
                    ],
                    "lock",
                )],
            },
            Section {
                title: "Lock screen",
                settings: &[Setting {
                    file: "lock-show-media",
                    label: "Show",
                    help: "What the lock screen shows besides the clock",
                    control: Control::Toggles(&[
                        Toggle {
                            file: "lock-show-media",
                            label: "Now playing",
                            default: true,
                        },
                        Toggle {
                            file: "lock-show-weather",
                            label: "Weather",
                            default: true,
                        },
                        Toggle {
                            file: "lock-show-battery",
                            label: "Battery",
                            default: true,
                        },
                    ]),
                    default: Default::Bool(true),
                }],
            },
        ],
    },
    Panel {
        id: "power",
        title: "Power",
        glyph: ico::BATTERY_CHARGING,
        group: Group::System,
        page: Page::Power,
        keywords: "battery critical suspend health charge cycles capacity temperature",
        sections: &[Section {
            title: "Low battery",
            settings: &[
                number(
                    "battery-critical-pct",
                    "Action level",
                    "Level that starts the countdown to the action below; 0 turns it off",
                    0,
                    30,
                    1,
                    "%",
                    5,
                ),
                number(
                    "battery-low-pct",
                    "Low warning",
                    "Show a warning at this level",
                    5,
                    50,
                    1,
                    "%",
                    20,
                ),
                number(
                    "battery-warn-pct",
                    "Critical warning",
                    "Show an urgent warning at this level",
                    3,
                    30,
                    1,
                    "%",
                    10,
                ),
                choice(
                    "battery-critical-action",
                    "At critical level",
                    "What happens when the countdown ends",
                    &[("suspend", "Suspend"), ("none", "Nothing")],
                    "suspend",
                ),
            ],
        }],
    },
    Panel {
        id: "about",
        title: "About",
        glyph: ico::INFO,
        group: Group::System,
        page: Page::About,
        keywords: "system version hardware computer kernel cpu gpu memory disk bug report",
        sections: &[],
    },
];

/// Old panel names that now open another panel.
const ALIASES: &[(&str, &str)] = &[("weather", "clock"), ("idle", "lock")];

pub fn panel_index(id: &str) -> Option<usize> {
    let id = ALIASES.iter().find(|(old, _)| *old == id).map_or(id, |(_, new)| new);
    PANELS.iter().position(|p| p.id == id)
}

pub fn all_settings() -> impl Iterator<Item = &'static Setting> {
    PANELS
        .iter()
        .flat_map(|p| p.sections.iter())
        .flat_map(|s| s.settings.iter())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// Every file the app writes is in Settings.qml's `_schema`, with the
    /// same type, so the shell reads what the app writes.
    #[test]
    fn matches_the_quickshell_schema() {
        let qml_path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../config/quickshell/Settings.qml");
        let qml = std::fs::read_to_string(qml_path).expect("Settings.qml");
        for (file, kind, _) in all_settings().flat_map(|s| s.files()) {
            let row = qml
                .lines()
                .find(|l| l.contains(&format!("file: \"{file}\"")))
                .unwrap_or_else(|| panic!("{file} is not in Settings.qml _schema"));
            let qml_type = match kind {
                Kind::Bool => "bool",
                Kind::Int => "int",
                Kind::Real => "real",
                Kind::Text => "string",
                Kind::Json => "json",
            };
            assert!(
                row.contains(&format!("type: \"{qml_type}\"")),
                "{file}: type differs from Settings.qml"
            );
        }
    }

    #[test]
    fn groups_are_contiguous() {
        let mut seen = Vec::new();
        for p in PANELS {
            if seen.last() != Some(&p.group) {
                assert!(!seen.contains(&p.group), "{} splits its group", p.id);
                seen.push(p.group);
            }
        }
    }

    #[test]
    fn ids_and_files_are_unique() {
        let ids: HashSet<_> = PANELS.iter().map(|p| p.id).collect();
        assert_eq!(ids.len(), PANELS.len());
        let files: Vec<_> = all_settings().flat_map(|s| s.files()).map(|(f, _, _)| f).collect();
        let unique: HashSet<_> = files.iter().collect();
        assert_eq!(unique.len(), files.len());
    }

    #[test]
    fn defaults_fit_their_controls() {
        for s in all_settings() {
            let value = s.default_value();
            assert_eq!(value.kind(), s.kind(), "{}", s.file);
            match (&s.control, &value) {
                (Control::Number { min, max, .. }, Value::Int(n)) => assert!((min..=max).contains(&n), "{}", s.file),
                (Control::Scale { min, max, .. }, Value::Real(n)) => assert!(*min <= *n && *n <= *max, "{}", s.file),
                (Control::Choice(options), Value::Text(t)) => {
                    assert!(options.iter().any(|(v, _)| v == t), "{}", s.file)
                }
                _ => {}
            }
        }
    }
}
