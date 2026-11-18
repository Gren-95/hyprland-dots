//! Icons & cursors panel: icon and cursor themes with previews, applied
//! through scripts/icon-theme.sh and scripts/cursor-theme.sh (`list`, `get`,
//! `set <id>`). Recently applied themes come first (iconThemeRecents,
//! cursorThemeRecents in the settings store), then the rest by name.

use iced::widget::{Column, Row, column, container, image, row, svg, text};
use iced::{Alignment, Element, Length, Task};
use serde_json::Value as Json;

use crate::store::{Kind, Store, Value};
use crate::style::{self, Action};
use crate::system;
use crate::ui;

const ICON_RECENTS: &str = "icon-theme-recents.json";
const CURSOR_RECENTS: &str = "cursor-theme-recents.json";
/// Size of a preview.
const SAMPLE: f32 = 30.0;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Theme {
    pub id: String,
    pub name: String,
    pub comment: String,
    /// "xcursor" or "hyprcursor" for cursor themes, empty for icon themes.
    pub kind: String,
    /// Preview files, PNG or SVG.
    pub samples: Vec<String>,
}

/// One kind of theme: what is installed and what is in use.
#[derive(Debug, Clone, Default)]
pub struct Themes {
    pub list: Vec<Theme>,
    /// Theme id → badge ("In use", "Apps", "Hyprland", "Apps · Hyprland").
    pub in_use: Vec<(String, String)>,
}

#[derive(Default)]
pub struct State {
    icons: Option<Themes>,
    cursors: Option<Themes>,
    /// Theme being applied.
    busy: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Icons(Result<Themes, String>),
    Cursors(Result<Themes, String>),
    UseIcon(String),
    UseCursor(String),
    Applied(Result<(), String>),
}

/// `list` output: a JSON array of {id, name, comment, kind?, samples}.
pub fn parse_list(json: &str) -> Result<Vec<Theme>, String> {
    let v: Json = serde_json::from_str(json).map_err(|e| format!("theme list: {e}"))?;
    let s = |t: &Json, k: &str| t[k].as_str().unwrap_or_default().to_string();
    Ok(v.as_array()
        .ok_or("theme list: not a list")?
        .iter()
        .map(|t| Theme {
            id: s(t, "id"),
            name: s(t, "name"),
            comment: s(t, "comment"),
            kind: s(t, "kind"),
            samples: t["samples"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|x| x.as_str().map(String::from))
                .collect(),
        })
        .filter(|t| !t.id.is_empty())
        .collect())
}

/// `cursor-theme.sh get`: {"apps": id, "hyprland": id} as badges.
pub fn cursor_badges(json: &str) -> Vec<(String, String)> {
    let v: Json = serde_json::from_str(json).unwrap_or(Json::Null);
    let (apps, hypr) = (
        v["apps"].as_str().unwrap_or_default(),
        v["hyprland"].as_str().unwrap_or_default(),
    );
    if apps == hypr {
        vec![(apps.to_string(), "Apps · Hyprland".into())]
    } else {
        vec![(apps.to_string(), "Apps".into()), (hypr.to_string(), "Hyprland".into())]
    }
}

