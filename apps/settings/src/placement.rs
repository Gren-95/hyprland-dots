//! Bar items panel: where each bar module, Quick Actions item and tray app
//! shows, written to the shell's placement files (Settings.qml):
//! bar-placement.json, qa-placement.json and tray-placement.json map an item
//! to "bar", "overflow" (the Quick Actions panel) or "hidden"; the activity
//! icons are the bool activity-icons.enabled.

use iced::widget::Column;
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;
use serde_json::{Map, Value as Json};

use crate::store::{Kind, Store, Value};
use crate::system::{self, args};
use crate::ui;

const BAR: &str = "bar-placement.json";
const QA: &str = "qa-placement.json";
const TRAY: &str = "tray-placement.json";
const ACTIVITY: &str = "activity-icons.enabled";

/// A place an item can be: (stored value, label).
const ON_BAR: (&str, &str) = ("bar", "On the bar");
const IN_PANEL: (&str, &str) = ("overflow", "In Quick Actions");
const HIDDEN: (&str, &str) = ("hidden", "Hidden");

/// A bar module: its id (the shell's `settingsStore.placement(id)` name),
/// label, glyph, default place and the places it can be.
struct Module {
    id: &'static str,
    label: &'static str,
    glyph: crate::ui::Icon,
    default: &'static str,
    places: &'static [(&'static str, &'static str)],
}

const MODULES: &[Module] = &[
    Module {
        id: "bell",
        label: "Notifications",
        glyph: ico::BELL,
        default: "bar",
        places: &[ON_BAR, HIDDEN],
    },
    Module {
        id: "quickactions",
        label: "Quick Actions button",
        glyph: ico::MENU,
        default: "bar",
        places: &[ON_BAR, HIDDEN],
    },
    Module {
        id: "network",
        label: "Bluetooth",
        glyph: ico::BLUETOOTH,
        default: "bar",
        places: &[ON_BAR, IN_PANEL, HIDDEN],
    },
    Module {
        id: "audiopower",
        label: "Sound",
        glyph: ico::VOLUME_2,
        default: "bar",
        places: &[ON_BAR, IN_PANEL, HIDDEN],
    },
    Module {
        id: "battery",
        label: "Battery",
        glyph: ico::BATTERY_FULL,
        default: "bar",
        places: &[ON_BAR, IN_PANEL, HIDDEN],
    },
    Module {
        id: "mic",
        label: "Microphone (while in use)",
        glyph: ico::MIC,
        default: "bar",
        places: &[ON_BAR, HIDDEN],
    },
];

/// Quick Actions items: (key, label, glyph, default). The shell's
/// `qaPlacementOf(key)`; clipboard defaults to the bar.
const ACTIONS: &[(&str, &str, crate::ui::Icon, &str)] = &[
    ("mic", "Microphone", ico::MIC, "overflow"),
    ("activityicons", "Activity icons", ico::EYE, "overflow"),
    ("clipboard", "Clipboard", ico::CLIPBOARD, "bar"),
    ("screenshot", "Screenshot", ico::CAMERA, "overflow"),
    ("record", "Record", ico::VIDEO, "overflow"),
    ("colorpicker", "Color picker", ico::PIPETTE, "overflow"),
    ("keybinds", "Keybinds", ico::CIRCLE_QUESTION_MARK, "overflow"),
    ("iconscursors", "Icons & cursors", ico::SHAPES, "overflow"),
];

#[derive(Debug, Clone, Default)]
pub struct Snapshot {
    bar: Map<String, Json>,
    qa: Map<String, Json>,
    tray: Map<String, Json>,
    activity: bool,
    /// Tray apps running now: (id the shell uses, title).
    live_tray: Vec<(String, String)>,
}

#[derive(Default)]
pub struct State {
    snapshot: Option<Snapshot>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Snapshot),
    /// (file, item, place)
    Place(&'static str, String, &'static str),
    Activity(bool),
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

fn map_of(file: &str) -> Map<String, Json> {
    match store().read(file, Kind::Json) {
        Some(Value::Json(Json::Object(m))) => m,
        _ => Map::new(),
    }
}

/// Tray items registered with the StatusNotifierWatcher: the shell names an
/// item by its Id, else its Title.
fn live_tray() -> Vec<(String, String)> {
    let bus = |a: &[&str]| system::run_blocking("busctl", &args(a), None).ok();
    let json = |out: Option<String>| {
        out.and_then(|o| serde_json::from_str::<Json>(&o).ok())
            .map(|v| v["data"].clone())
    };
    let watcher = [
        "--user",
        "-j",
        "get-property",
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
    ];
    let items = json(bus(&[
        &watcher[..],
        &["org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems"],
    ]
    .concat()));
    let mut out = Vec::new();
    for item in items
        .as_ref()
        .and_then(Json::as_array)
        .into_iter()
        .flatten()
        .filter_map(Json::as_str)
    {
        let Some((service, path)) = item.split_once('/') else {
            continue;
        };
        let path = format!("/{path}");
        let prop = |name: &str| {
            json(bus(&[
                "--user",
                "-j",
                "get-property",
                service,
                &path,
                "org.kde.StatusNotifierItem",
                name,
            ]))
            .and_then(|v| v.as_str().map(String::from))
            .unwrap_or_default()
        };
        let (id, title) = (prop("Id"), prop("Title"));
        let key = if id.is_empty() { title.clone() } else { id };
        if !key.is_empty() {
            out.push((key, if title.is_empty() { String::new() } else { title }));
        }
    }
    out
}

