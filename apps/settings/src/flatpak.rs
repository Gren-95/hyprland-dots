//! App permissions panel: what each installed Flatpak app may reach outside
//! its sandbox. The switches show the permissions in effect (`flatpak info
//! --show-permissions`: the app's own merged with overrides) and change them
//! with user overrides (`flatpak override --user`), which apply to apps from
//! either installation. Reset removes the user overrides of one app. An app
//! reads its permissions when it starts, so a change counts from its next
//! start.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// A permission with a switch: (kind, value, label, help). The kind is the
/// [Context] key; its override flags are in `flags`.
pub const SWITCHES: &[(&str, &str, &str, &str)] = &[
    ("shared", "network", "Network", "Internet and local network"),
    ("sockets", "pulseaudio", "Sound", "Speakers and microphone"),
    ("devices", "dri", "Graphics acceleration", "Draw with the GPU"),
    ("devices", "all", "All devices", "Webcam, controllers, USB, all of /dev"),
    ("sockets", "cups", "Printing", "Without the print dialog"),
    ("sockets", "ssh-auth", "SSH agent", "Use your SSH keys"),
    (
        "sockets",
        "session-bus",
        "Every app and service",
        "Whole session bus; can leave the sandbox",
    ),
];

/// (switch on, switch off) flags of a [Context] key.
fn flags(kind: &str) -> (&'static str, &'static str) {
    match kind {
        "shared" => ("--share", "--unshare"),
        "sockets" => ("--socket", "--nosocket"),
        _ => ("--device", "--nodevice"),
    }
}

/// The [Context] group of a keyfile: (key, values) with the `;` lists split.
pub fn parse_context(keyfile: &str) -> Vec<(String, Vec<String>)> {
    let mut in_context = false;
    let mut out = Vec::new();
    for line in keyfile.lines().map(str::trim) {
        if line.starts_with('[') {
            in_context = line == "[Context]";
            continue;
        }
        let Some((key, values)) = line.split_once('=').filter(|_| in_context) else {
            continue;
        };
        let values = values.split(';').filter(|v| !v.is_empty()).map(String::from).collect();
        out.push((key.to_string(), values));
    }
    out
}

fn values<'a>(context: &'a [(String, Vec<String>)], key: &str) -> &'a [String] {
    context
        .iter()
        .find(|(k, _)| k == key)
        .map_or(&[], |(_, v)| v.as_slice())
}

/// `flatpak list --app --columns=application,name`: (id, name), each app
/// once (it may be in both installations).
pub fn parse_apps(out: &str) -> Vec<(String, String)> {
    let mut apps: Vec<(String, String)> = out
        .lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(id, name)| (id.trim().to_string(), name.trim().to_string()))
        .filter(|(id, _)| !id.is_empty())
        .collect();
    apps.sort_by_key(|(_, name)| name.to_lowercase());
    apps.dedup_by(|a, b| a.0 == b.0);
    apps
}

/// A filesystem entry as people read it: "home:ro" is "Home folder, read
/// only".
pub fn folder_label(entry: &str) -> String {
    let (path, mode) = match entry.rsplit_once(':') {
        Some((p, m @ ("ro" | "rw" | "create"))) => (p, m),
        _ => (entry, "rw"),
    };
    let named = match path {
        "host" => "All files".to_string(),
        "host-os" => "System files".to_string(),
        "host-etc" => "System settings (/etc)".to_string(),
        "home" => "Home folder".to_string(),
        "xdg-download" => "Downloads".to_string(),
        "xdg-documents" => "Documents".to_string(),
        "xdg-music" => "Music".to_string(),
        "xdg-pictures" => "Pictures".to_string(),
        "xdg-videos" => "Videos".to_string(),
        "xdg-desktop" => "Desktop".to_string(),
        p => match p.split_once('/') {
            Some(("xdg-config", rest)) => format!("~/.config/{rest}"),
            Some(("xdg-data", rest)) => format!("~/.local/share/{rest}"),
            Some(("xdg-cache", rest)) => format!("~/.cache/{rest}"),
            Some(("xdg-run", rest)) => format!("Runtime folder: {rest}"),
            _ => p.to_string(),
        },
    };
    match mode {
        "ro" => format!("{named}, read only"),
        "create" => format!("{named}, made when missing"),
        _ => named,
    }
}