/// Recent ids first (newest first), then the rest by name.
pub fn order(mut list: Vec<Theme>, recents: &[String]) -> Vec<Theme> {
    let rank = |t: &Theme| recents.iter().position(|r| *r == t.id).unwrap_or(recents.len());
    list.sort_by(|a, b| {
        rank(a)
            .cmp(&rank(b))
            .then(a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    list
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

fn recents(file: &str) -> Vec<String> {
    match store().read(file, Kind::Json) {
        Some(Value::Json(Json::Array(a))) => a.into_iter().filter_map(|v| v.as_str().map(String::from)).collect(),
        _ => Vec::new(),
    }
}

/// Put `id` (and the themes it replaces) at the front of the recents.
fn remember(file: &str, id: &str, replaced: &[String]) {
    let mut ids: Vec<String> = std::iter::once(id.to_string())
        .chain(replaced.iter().cloned())
        .chain(recents(file))
        .collect();
    let mut seen = std::collections::HashSet::new();
    ids.retain(|i| !i.is_empty() && seen.insert(i.clone()));
    let _ = store().write(
        file,
        &Value::Json(Json::Array(ids.into_iter().map(Json::String).collect())),
    );
}

fn script(name: &str) -> String {
    crate::store::home()
        .join(".config/scripts")
        .join(name)
        .to_string_lossy()
        .into_owned()
}

fn load_icons() -> Result<Themes, String> {
    let list = parse_list(&system::run_blocking(
        "bash",
        &[script("icon-theme.sh"), "list".into()],
        None,
    )?)?;
    let current = system::run_blocking("bash", &[script("icon-theme.sh"), "get".into()], None)?
        .trim()
        .to_string();
    Ok(Themes {
        list: order(list, &recents(ICON_RECENTS)),
        in_use: vec![(current, "In use".into())],
    })
}

fn load_cursors() -> Result<Themes, String> {
    let list = parse_list(&system::run_blocking(
        "bash",
        &[script("cursor-theme.sh"), "list".into()],
        None,
    )?)?;
    let badges = cursor_badges(&system::run_blocking(
        "bash",
        &[script("cursor-theme.sh"), "get".into()],
        None,
    )?);
    Ok(Themes {
        list: order(list, &recents(CURSOR_RECENTS)),
        in_use: badges,
    })
}

fn apply(script_name: &'static str, recents_file: &'static str, id: String, replaced: Vec<String>) -> Task<Msg> {
    Task::perform(
        system::spawn(move || {
            system::run_blocking("bash", &[script(script_name), "set".into(), id.clone()], None)?;
            remember(recents_file, &id, &replaced);
            Ok(())
        }),
        |r| Msg::Applied(r.unwrap_or_else(|| Err("applying stopped unexpectedly".into()))),
    )
}

fn spawn_load<T: Send + 'static>(f: fn() -> Result<T, String>, msg: fn(Result<T, String>) -> Msg) -> Task<Msg> {
    Task::perform(system::spawn(f), move |r| {
        msg(r.unwrap_or_else(|| Err("loading stopped unexpectedly".into())))
    })
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::batch([
                    spawn_load(load_icons, Msg::Icons),
                    spawn_load(load_cursors, Msg::Cursors),
                ]);
            }
            Msg::Icons(r) => match r {
                Ok(t) => self.icons = Some(t),
                Err(e) => self.error = Some(e),
            },
            Msg::Cursors(r) => match r {
                Ok(t) => self.cursors = Some(t),
                Err(e) => self.error = Some(e),
            },
            Msg::UseIcon(id) => {
                let replaced = self
                    .icons
                    .as_ref()
                    .map(|t| t.in_use.iter().map(|(i, _)| i.clone()).collect())
                    .unwrap_or_default();
                self.busy = Some(id.clone());
                return apply("icon-theme.sh", ICON_RECENTS, id, replaced);
            }
            Msg::UseCursor(id) => {
                let replaced = self
                    .cursors
                    .as_ref()
                    .map(|t| t.in_use.iter().map(|(i, _)| i.clone()).collect())
                    .unwrap_or_default();
                self.busy = Some(id.clone());
                return apply("cursor-theme.sh", CURSOR_RECENTS, id, replaced);
            }
            Msg::Applied(r) => {
                self.busy = None;
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
        body = ui::section(
            body,
            "Icon theme",
            self.rows(&self.icons, "Looking for icon themes…", Msg::UseIcon),
        );
        ui::section(
            body,
            "Cursor theme",
            self.rows(&self.cursors, "Looking for cursor themes…", Msg::UseCursor),
        )
    }

    fn rows<'a>(
        &'a self,
        themes: &'a Option<Themes>,
        loading: &'a str,
        on_use: fn(String) -> Msg,
    ) -> Vec<Element<'a, Msg>> {
        let Some(themes) = themes else {
            return vec![ui::note(loading)];
        };
        if themes.list.is_empty() {
            return vec![ui::note("None installed")];
        }
        themes.list.iter().map(|t| self.theme_row(t, themes, on_use)).collect()
    }

    fn theme_row<'a>(&'a self, t: &'a Theme, themes: &'a Themes, on_use: fn(String) -> Msg) -> Element<'a, Msg> {
        let badge = themes
            .in_use
            .iter()
            .find(|(id, _)| *id == t.id)
            .map(|(_, b)| b.as_str());
        let mut detail = t.comment.clone();
        if t.kind == "hyprcursor" {
            detail = format!(
                "Hyprcursor · Hyprland only{}",
                if detail.is_empty() {
                    String::new()
                } else {
                    format!(" · {detail}")
                }
            );
        }
        let control: Element<'a, Msg> = if self.busy.as_deref() == Some(t.id.as_str()) {
            ui::note("Applying…")
        } else if let Some(badge) = badge {
            text(badge).size(13).color(style::FG_MUTED).into()
        } else {
            ui::action(
                "Use",
                self.busy.is_none().then(|| on_use(t.id.clone())),
                Action::Primary,
            )
        };
        let samples = Row::with_children(t.samples.iter().map(|path| sample(path))).spacing(10);
        let mut info = column![text(t.name.clone()).size(14).color(style::FG)]
            .spacing(2)
            .width(Length::Fill);
        if !detail.is_empty() {
            info = info.push(text(detail).size(12).color(style::MUTED_DEEP));
        }
        let line = column![row![info, control].spacing(16).align_y(Alignment::Center), samples].spacing(8);
        container(line)
            .padding([10, 14])
            .style(if badge.is_some() {
                style::highlight
            } else {
                container::transparent
            })
            .into()
    }
}

/// One preview file: SVG drawn as a vector, anything else as an image.
fn sample<'a>(path: &str) -> Element<'a, Msg> {
    if path.ends_with(".svg") {
        svg(svg::Handle::from_path(path)).width(SAMPLE).height(SAMPLE).into()
    } else {
        image(image::Handle::from_path(path))
            .width(SAMPLE)
            .height(SAMPLE)
            .into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn theme(id: &str, name: &str) -> Theme {
        Theme {
            id: id.into(),
            name: name.into(),
            ..Theme::default()
        }
    }

    #[test]
    fn parses_theme_lists() {
        let json = r#"[{"id":"Papirus","name":"Papirus","comment":"Papirus icon theme","samples":["/a.svg","/b.png"]},
                       {"id":"rose","name":"rose","comment":"","kind":"hyprcursor","samples":[]},{"name":"no id"}]"#;
        let list = parse_list(json).unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].samples, ["/a.svg", "/b.png"]);
        assert_eq!(list[1].kind, "hyprcursor");
        assert!(parse_list("nope").is_err());
    }

    #[test]
    fn badges_cursor_themes() {
        assert_eq!(
            cursor_badges(r#"{"apps":"A","hyprland":"A"}"#),
            [("A".to_string(), "Apps · Hyprland".to_string())]
        );
        assert_eq!(cursor_badges(r#"{"apps":"A","hyprland":"H"}"#).len(), 2);
    }

    #[test]
    fn orders_recent_first_then_by_name() {
        let list = vec![theme("c", "Charlie"), theme("a", "alpha"), theme("b", "Bravo")];
        let ids: Vec<_> = order(list, &["b".into()]).into_iter().map(|t| t.id).collect();
        assert_eq!(ids, ["b", "a", "c"]);
    }
}
