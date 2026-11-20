//! Appearance panel's own rows: the GTK theme (from the installed ones,
//! through gsettings) and the wallpaper, picked from a grid of the
//! wallpaper folder (thumbnails from scripts/wallpaper-thumbs.sh, applied
//! with scripts/wallpaper.sh). The grid starts closed, behind the current
//! wallpaper's row.

use std::path::{Path, PathBuf};

use iced::widget::{Space, button, container, image, row};
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::store::{Kind, Store, Value, home};
use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

const WALLPAPER_EXTENSIONS: &[&str] = &["jpg", "jpeg", "png", "webp", "gif"];
/// A grid card, a third of the thumbnail's 520 x 728.
const CARD: (f32, f32) = (104.0, 146.0);

/// GTK themes: Adwaita and HighContrast (built into GTK), and folders with
/// a gtk-3.0 part in the theme folders, by name.
pub fn gtk_themes(dirs: &[PathBuf]) -> Vec<String> {
    let mut names: Vec<String> = ["Adwaita", "HighContrast"].map(String::from).into();
    names.extend(
        dirs.iter()
            .filter_map(|d| std::fs::read_dir(d).ok())
            .flatten()
            .flatten()
            .filter(|e| e.path().join("gtk-3.0").is_dir())
            .map(|e| e.file_name().to_string_lossy().into_owned()),
    );
    names.sort_by_key(|n| n.to_lowercase());
    names.dedup();
    names
}

fn theme_dirs() -> Vec<PathBuf> {
    vec![
        home().join(".local/share/themes"),
        home().join(".themes"),
        PathBuf::from("/usr/share/themes"),
    ]
}

/// gsettings prints strings quoted: 'Adwaita'.
pub fn unquote(out: &str) -> String {
    out.trim().trim_matches('\'').to_string()
}

fn gsettings_get(key: &str) -> String {
    system::run_blocking("gsettings", &args(&["get", "org.gnome.desktop.interface", key]), None)
        .map(|o| unquote(&o))
        .unwrap_or_default()
}

/// The wallpaper folder setting, with ~ expanded.
fn wallpaper_dir() -> PathBuf {
    let stored = match Store::new(Store::default_dir()).read("wallpaper-dir", Kind::Text) {
        Some(Value::Text(t)) if !t.trim().is_empty() => t.trim().to_string(),
        _ => "~/Pictures/wallpapers".into(),
    };
    match stored.strip_prefix("~/") {
        Some(rest) => home().join(rest),
        None => PathBuf::from(stored),
    }
}

/// Wallpaper files under `dir` (like the deck's find), sorted.
fn wallpapers(dir: &Path) -> Vec<PathBuf> {
    let mut found = Vec::new();
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for e in std::fs::read_dir(&d).into_iter().flatten().flatten() {
            let p = e.path();
            if p.is_dir() {
                stack.push(p);
            } else if p
                .extension()
                .and_then(|x| x.to_str())
                .is_some_and(|x| WALLPAPER_EXTENSIONS.contains(&x.to_lowercase().as_str()))
            {
                found.push(p);
            }
        }
    }
    found.sort();
    found
}

/// `wallpaper-thumbs.sh`: "wallpaper<TAB>thumbnail" lines.
pub fn parse_thumbs(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter_map(|l| l.split_once('\t'))
        .map(|(w, t)| (w.to_string(), t.to_string()))
        .collect()
}

/// `awww query`: the image the first output shows.
pub fn parse_current(out: &str) -> String {
    out.lines()
        .find_map(|l| l.split_once("image: ").map(|(_, p)| p.trim().to_string()))
        .unwrap_or_default()
}

fn script(name: &str) -> String {
    home().join(".config/scripts").join(name).to_string_lossy().into_owned()
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub gtk_themes: Vec<String>,
    pub gtk_theme: String,
    pub current_wallpaper: String,
    /// awww could not be asked (not running): the wallpaper is unknown.
    pub wallpaper_unknown: bool,
}

fn read() -> Reading {
    Reading {
        gtk_themes: gtk_themes(&theme_dirs()),
        gtk_theme: gsettings_get("gtk-theme"),
        ..wallpaper()
    }
}

fn wallpaper() -> Reading {
    match system::run_blocking("awww", &args(&["query"]), None) {
        Ok(out) => Reading {
            current_wallpaper: canonical(&parse_current(&out)),
            ..Reading::default()
        },
        Err(_) => Reading {
            wallpaper_unknown: true,
            ..Reading::default()
        },
    }
}

/// A path with links resolved (~/Pictures may be a link elsewhere), so the
/// wallpaper in use matches its card.
fn canonical(path: &str) -> String {
    std::fs::canonicalize(path).map_or_else(|_| path.to_string(), |p| p.to_string_lossy().into_owned())
}

/// The grid: (wallpaper, thumbnail) pairs.
fn read_thumbs() -> Result<Vec<(String, String)>, String> {
    let mut list = vec![script("wallpaper-thumbs.sh")];
    list.extend(
        wallpapers(&wallpaper_dir())
            .into_iter()
            .map(|p| p.to_string_lossy().into_owned()),
    );
    let out = system::run_blocking("bash", &list, None).map_err(|e| format!("Could not make the previews: {e}"))?;
    Ok(parse_thumbs(&out)
        .into_iter()
        .map(|(w, t)| (canonical(&w), t))
        .collect())
}