/// An entry without its mode: what --nofilesystem takes.
fn folder_path(entry: &str) -> &str {
    match entry.rsplit_once(':') {
        Some((p, "ro" | "rw" | "create")) => p,
        _ => entry,
    }
}

#[derive(Debug, Clone, Default)]
pub struct App {
    pub id: String,
    pub name: String,
    /// In effect.
    pub context: Vec<(String, Vec<String>)>,
    /// The user's overrides of this app.
    pub overridden: bool,
    /// Why its permissions could not be read.
    pub error: Option<String>,
}

impl App {
    fn has(&self, kind: &str, value: &str) -> bool {
        values(&self.context, kind).iter().any(|v| v == value)
    }

    fn folders(&self) -> &[String] {
        values(&self.context, "filesystems")
    }

    /// The reach in one line: what stands out most first.
    fn summary(&self) -> String {
        let mut parts: Vec<String> = Vec::new();
        for f in self.folders() {
            match folder_path(f) {
                "host" | "host-os" | "home" => parts.push(folder_label(f)),
                _ => {}
            }
        }
        for (kind, value, label, _) in SWITCHES {
            if self.has(kind, value) {
                parts.push((*label).to_string());
            }
        }
        if parts.is_empty() {
            "Nothing outside its sandbox".into()
        } else {
            parts.join(" · ")
        }
    }
}

/// The apps with their permissions. Err when flatpak itself cannot list
/// them (not installed); an app whose permissions cannot be read carries
/// the error instead.
fn read() -> Result<Vec<App>, String> {
    let list = system::run_blocking("flatpak", &args(&["list", "--app", "--columns=application,name"]), None).map_err(
        |e| {
            if e.starts_with("could not run") {
                "Flatpak is not installed".to_string()
            } else {
                format!("Could not list the Flatpak apps: {e}")
            }
        },
    )?;
    Ok(parse_apps(&list)
        .into_iter()
        .map(|(id, name)| {
            let info = system::run_blocking("flatpak", &args(&["info", "--show-permissions", &id]), None);
            let own = system::run_blocking("flatpak", &args(&["override", "--user", "--show", &id]), None)
                .unwrap_or_default();
            App {
                context: info.as_deref().map(parse_context).unwrap_or_default(),
                error: info.err().map(|e| format!("Could not read its permissions: {e}")),
                overridden: !own.trim().is_empty(),
                id,
                name,
            }
        })
        .collect())
}

#[derive(Default)]
pub struct State {
    apps: Option<Result<Vec<App>, String>>,
    open: Option<String>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Result<Vec<App>, String>),
    Toggle(String),
    Set(String, &'static str, &'static str, bool),
    RemoveFolder(String, String),
    AddFolder(String),
    Picked(String, Result<Option<String>, String>),
    Reset(String),
    Done(Result<(), String>),
}

