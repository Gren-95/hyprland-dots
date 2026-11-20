//! Export and import every setting as one JSON file: the shell's settings
//! store (one entry per file, as its text), the Hyprland choices
//! (~/.config/hypr/settings.json) and the default apps. An import first
//! lists what it would change; nothing is written until that is accepted.
//! Used by `settings export/import` and the Backup section on About.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use iced::{Element, Task};
use lucide_iced::bytes as ico;
use serde_json::{Map, Value as Json, json};

use crate::store::{Store, Value};
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

const FORMAT: u64 = 1;

/// Store files that record what happened on this machine rather than a
/// choice (the last connected Bluetooth device): not exported.
const MACHINE_STATE: &[&str] = &["bt-last-connected.json"];

/// What an export file holds.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Backup {
    pub store: BTreeMap<String, String>,
    pub hyprland: Json,
    pub default_apps: BTreeMap<String, String>,
}

/// One difference an import would make.
#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    pub what: String,
    pub from: String,
    pub to: String,
}

/// The store's files and their text, without temporary and machine-state
/// files.
fn read_store(dir: &Path) -> BTreeMap<String, String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return BTreeMap::new();
    };
    entries
        .flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_file()))
        .filter_map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') || MACHINE_STATE.contains(&name.as_str()) {
                return None;
            }
            Some((name.clone(), fs::read_to_string(e.path()).ok()?))
        })
        .collect()
}

/// Everything as it is now.
pub fn current(store_dir: &Path) -> Backup {
    Backup {
        store: read_store(store_dir),
        hyprland: crate::hypr::saved_json(),
        default_apps: crate::defaultapps::current_roles()
            .into_iter()
            .filter(|(_, app)| !app.is_empty())
            .map(|(role, app)| (role.to_string(), app))
            .collect(),
    }
}

pub fn to_json(b: &Backup) -> Json {
    json!({
        "settings-export": FORMAT,
        "store": b.store,
        "hyprland": b.hyprland,
        "default-apps": b.default_apps,
    })
}

fn string_map(v: &Json) -> BTreeMap<String, String> {
    v.as_object()
        .into_iter()
        .flatten()
        .filter_map(|(k, v)| Some((k.clone(), v.as_str()?.to_string())))
        .collect()
}

/// A store file name that cannot leave the store folder.
fn safe_name(name: &str) -> bool {
    !name.is_empty() && !name.starts_with('.') && !name.contains('/') && !name.contains('\\')
}

pub fn from_json(text: &str) -> Result<Backup, String> {
    let v: Json = serde_json::from_str(text).map_err(|e| format!("not a settings export: {e}"))?;
    match v["settings-export"].as_u64() {
        Some(FORMAT) => {}
        Some(n) => return Err(format!("made by a newer settings app (format {n})")),
        None => return Err("not a settings export".into()),
    }
    let store = string_map(&v["store"]);
    if let Some(bad) = store.keys().find(|k| !safe_name(k)) {
        return Err(format!("not a settings file name: {bad}"));
    }
    Ok(Backup {
        store,
        hyprland: v["hyprland"].clone(),
        default_apps: string_map(&v["default-apps"]),
    })
}

/// A value shortened to one line for the change list.
fn brief(text: &str) -> String {
    let line = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.chars().count() > 40 {
        format!("{}…", line.chars().take(39).collect::<String>())
    } else if line.is_empty() {
        "(empty)".into()
    } else {
        line
    }
}

fn show(v: Option<&Json>) -> String {
    match v {
        None | Some(Json::Null) => "(unset)".into(),
        Some(Json::String(s)) => brief(s),
        Some(other) => brief(&other.to_string()),
    }
}

/// Differences between two JSON objects, key by key, named `prefix key`.
fn object_changes(prefix: &str, now: &Json, new: &Json, out: &mut Vec<Change>) {
    let empty = Map::new();
    let (a, b) = (now.as_object().unwrap_or(&empty), new.as_object().unwrap_or(&empty));
    for key in b.keys() {
        if a.get(key) != b.get(key) {
            out.push(Change {
                what: format!("{prefix} {key}"),
                from: show(a.get(key)),
                to: show(b.get(key)),
            });
        }
    }
}

