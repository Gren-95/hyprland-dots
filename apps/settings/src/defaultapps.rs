//! Default apps panel: which app fills a role. Browser, terminal, editor and
//! file manager go through scripts/default-app.sh (which the Hyprland binds
//! launch through, and which sets the XDG defaults where they exist); the
//! other roles are XDG mime defaults set with xdg-mime. The choices are the
//! installed apps whose desktop entry says they handle the role.

use std::collections::HashSet;
use std::path::PathBuf;

use iced::widget::Column;
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::system::{self, args};
use crate::ui;

/// How a role is stored.
#[derive(Debug, Clone, Copy, PartialEq)]
enum Store {
    /// default-app.sh get/set <role>.
    Script,
    /// xdg-mime default for these types (the first is read back).
    Mime(&'static [&'static str]),
}

struct Role {
    id: &'static str,
    label: &'static str,
    help: &'static str,
    icon: ui::Icon,
    store: Store,
    /// An app qualifies when its MimeType has one of these…
    mimes: &'static [&'static str],
    /// …or its Categories has one of these.
    categories: &'static [&'static str],
}

const ROLES: &[Role] = &[
    Role {
        id: "browser",
        label: "Web browser",
        help: "Opens links",
        icon: ico::GLOBE,
        store: Store::Script,
        mimes: &["x-scheme-handler/https", "text/html"],
        categories: &["WebBrowser"],
    },
    Role {
        id: "mail",
        label: "Mail",
        help: "Opens email links",
        icon: ico::MAIL,
        store: Store::Mime(&["x-scheme-handler/mailto"]),
        mimes: &["x-scheme-handler/mailto"],
        categories: &["Email"],
    },
    Role {
        id: "terminal",
        label: "Terminal",
        help: "Super+T and the terminal in the launcher",
        icon: ico::SQUARE_TERMINAL,
        store: Store::Script,
        mimes: &[],
        categories: &["TerminalEmulator"],
    },
    Role {
        id: "editor",
        label: "Text editor",
        help: "Opens text files",
        icon: ico::FILE_PEN,
        store: Store::Script,
        mimes: &["text/plain"],
        categories: &["TextEditor"],
    },
    Role {
        id: "filemanager",
        label: "Files",
        help: "Super+E and opening folders",
        icon: ico::FOLDER,
        store: Store::Script,
        mimes: &["inode/directory"],
        categories: &["FileManager"],
    },
    Role {
        id: "images",
        label: "Images",
        help: "Opens pictures",
        icon: ico::IMAGE,
        store: Store::Mime(&[
            "image/png",
            "image/jpeg",
            "image/gif",
            "image/webp",
            "image/bmp",
            "image/svg+xml",
        ]),
        mimes: &["image/png", "image/jpeg"],
        categories: &[],
    },
    Role {
        id: "video",
        label: "Video",
        help: "Plays videos",
        icon: ico::FILM,
        store: Store::Mime(&[
            "video/mp4",
            "video/x-matroska",
            "video/webm",
            "video/quicktime",
            "video/x-msvideo",
        ]),
        mimes: &["video/mp4", "video/x-matroska"],
        categories: &[],
    },
    Role {
        id: "music",
        label: "Music",
        help: "Plays audio files",
        icon: ico::AUDIO_LINES,
        store: Store::Mime(&[
            "audio/mpeg",
            "audio/flac",
            "audio/ogg",
            "audio/x-wav",
            "audio/mp4",
            "audio/aac",
        ]),
        mimes: &["audio/mpeg", "audio/flac"],
        categories: &[],
    },
    Role {
        id: "pdf",
        label: "PDF documents",
        help: "Opens PDF files",
        icon: ico::FILE_TEXT,
        store: Store::Mime(&["application/pdf"]),
        mimes: &["application/pdf"],
        categories: &[],
    },
];

/// An installed app: desktop id and name, with what it handles.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct App {
    pub id: String,
    pub name: String,
    /// NoDisplay: kept out of the choices, but named when it is the default.
    pub hidden: bool,
    pub mimes: Vec<String>,
    pub categories: Vec<String>,
    /// The .desktop file (set by `installed`).
    pub path: std::path::PathBuf,
}