fn snapshot() -> Snapshot {
    Snapshot {
        bar: map_of(BAR),
        qa: map_of(QA),
        tray: map_of(TRAY),
        activity: !matches!(store().read(ACTIVITY, Kind::Bool), Some(Value::Bool(false))),
        live_tray: live_tray(),
    }
}

fn place_of(map: &Map<String, Json>, key: &str, default: &str) -> String {
    map.get(key).and_then(Json::as_str).unwrap_or(default).to_string()
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return Task::perform(system::spawn(snapshot), |s| Msg::Refreshed(s.unwrap_or_default())),
            Msg::Refreshed(s) => self.snapshot = Some(s),
            Msg::Place(file, item, place) => {
                let mut map = map_of(file);
                map.insert(item, Json::String(place.into()));
                self.error = store()
                    .write(file, &Value::Json(Json::Object(map)))
                    .err()
                    .map(|e| e.to_string());
                return self.update(Msg::Refresh);
            }
            Msg::Activity(on) => {
                self.error = store().write(ACTIVITY, &Value::Bool(on)).err().map(|e| e.to_string());
                return self.update(Msg::Refresh);
            }
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(s) = &self.snapshot else {
            return ui::section(body, "Bar", vec![ui::note("Loading…")]);
        };
        let width = Length::Fixed(220.0);

        let mut modules: Vec<Element<'a, Msg>> = MODULES
            .iter()
            .map(|m| {
                let current = place_of(&s.bar, m.id, m.default);
                let items = m
                    .places
                    .iter()
                    .map(|(v, l)| (*l, current == *v, Some(Msg::Place(BAR, m.id.to_string(), v))))
                    .collect();
                ui::item(
                    m.glyph,
                    m.label.to_string(),
                    String::new(),
                    vec![ui::choice(items, width)],
                )
            })
            .collect();
        let activity = vec![
            (ON_BAR.1, s.activity, Some(Msg::Activity(true))),
            (HIDDEN.1, !s.activity, Some(Msg::Activity(false))),
        ];
        modules.push(ui::item(
            ico::EYE,
            "Activity icons".into(),
            String::new(),
            vec![ui::choice(activity, width)],
        ));
        body = ui::section(body, "Bar", modules);

        let actions = ACTIONS
            .iter()
            .map(|(key, label, glyph, default)| {
                let current = place_of(&s.qa, key, default);
                let items = [IN_PANEL, ON_BAR, HIDDEN]
                    .iter()
                    .map(|(v, l)| (*l, current == *v, Some(Msg::Place(QA, key.to_string(), v))))
                    .collect();
                ui::item(glyph, label.to_string(), String::new(), vec![ui::choice(items, width)])
            })
            .collect();
        body = ui::section(body, "Quick Actions", actions);

        // Running tray apps, then ones placed before that are not running.
        let mut tray: Vec<(String, String)> = s.live_tray.clone();
        for key in s.tray.keys() {
            if !tray.iter().any(|(k, _)| k == key) {
                tray.push((key.clone(), "Not running".into()));
            }
        }
        let mut rows: Vec<Element<'a, Msg>> = tray
            .into_iter()
            .map(|(key, detail)| {
                let current = place_of(&s.tray, &key, "bar");
                let items = [ON_BAR, IN_PANEL, HIDDEN]
                    .iter()
                    .map(|(v, l)| (*l, current == *v, Some(Msg::Place(TRAY, key.clone(), v))))
                    .collect();
                ui::item(ico::APP_WINDOW, key.clone(), detail, vec![ui::choice(items, width)])
            })
            .collect();
        if rows.is_empty() {
            rows.push(ui::note("No tray apps running"));
        }
        ui::section(body, "Tray apps", rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_places_with_defaults() {
        let mut m = Map::new();
        m.insert("network".into(), Json::String("overflow".into()));
        assert_eq!(place_of(&m, "network", "bar"), "overflow");
        assert_eq!(place_of(&m, "battery", "bar"), "bar");
    }

    #[test]
    fn modules_offer_their_default_place() {
        for m in MODULES {
            assert!(m.places.iter().any(|(v, _)| *v == m.default), "{}", m.id);
        }
    }
}