/// What importing `new` over `now` changes. Store files and default apps
/// only missing from the export stay as they are.
pub fn changes(now: &Backup, new: &Backup) -> Vec<Change> {
    let mut out = Vec::new();
    for (file, text) in &new.store {
        if now.store.get(file).map(|t| t.trim()) != Some(text.trim()) {
            out.push(Change {
                what: file.clone(),
                from: now.store.get(file).map_or("(unset)".into(), |t| brief(t)),
                to: brief(text),
            });
        }
    }
    if !new.hyprland.is_null() && now.hyprland != new.hyprland {
        if now.hyprland["keyboard"] != new.hyprland["keyboard"] {
            out.push(Change {
                what: "Hyprland keyboard".into(),
                from: show(now.hyprland.get("keyboard")),
                to: show(new.hyprland.get("keyboard")),
            });
        }
        object_changes("Hyprland", &now.hyprland["options"], &new.hyprland["options"], &mut out);
        object_changes("Shortcut", &now.hyprland["binds"], &new.hyprland["binds"], &mut out);
        if now.hyprland["rules"] != new.hyprland["rules"] {
            let classes = |v: &Json| {
                v.as_array()
                    .into_iter()
                    .flatten()
                    .filter_map(|r| r["class"].as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            };
            out.push(Change {
                what: "Window rules".into(),
                from: brief(&classes(&now.hyprland["rules"])),
                to: brief(&classes(&new.hyprland["rules"])),
            });
        }
    }
    for (role, app) in &new.default_apps {
        if now.default_apps.get(role) != Some(app) {
            let label = crate::defaultapps::role_label(role).unwrap_or(role);
            out.push(Change {
                what: format!("Default {}", label.to_lowercase()),
                from: now.default_apps.get(role).map_or("(unset)".into(), |a| a.clone()),
                to: app.clone(),
            });
        }
    }
    out
}

pub fn export_to(path: &Path, store_dir: &Path) -> Result<(), String> {
    let text = serde_json::to_string_pretty(&to_json(&current(store_dir))).unwrap_or_default();
    fs::write(path, text + "\n").map_err(|e| format!("could not write {}: {e}", path.display()))
}

pub fn read_file(path: &Path) -> Result<Backup, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("could not read {}: {e}", path.display()))?;
    from_json(&text)
}

/// Write what differs. The shell picks up store files as they change; the
/// settings that also change Hyprland or GTK run their after-write work.
pub fn apply(new: &Backup, store_dir: &Path) -> Result<(), String> {
    let store = Store::new(store_dir.to_path_buf());
    let now = current(store_dir);
    let mut work = Vec::new();
    for (file, text) in &new.store {
        if now.store.get(file).map(|t| t.trim()) == Some(text.trim()) {
            continue;
        }
        store
            .write(file, &Value::Text(text.clone()))
            .map_err(|e| format!("could not save {file}: {e}"))?;
        work.extend(crate::system::after_write(file));
    }
    for w in work {
        let _ = w.join();
    }
    // After the store: the store's after-write work also writes Hyprland
    // options, which the export's own values then replace.
    if !new.hyprland.is_null() && crate::hypr::saved_json() != new.hyprland {
        crate::hypr::replace_saved(&new.hyprland)?;
    }
    for (role, app) in &new.default_apps {
        if now.default_apps.get(role) != Some(app) {
            crate::defaultapps::set_role(role, app.clone())?;
        }
    }
    Ok(())
}

/// The Backup section on About: Export… and Import…, and after picking a
/// file to import, the changes it makes with Apply and Cancel.
#[derive(Default)]
pub struct State {
    /// An import waiting for Apply: the file's settings and what they change.
    pending: Option<(Backup, Vec<Change>)>,
    busy: bool,
    note: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Export,
    ExportTo(Option<String>),
    Import,
    ImportFrom(Option<String>),
    Read(Result<(Backup, Vec<Change>), String>),
    Apply,
    Cancel,
    /// The import was written; the app reads its values again.
    Applied(Result<(), String>),
    Done(Result<String, String>),
}

/// "Apply this change?" or "Apply these 3 changes?".
pub fn plural_question(count: usize) -> String {
    if count == 1 {
        "Apply this change?".into()
    } else {
        format!("Apply these {count} changes?")
    }
}

/// How many changes show before "and N more".
const SHOWN_CHANGES: usize = 12;

