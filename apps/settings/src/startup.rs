//! Apps at login on the Services panel: the XDG autostart entries in
//! ~/.config/autostart, which scripts/autostart-apps.sh starts once per
//! login. Each can be switched off (X-GNOME-Autostart-enabled=false, the
//! entry stays) or removed; installed apps can be added (their .desktop file
//! is copied in).

use std::path::{Path, PathBuf};

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::defaultapps;
use crate::style::Action;
use crate::system;
use crate::ui;

const ENABLED_KEY: &str = "X-GNOME-Autostart-enabled";

#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub file: PathBuf,
    pub name: String,
    pub enabled: bool,
}

fn dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::store::home().join(".config"))
        .join("autostart")
}

/// A key of the [Desktop Entry] group.
fn entry_value(text: &str, key: &str) -> Option<String> {
    let mut inside = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Desktop Entry]";
        } else if inside && let Some(v) = line.strip_prefix(&format!("{key}=")) {
            return Some(v.trim().to_string());
        }
    }
    None
}

/// An autostart entry, or None for one marked deleted (Hidden=true).
pub fn parse_entry(file: &Path, text: &str) -> Option<Entry> {
    if entry_value(text, "Hidden").as_deref() == Some("true") {
        return None;
    }
    let fallback = file.file_stem().unwrap_or_default().to_string_lossy().into_owned();
    Some(Entry {
        file: file.to_path_buf(),
        name: entry_value(text, "Name").unwrap_or(fallback),
        enabled: entry_value(text, ENABLED_KEY).as_deref() != Some("false"),
    })
}

/// The entry with the enabled key set, added to the [Desktop Entry] group
/// when it is not there.
pub fn with_enabled(text: &str, on: bool) -> String {
    let value = format!("{ENABLED_KEY}={on}");
    let mut out = Vec::new();
    let (mut inside, mut done) = (false, false);
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('[') {
            if inside && !done {
                out.push(value.clone());
                done = true;
            }
            inside = trimmed == "[Desktop Entry]";
        } else if inside && trimmed.starts_with(&format!("{ENABLED_KEY}=")) {
            out.push(value.clone());
            done = true;
            continue;
        }
        out.push(line.to_string());
    }
    if inside && !done {
        out.push(value);
    }
    out.join("\n") + "\n"
}

fn load() -> Vec<Entry> {
    let mut list: Vec<Entry> = std::fs::read_dir(dir())
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "desktop"))
        .filter_map(|p| std::fs::read_to_string(&p).ok().and_then(|t| parse_entry(&p, &t)))
        .collect();
    list.sort_by_key(|e| e.name.to_lowercase());
    list
}

fn set_enabled(file: PathBuf, on: bool) -> Result<(), String> {
    let text = std::fs::read_to_string(&file).map_err(|e| e.to_string())?;
    std::fs::write(&file, with_enabled(&text, on)).map_err(|e| e.to_string())
}

fn add(source: PathBuf) -> Result<(), String> {
    let target = dir();
    std::fs::create_dir_all(&target).map_err(|e| e.to_string())?;
    let name = source.file_name().ok_or("no file name")?;
    std::fs::copy(&source, target.join(name))
        .map(|_| ())
        .map_err(|e| e.to_string())
}

#[derive(Default)]
pub struct State {
    entries: Option<Vec<Entry>>,
    /// Installed apps for Add, once asked for: (name, .desktop file).
    apps: Option<Vec<(String, PathBuf)>>,
    adding: bool,
    query: String,
    /// Entry whose Remove was clicked once.
    confirming: Option<PathBuf>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Vec<Entry>),
    Switch(PathBuf, bool),
    Remove(PathBuf),
    StartAdd,
    Apps(Vec<(String, PathBuf)>),
    Query(String),
    Add(PathBuf),
    CancelAdd,
    Done(Result<(), String>),
}