/// The [Desktop Entry] of a .desktop file, or None for deleted entries
/// (Hidden=true) and non-applications.
pub fn parse_desktop(id: &str, text: &str) -> Option<App> {
    let mut app = App {
        id: id.to_string(),
        ..App::default()
    };
    let mut inside = false;
    let mut is_app = false;
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Desktop Entry]";
            continue;
        }
        let Some((key, value)) = line.split_once('=').filter(|_| inside) else {
            continue;
        };
        let list = || value.split(';').filter(|v| !v.is_empty()).map(String::from).collect();
        match key.trim() {
            "Name" => app.name = value.trim().to_string(),
            "MimeType" => app.mimes = list(),
            "Categories" => app.categories = list(),
            "Type" => is_app = value.trim() == "Application",
            "Hidden" if value.trim() == "true" => return None,
            "NoDisplay" => app.hidden = value.trim() == "true",
            _ => {}
        }
    }
    (is_app && !app.name.is_empty()).then_some(app)
}

/// Application directories, the user's first.
fn app_dirs() -> Vec<PathBuf> {
    let mut dirs = vec![crate::store::home().join(".local/share/applications")];
    let data = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    dirs.extend(
        data.split(':')
            .filter(|d| !d.is_empty())
            .map(|d| PathBuf::from(d).join("applications")),
    );
    dirs
}

/// Every installed app, once each (the first directory wins).
pub fn installed() -> Vec<App> {
    let mut seen = HashSet::new();
    let mut apps = Vec::new();
    for dir in app_dirs() {
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        let mut entries: Vec<_> = entries.flatten().collect();
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            let id = entry.file_name().to_string_lossy().into_owned();
            if !id.ends_with(".desktop") || !seen.insert(id.clone()) {
                continue;
            }
            if let Some(app) = std::fs::read_to_string(entry.path())
                .ok()
                .and_then(|t| parse_desktop(&id, &t))
            {
                apps.push(App {
                    path: entry.path(),
                    ..app
                });
            }
        }
    }
    apps
}

fn fits(app: &App, role: &Role) -> bool {
    role.mimes.iter().any(|m| app.mimes.iter().any(|a| a == m))
        || role.categories.iter().any(|c| app.categories.iter().any(|a| a == c))
}

fn script() -> String {
    crate::store::home()
        .join(".config/scripts/default-app.sh")
        .to_string_lossy()
        .into_owned()
}

fn current(role: &Role) -> String {
    let out = match role.store {
        Store::Script => system::run_blocking("bash", &[script(), "get".into(), role.id.into()], None),
        Store::Mime(types) => system::run_blocking("xdg-mime", &args(&["query", "default", types[0]]), None),
    };
    out.map(|s| s.trim().to_string()).unwrap_or_default()
}

/// One role: what it is now and the apps that can fill it.
#[derive(Debug, Clone, Default)]
pub struct Choice {
    pub current: String,
    pub apps: Vec<App>,
}

fn load() -> Vec<Choice> {
    let apps = installed();
    ROLES
        .iter()
        .map(|role| {
            let current = current(role);
            let mut fitting: Vec<App> = apps
                .iter()
                .filter(|a| fits(a, role) && (!a.hidden || a.id == current))
                .cloned()
                .collect();
            // The default by its name even when its entry does not list the
            // role (set by hand, or a NoDisplay entry).
            if !fitting.iter().any(|a| a.id == current)
                && let Some(app) = apps.iter().find(|a| a.id == current)
            {
                fitting.push(app.clone());
            }
            fitting.sort_by_key(|a| a.name.to_lowercase());
            Choice { current, apps: fitting }
        })
        .collect()
}

fn set(role: &'static Role, id: String) -> Result<(), String> {
    match role.store {
        Store::Script => system::run_blocking("bash", &[script(), "set".into(), role.id.into(), id], None).map(|_| ()),
        Store::Mime(types) => {
            let mut list = args(&["default"]);
            list.push(id);
            list.extend(types.iter().map(|t| t.to_string()));
            system::run_blocking("xdg-mime", &list, None).map(|_| ())
        }
    }
}