fn pick(save: bool) -> Task<Option<String>> {
    let mut list = args(&["--file-selection", "--file-filter=*.json"]);
    if save {
        list.extend(args(&["--save", "--confirm-overwrite", "--filename=dots-settings.json"]));
    }
    // zenity exits 1 when cancelled.
    Task::perform(system::run("zenity", list, None), |r| {
        r.ok().map(|p| p.trim().to_string()).filter(|p| !p.is_empty())
    })
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Export => return pick(true).map(Msg::ExportTo),
            Msg::Import => return pick(false).map(Msg::ImportFrom),
            Msg::ExportTo(None) | Msg::ImportFrom(None) => {}
            Msg::ExportTo(Some(path)) => {
                self.busy = true;
                let work = move || export_to(Path::new(&path), &Store::default_dir()).map(|_| format!("Saved to {path}"));
                return Task::perform(system::spawn(work), |r| {
                    Msg::Done(r.unwrap_or_else(|| Err("exporting stopped unexpectedly".into())))
                });
            }
            Msg::ImportFrom(Some(path)) => {
                self.busy = true;
                let work = move || {
                    let new = read_file(Path::new(&path))?;
                    let list = changes(&current(&Store::default_dir()), &new);
                    Ok((new, list))
                };
                return Task::perform(system::spawn(work), |r| {
                    Msg::Read(r.unwrap_or_else(|| Err("reading stopped unexpectedly".into())))
                });
            }
            Msg::Read(Ok((_, list))) if list.is_empty() => {
                self.busy = false;
                self.note = Some("Nothing to change: the settings already match".into());
            }
            Msg::Read(r) => {
                self.busy = false;
                self.note = None;
                match r {
                    Ok(p) => self.pending = Some(p),
                    Err(e) => self.error = Some(e),
                }
            }
            Msg::Apply => {
                let Some((new, _)) = self.pending.take() else {
                    return Task::none();
                };
                self.busy = true;
                return Task::perform(
                    system::spawn(move || apply(&new, &Store::default_dir())),
                    |r| Msg::Applied(r.unwrap_or_else(|| Err("importing stopped unexpectedly".into()))),
                );
            }
            Msg::Cancel => self.pending = None,
            Msg::Applied(r) => return self.update(Msg::Done(r.map(|_| "Imported".to_string()))),
            Msg::Done(r) => {
                self.busy = false;
                match r {
                    Ok(note) => {
                        self.note = Some(note);
                        self.error = None;
                    }
                    Err(e) => self.error = Some(e),
                }
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if let Some(n) = &self.note {
            rows.push(ui::note(n.clone()));
        }
        let idle = !self.busy && self.pending.is_none();
        rows.push(ui::item(
            ico::DOWNLOAD,
            "Export settings".into(),
            "The shell, Hyprland choices and default apps, in one file".into(),
            vec![ui::action("Export…", idle.then_some(Msg::Export), Action::Normal)],
        ));
        rows.push(ui::item(
            ico::UPLOAD,
            "Import settings".into(),
            "Shows what changes before anything is written".into(),
            vec![ui::action("Import…", idle.then_some(Msg::Import), Action::Normal)],
        ));
        let Some((_, list)) = &self.pending else { return rows };
        let mut lines: Vec<Element<'_, Msg>> = list
            .iter()
            .take(SHOWN_CHANGES)
            .map(|c| ui::item(ico::DOT, c.what.clone(), format!("{} → {}", c.from, c.to), vec![]))
            .collect();
        if list.len() > SHOWN_CHANGES {
            lines.push(ui::note(format!("and {} more", list.len() - SHOWN_CHANGES)));
        }
        lines.push(ui::item(
            ico::CIRCLE_QUESTION_MARK,
            plural_question(list.len()),
            String::new(),
            vec![
                ui::action("Cancel", (!self.busy).then_some(Msg::Cancel), Action::Normal),
                ui::action("Apply", (!self.busy).then_some(Msg::Apply), Action::Primary),
            ],
        ));
        let count = lines.len();
        rows.extend(lines.into_iter().enumerate().map(|(i, l)| ui::branch(l, i + 1 == count)));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Backup {
        Backup {
            store: BTreeMap::from([
                ("bar-height".to_string(), "36".to_string()),
                ("clock-24h".to_string(), "1".to_string()),
            ]),
            hyprland: json!({"options": {"general:gaps_in": 5}, "binds": {}, "keyboard": {"switch": ""}}),
            default_apps: BTreeMap::from([("browser".to_string(), "firefox.desktop".to_string())]),
        }
    }

    #[test]
    fn round_trips_through_json() {
        let b = sample();
        let text = to_json(&b).to_string();
        assert_eq!(from_json(&text).unwrap(), b);
        assert!(from_json("{}").is_err());
        assert!(from_json(r#"{"settings-export": 9}"#).is_err());
        assert!(from_json(r#"{"settings-export": 1, "store": {"../x": "1"}}"#).is_err());
    }

    #[test]
    fn lists_only_what_changes() {
        let now = sample();
        let mut new = sample();
        assert!(changes(&now, &new).is_empty());
        new.store.insert("bar-height".into(), "40\n".into());
        new.hyprland["options"]["general:gaps_in"] = json!(8);
        new.default_apps.insert("browser".into(), "chromium.desktop".into());
        let what: Vec<String> = changes(&now, &new).into_iter().map(|c| c.what).collect();
        assert_eq!(what, ["bar-height", "Hyprland general:gaps_in", "Default web browser"]);
        let c = &changes(&now, &new)[0];
        assert_eq!((c.from.as_str(), c.to.as_str()), ("36", "40"));
    }

    #[test]
    fn exports_the_store_without_machine_state() {
        let dir = std::env::temp_dir().join(format!("settings-backup-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("bar-height"), "36").unwrap();
        fs::write(dir.join("bt-last-connected.json"), "{}").unwrap();
        fs::write(dir.join(".bar-height.tmp"), "1").unwrap();
        let store = read_store(&dir);
        assert_eq!(store.keys().collect::<Vec<_>>(), ["bar-height"]);
        let _ = fs::remove_dir_all(&dir);
    }
}