fn override_task(list: Vec<String>) -> Task<Msg> {
    let mut all = args(&["override", "--user"]);
    all.extend(list);
    Task::perform(system::run("flatpak", all, None), |r| Msg::Done(r.map(|_| ())))
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::perform(system::spawn(read), |a| {
                    Msg::Loaded(a.unwrap_or_else(|| Err("Reading the apps stopped unexpectedly".into())))
                });
            }
            Msg::Loaded(apps) => {
                self.apps = Some(apps);
                self.busy = false;
            }
            Msg::Toggle(id) => {
                self.open = if self.open.as_ref() == Some(&id) {
                    None
                } else {
                    Some(id)
                };
            }
            Msg::Set(id, kind, value, on) => {
                self.busy = true;
                let (yes, no) = flags(kind);
                let flag = if on { yes } else { no };
                return override_task(vec![format!("{flag}={value}"), id]);
            }
            Msg::RemoveFolder(id, entry) => {
                self.busy = true;
                return override_task(vec![format!("--nofilesystem={}", folder_path(&entry)), id]);
            }
            Msg::AddFolder(id) => {
                let list = args(&["--file-selection", "--directory", "--title=Folder the app may use"]);
                return Task::perform(system::pick(list), move |r| Msg::Picked(id.clone(), r));
            }
            Msg::Picked(_, Ok(None)) => {}
            Msg::Picked(_, Err(e)) => self.error = Some(e),
            Msg::Picked(id, Ok(Some(path))) => {
                self.busy = true;
                return override_task(vec![format!("--filesystem={path}"), id]);
            }
            Msg::Reset(id) => {
                self.busy = true;
                return override_task(vec!["--reset".into(), id]);
            }
            Msg::Done(r) => {
                self.error = r.err().map(|e| format!("Not changed: {e}"));
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let apps = match &self.apps {
            None => return vec![ui::note("Looking…")],
            Some(Err(e)) => return vec![ui::note(e.clone())],
            Some(Ok(apps)) => apps,
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if apps.is_empty() {
            rows.push(ui::note("No Flatpak apps installed"));
        }
        for app in apps {
            let open = self.open.as_ref() == Some(&app.id);
            rows.push(ui::item(
                ico::BOX,
                app.name.clone(),
                app.error.clone().unwrap_or_else(|| app.summary()),
                // Switches showing unread permissions as off would mislead.
                if app.error.is_some() {
                    vec![]
                } else {
                    vec![ui::disclosure(open, Msg::Toggle(app.id.clone()))]
                },
            ));
            if open && app.error.is_none() {
                let details = self.details(app);
                let count = details.len();
                rows.extend(
                    details
                        .into_iter()
                        .enumerate()
                        .map(|(i, d)| ui::branch(d, i + 1 == count)),
                );
            }
        }
        rows
    }

    fn details<'a>(&'a self, app: &'a App) -> Vec<Element<'a, Msg>> {
        let idle = !self.busy;
        let mut rows: Vec<Element<'a, Msg>> = SWITCHES
            .iter()
            .map(|&(kind, value, label, help)| {
                let id = app.id.clone();
                ui::item(
                    ico::LOCK_OPEN,
                    label.into(),
                    help.into(),
                    vec![ui::switch(
                        app.has(kind, value),
                        idle.then_some(move |on| Msg::Set(id.clone(), kind, value, on)),
                    )],
                )
            })
            .collect();
        for entry in app.folders() {
            rows.push(ui::item(
                ico::FOLDER_OPEN,
                folder_label(entry),
                entry.clone(),
                vec![ui::icon_action(
                    ico::TRASH,
                    "Take away access",
                    idle.then(|| Msg::RemoveFolder(app.id.clone(), entry.clone())),
                    Action::Danger,
                )],
            ));
        }
        let mut controls = vec![ui::icon_action(
            ico::FOLDER_PLUS,
            "Add a folder",
            idle.then(|| Msg::AddFolder(app.id.clone())),
            Action::Normal,
        )];
        if app.overridden {
            controls.push(ui::icon_action(
                ico::ROTATE_CCW,
                "Reset to default",
                idle.then(|| Msg::Reset(app.id.clone())),
                Action::Normal,
            ));
        }
        rows.push(ui::item(
            ico::FOLDER_PLUS,
            "Files and folders".into(),
            if app.overridden {
                "From the app's next start".into()
            } else {
                "From the app's next start".into()
            },
            controls,
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_permissions() {
        let info = "[Context]\nshared=ipc;network;\nsockets=wayland;\nfilesystems=home:ro;xdg-config/gtk-4.0;\n\n[Session Bus Policy]\nshared=x\n";
        let ctx = parse_context(info);
        assert_eq!(values(&ctx, "shared"), ["ipc", "network"]);
        assert_eq!(values(&ctx, "filesystems"), ["home:ro", "xdg-config/gtk-4.0"]);
        assert!(values(&ctx, "devices").is_empty());
        let app = App {
            context: ctx,
            ..App::default()
        };
        assert!(app.has("shared", "network"));
        assert_eq!(app.summary(), "Home folder, read only · Network");
    }

    #[test]
    fn names_folders() {
        assert_eq!(folder_label("host"), "All files");
        assert_eq!(folder_label("xdg-download:ro"), "Downloads, read only");
        assert_eq!(folder_label("xdg-config/gtk-4.0"), "~/.config/gtk-4.0");
        assert_eq!(folder_label("/run/spnav.sock:ro"), "/run/spnav.sock, read only");
        assert_eq!(folder_path("home:ro"), "home");
        assert_eq!(folder_path("/mnt/a:b"), "/mnt/a:b");
    }

    #[test]
    fn lists_each_app_once() {
        let out = "org.b.B\tBeta\norg.a.A\talpha\norg.b.B\tBeta\n";
        assert_eq!(
            parse_apps(out),
            [
                ("org.a.A".to_string(), "alpha".to_string()),
                ("org.b.B".to_string(), "Beta".to_string())
            ]
        );
    }
}