/// Every role's id and the app filling it now (for export).
pub fn current_roles() -> Vec<(&'static str, String)> {
    ROLES.iter().map(|r| (r.id, current(r))).collect()
}

/// A role's label, for listing what an import changes.
pub fn role_label(id: &str) -> Option<&'static str> {
    ROLES.iter().find(|r| r.id == id).map(|r| r.label)
}

/// Fill a role by its id (for import).
pub fn set_role(id: &str, app: String) -> Result<(), String> {
    let role = ROLES
        .iter()
        .find(|r| r.id == id)
        .ok_or_else(|| format!("unknown role {id}"))?;
    set(role, app)
}

#[derive(Default)]
pub struct State {
    choices: Option<Vec<Choice>>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Vec<Choice>),
    /// (index into ROLES, desktop id)
    Pick(usize, String),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |c| Msg::Loaded(c.unwrap_or_default())),
            Msg::Loaded(c) => self.choices = Some(c),
            Msg::Pick(i, id) => {
                self.busy = true;
                let role = &ROLES[i];
                return Task::perform(system::spawn(move || set(role, id)), |r| {
                    Msg::Done(r.unwrap_or_else(|| Err("saving stopped unexpectedly".into())))
                });
            }
            Msg::Done(r) => {
                self.busy = false;
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(choices) = &self.choices else {
            return ui::section(body, "Default apps", vec![ui::note("Loading…")]);
        };
        let rows = ROLES
            .iter()
            .zip(choices)
            .enumerate()
            .map(|(i, (role, choice))| {
                let mut items: Vec<(&'a str, bool, Option<Msg>)> = choice
                    .apps
                    .iter()
                    .map(|a| {
                        (
                            a.name.as_str(),
                            a.id == choice.current,
                            (!self.busy).then(|| Msg::Pick(i, a.id.clone())),
                        )
                    })
                    .collect();
                // A default that is not among the apps found (set elsewhere,
                // or its entry is gone) is still shown, by its id.
                if !choice.current.is_empty() && !choice.apps.iter().any(|a| a.id == choice.current) {
                    let again = (!self.busy).then(|| Msg::Pick(i, choice.current.clone()));
                    items.insert(0, (choice.current.as_str(), true, again));
                }
                let control: Element<'a, Msg> = if items.is_empty() {
                    ui::note("No app found")
                } else {
                    ui::select(items, Length::Fixed(260.0))
                };
                ui::item(role.icon, role.label.into(), role.help.into(), vec![control])
            })
            .collect();
        ui::section(body, "Default apps", rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_desktop_entries() {
        let text = "[Desktop Entry]\nType=Application\nName=Eye of GNOME\nMimeType=image/png;image/jpeg;\nCategories=Graphics;Viewer;\n[Desktop Action new]\nName=New window\n";
        let app = parse_desktop("org.gnome.eog.desktop", text).unwrap();
        assert_eq!(app.name, "Eye of GNOME");
        assert_eq!(app.mimes, ["image/png", "image/jpeg"]);
        assert!(fits(&app, &ROLES[5]));
        assert!(!fits(&app, &ROLES[0]));
        let hidden = parse_desktop(
            "x.desktop",
            "[Desktop Entry]\nType=Application\nName=X\nNoDisplay=true\n",
        );
        assert!(hidden.unwrap().hidden);
        let deleted = parse_desktop("x.desktop", "[Desktop Entry]\nType=Application\nName=X\nHidden=true\n");
        assert_eq!(deleted, None);
        assert_eq!(parse_desktop("x.desktop", "[Desktop Entry]\nType=Link\nName=X\n"), None);
    }

    #[test]
    fn terminals_are_found_by_category() {
        let kitty = parse_desktop(
            "kitty.desktop",
            "[Desktop Entry]\nType=Application\nName=kitty\nCategories=System;TerminalEmulator;\n",
        )
        .unwrap();
        assert!(fits(&kitty, ROLES.iter().find(|r| r.id == "terminal").unwrap()));
    }
}