fn work(f: impl FnOnce() -> Result<(), String> + Send + 'static) -> Task<Msg> {
    Task::perform(system::spawn(f), |r| {
        Msg::Done(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
    })
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(msg, Msg::Remove(_) | Msg::Load | Msg::Loaded(_)) {
            self.confirming = None;
        }
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |l| Msg::Loaded(l.unwrap_or_default())),
            Msg::Loaded(l) => self.entries = Some(l),
            Msg::Switch(file, on) => return work(move || set_enabled(file, on)),
            Msg::Remove(file) => {
                if self.confirming.as_ref() != Some(&file) {
                    self.confirming = Some(file);
                } else {
                    self.confirming = None;
                    return work(move || std::fs::remove_file(&file).map_err(|e| e.to_string()));
                }
            }
            Msg::StartAdd => {
                self.adding = true;
                self.query.clear();
                if self.apps.is_none() {
                    return Task::perform(
                        system::spawn(|| {
                            let mut apps: Vec<(String, PathBuf)> = defaultapps::installed()
                                .into_iter()
                                .filter(|a| !a.hidden)
                                .map(|a| (a.name, a.path))
                                .collect();
                            apps.sort_by_key(|(n, _)| n.to_lowercase());
                            apps
                        }),
                        |a| Msg::Apps(a.unwrap_or_default()),
                    );
                }
            }
            Msg::Apps(a) => self.apps = Some(a),
            Msg::Query(q) => self.query = q,
            Msg::Add(path) => {
                self.adding = false;
                return work(move || add(path));
            }
            Msg::CancelAdd => self.adding = false,
            Msg::Done(r) => {
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let Some(entries) = &self.entries else {
            return vec![ui::note("Looking…")];
        };
        for e in entries {
            let file = e.file.clone();
            rows.push(ui::item(
                ico::ROCKET,
                e.name.clone(),
                if e.enabled {
                    "Starts at login".into()
                } else {
                    "Off".into()
                },
                vec![
                    ui::confirm_action(
                        ico::TRASH,
                        "Remove from login",
                        self.confirming.as_ref() == Some(&e.file),
                        Some(Msg::Remove(e.file.clone())),
                    ),
                    ui::switch(e.enabled, Some(move |on| Msg::Switch(file.clone(), on))),
                ],
            ));
        }
        rows.push(ui::item(
            ico::PLUS,
            "Add an app".into(),
            "Start an installed app when you log in".into(),
            vec![if self.adding {
                ui::action("Cancel", Some(Msg::CancelAdd), Action::Normal)
            } else {
                ui::icon_action(ico::PLUS, "Add", Some(Msg::StartAdd), Action::Normal)
            }],
        ));
        if self.adding {
            let matches = match &self.apps {
                None => Vec::new(),
                Some(apps) => apps
                    .iter()
                    .filter(|(n, _)| ui::matches_query(n, &self.query))
                    .take(8)
                    .map(|(n, p)| ui::PickerMatch {
                        label: n.clone(),
                        font: None,
                        detail: String::new(),
                        on_pick: Msg::Add(p.clone()),
                    })
                    .collect(),
            };
            let picker = ui::search_picker("Search installed apps", &self.query, Msg::Query, matches);
            rows.push(iced::widget::container(picker).padding([4, 14]).into());
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_entries() {
        let p = Path::new("/x/remmina-applet.desktop");
        let e = parse_entry(p, "[Desktop Entry]\nName=Remmina Applet\nHidden=false\n").unwrap();
        assert_eq!((e.name.as_str(), e.enabled), ("Remmina Applet", true));
        let off = parse_entry(p, "[Desktop Entry]\nName=R\nX-GNOME-Autostart-enabled=false\n").unwrap();
        assert!(!off.enabled);
        assert_eq!(parse_entry(p, "[Desktop Entry]\nName=R\nHidden=true\n"), None);
        assert_eq!(
            parse_entry(p, "[Desktop Entry]\nType=Application\n").unwrap().name,
            "remmina-applet"
        );
    }

    #[test]
    fn switches_entries_in_place() {
        let text = "[Desktop Entry]\nName=A\n\n[Desktop Action new]\nName=New\n";
        let off = with_enabled(text, false);
        assert_eq!(
            off,
            "[Desktop Entry]\nName=A\n\nX-GNOME-Autostart-enabled=false\n[Desktop Action new]\nName=New\n"
        );
        let on = with_enabled(&off, true);
        assert!(on.contains("X-GNOME-Autostart-enabled=true") && !on.contains("=false"));
        assert_eq!(
            with_enabled("[Desktop Entry]\nName=A\n", false),
            "[Desktop Entry]\nName=A\nX-GNOME-Autostart-enabled=false\n"
        );
    }
}