#[derive(Default)]
pub struct State {
    reading: Option<Reading>,
    /// The wallpaper grid is open, and its cards once made.
    grid_open: bool,
    thumbs: Option<Result<Vec<(String, String)>, String>>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Reading),
    GtkTheme(String),
    ToggleGrid,
    Thumbs(Result<Vec<(String, String)>, String>),
    Wallpaper(String),
    OpenFolder,
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => {
                self.reading = Some(r);
                self.busy = false;
            }
            Msg::GtkTheme(name) => {
                self.busy = true;
                let list = args(&["set", "org.gnome.desktop.interface", "gtk-theme", &name]);
                return Task::perform(system::run("gsettings", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::ToggleGrid => {
                self.grid_open = !self.grid_open;
                if self.grid_open {
                    // Made again on every opening: the folder may have changed.
                    return Task::perform(system::spawn(read_thumbs), |t| {
                        Msg::Thumbs(t.unwrap_or_else(|| Err("Making the previews stopped unexpectedly".into())))
                    });
                }
            }
            Msg::Thumbs(t) => self.thumbs = Some(t),
            Msg::Wallpaper(path) => {
                self.busy = true;
                return Task::perform(system::run("bash", vec![script("wallpaper.sh"), path], None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::OpenFolder => {
                let dir = wallpaper_dir().to_string_lossy().into_owned();
                return Task::perform(system::run("xdg-open", vec![dir], None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::Done(r) => {
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    /// The GTK theme row, for the Style section.
    pub fn style_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(r) = &self.reading else {
            return vec![ui::note("Looking…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let choices = r
            .gtk_themes
            .iter()
            .map(|t| {
                (
                    t.as_str(),
                    *t == r.gtk_theme,
                    (!self.busy).then(|| Msg::GtkTheme(t.clone())),
                )
            })
            .collect();
        rows.push(ui::item(
            ico::APP_WINDOW,
            "GTK 3 theme".into(),
            "For older GTK apps".into(),
            vec![ui::select(choices, Length::Fixed(260.0))],
        ));
        rows
    }

    /// The current wallpaper with Choose, and the grid when open.
    pub fn wallpaper_rows(&self) -> Vec<Element<'_, Msg>> {
        let current = self
            .reading
            .as_ref()
            .map(|r| r.current_wallpaper.as_str())
            .unwrap_or_default();
        let unknown = self.reading.as_ref().is_some_and(|r| r.wallpaper_unknown);
        let name = match Path::new(current).file_name() {
            Some(n) => n.to_string_lossy().into_owned(),
            None if unknown => "Unknown: the wallpaper daemon (awww) is not running".to_string(),
            None => "None set".to_string(),
        };
        let mut rows = vec![ui::item(
            ico::IMAGE,
            "Wallpaper".into(),
            format!("{name} · Super+W deals the wallpaper deck"),
            vec![
                ui::icon_action(ico::FOLDER_OPEN, "Open folder", Some(Msg::OpenFolder), Action::Normal),
                ui::disclosure(self.grid_open, Msg::ToggleGrid),
            ],
        )];
        if !self.grid_open {
            return rows;
        }
        let thumbs = match &self.thumbs {
            None => {
                rows.push(ui::note("Making previews…"));
                return rows;
            }
            Some(Err(e)) => {
                rows.push(ui::error(e));
                return rows;
            }
            Some(Ok(t)) => t,
        };
        if thumbs.is_empty() {
            rows.push(ui::note("No pictures in the wallpaper folder"));
            return rows;
        }
        let cards = thumbs.iter().map(|(wallpaper, thumb)| {
            let picture = image(image::Handle::from_path(thumb))
                .width(CARD.0)
                .height(CARD.1)
                .content_fit(iced::ContentFit::Cover);
            let chosen = wallpaper == current;
            let card = button(picture)
                .padding(3)
                .on_press_maybe((!self.busy).then(|| Msg::Wallpaper(wallpaper.clone())))
                .style(move |t, s| style::wallpaper_card(t, s, chosen));
            crate::focus::focusable(card, (!self.busy).then(|| Msg::Wallpaper(wallpaper.clone()))).into()
        });
        let grid = row(cards).spacing(8).wrap();
        rows.push(container(grid).padding([6, 14]).into());
        rows.push(Space::new().height(4).into());
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_tools_output() {
        assert_eq!(unquote("'adw-gtk3-dark'\n"), "adw-gtk3-dark");
        assert_eq!(
            parse_thumbs("/w/a.jpg\t/c/1.jpg\nbad line\n/w/b.png\t/c/2.jpg\n"),
            [
                ("/w/a.jpg".to_string(), "/c/1.jpg".to_string()),
                ("/w/b.png".to_string(), "/c/2.jpg".to_string())
            ]
        );
        assert_eq!(
            parse_current(": eDP-1: 1920x1200, scale: 1, currently displaying: image: /w/rm-rf.jpg\n"),
            "/w/rm-rf.jpg"
        );
        assert_eq!(parse_current(""), "");
    }

    #[test]
    fn finds_gtk_themes() {
        let dir = std::env::temp_dir().join(format!("settings-gtk-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("adw-gtk3/gtk-3.0")).unwrap();
        std::fs::create_dir_all(dir.join("Emacs/gtk-2.0")).unwrap();
        assert_eq!(gtk_themes(&[dir.clone()]), ["adw-gtk3", "Adwaita", "HighContrast"]);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
