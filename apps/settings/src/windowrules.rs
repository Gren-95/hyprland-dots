//! Windows panel's window rules: per-app rules (float at a size, see-through, open on
//! a workspace), one per window class. Kept in settings.json and written to
//! the gitignored settings.lua as `hl.window_rule` calls (hypr.rs); the
//! tracked rules.lua is not touched. Hyprland reloads after a change, and
//! rules count for windows opened after it.

use iced::widget::{container, text_input};
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::hypr::{self, WindowRule};
use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

const OPACITY: &[(Option<i64>, &str)] = &[
    (None, "Solid"),
    (Some(95), "95 %"),
    (Some(90), "90 %"),
    (Some(80), "80 %"),
    (Some(70), "70 %"),
];
const WORKSPACES: &[&str] = &["", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10"];

/// A one-line summary of what a rule does.
pub fn summary(r: &WindowRule) -> String {
    let mut parts = Vec::new();
    if r.float {
        parts.push(if r.size.is_empty() {
            "Floats".to_string()
        } else {
            format!("Floats at {}", r.size.replace(' ', " × "))
        });
    }
    if let Some(o) = r.opacity {
        parts.push(format!("{o} % opaque"));
    }
    if !r.workspace.is_empty() {
        parts.push(format!("Opens on workspace {}", r.workspace));
    }
    if parts.is_empty() {
        "Does nothing yet".into()
    } else {
        parts.join(" · ")
    }
}

/// `hyprctl clients -j`: the classes of open windows, without repeats.
pub fn parse_classes(json: &str) -> Vec<(String, String)> {
    let v: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    let mut list: Vec<(String, String)> = Vec::new();
    for c in v.as_array().into_iter().flatten() {
        let class = c["class"].as_str().unwrap_or_default();
        if hypr::valid_class(class) && !list.iter().any(|(k, _)| k == class) {
            list.push((class.to_string(), c["title"].as_str().unwrap_or_default().to_string()));
        }
    }
    list
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub rules: Vec<WindowRule>,
    /// Open windows: (class, title).
    pub open: Vec<(String, String)>,
    /// Installed apps: (desktop id without .desktop, name), to name classes.
    pub names: Vec<(String, String)>,
}

fn read() -> Reading {
    Reading {
        rules: hypr::Settings::load().rules,
        open: parse_classes(&system::run_blocking("hyprctl", &args(&["clients", "-j"]), None).unwrap_or_default()),
        names: crate::defaultapps::installed()
            .into_iter()
            .map(|a| (a.id.trim_end_matches(".desktop").to_string(), a.name))
            .collect(),
    }
}

/// Save the rules and reload Hyprland, which reads settings.lua again.
async fn save(rules: Vec<WindowRule>) -> Result<(), String> {
    hypr::update(move |s| s.rules = rules).await?;
    system::run("hyprctl", args(&["reload"]), None).await.map(|_| ())
}

#[derive(Default)]
pub struct State {
    reading: Option<Reading>,
    /// The class whose rule is open.
    open: Option<String>,
    size_draft: String,
    adding: bool,
    query: String,
    confirming: Option<String>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Reading),
    Toggle(String),
    Float(String, bool),
    SizeText(String),
    SaveSize(String),
    Opacity(String, Option<i64>),
    Workspace(String, &'static str),
    Remove(String),
    StartAdd,
    CancelAdd,
    Query(String),
    Add(String),
    Done(Result<(), String>),
}

impl State {
    fn rules(&self) -> Vec<WindowRule> {
        self.reading.as_ref().map(|r| r.rules.clone()).unwrap_or_default()
    }

    /// Change one rule and save them all.
    fn change(&mut self, class: &str, edit: impl FnOnce(&mut WindowRule)) -> Task<Msg> {
        let mut rules = self.rules();
        let Some(rule) = rules.iter_mut().find(|r| r.class == class) else {
            return Task::none();
        };
        edit(rule);
        self.store(rules)
    }

    fn store(&mut self, rules: Vec<WindowRule>) -> Task<Msg> {
        if let Err(e) = hypr::rules_lua(&rules) {
            self.error = Some(e);
            return Task::none();
        }
        self.busy = true;
        if let Some(r) = &mut self.reading {
            r.rules = rules.clone();
        }
        Task::perform(save(rules), Msg::Done)
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(msg, Msg::Remove(_) | Msg::Loaded(_) | Msg::Load) {
            self.confirming = None;
        }
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => {
                self.reading = Some(r);
                self.busy = false;
            }
            Msg::Toggle(class) => {
                self.size_draft.clear();
                self.open = if self.open.as_ref() == Some(&class) {
                    None
                } else {
                    Some(class)
                };
            }
            Msg::Float(class, on) => return self.change(&class, |r| r.float = on),
            Msg::SizeText(t) => self.size_draft = t,
            Msg::SaveSize(class) => {
                let size = self
                    .size_draft
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
                    .replace(['x', '×'], " ");
                let size = size.split_whitespace().collect::<Vec<_>>().join(" ");
                if !size.is_empty() && !hypr::valid_size(&size) {
                    self.error = Some("A size is a width and a height in pixels, like 800 600".into());
                    return Task::none();
                }
                self.size_draft.clear();
                return self.change(&class, |r| r.size = size);
            }
            Msg::Opacity(class, o) => return self.change(&class, |r| r.opacity = o),
            Msg::Workspace(class, w) => return self.change(&class, |r| r.workspace = w.to_string()),
            Msg::Remove(class) if self.confirming.as_ref() != Some(&class) => self.confirming = Some(class),
            Msg::Remove(class) => {
                self.confirming = None;
                let rules = self.rules().into_iter().filter(|r| r.class != class).collect();
                return self.store(rules);
            }
            Msg::StartAdd => {
                self.adding = true;
                self.query.clear();
                // The open windows may have changed since the panel opened.
                return self.update(Msg::Load);
            }
            Msg::CancelAdd => self.adding = false,
            Msg::Query(q) => self.query = q,
            Msg::Add(class) => {
                self.adding = false;
                let mut rules = self.rules();
                if !rules.iter().any(|r| r.class == class) {
                    rules.push(WindowRule {
                        class: class.clone(),
                        float: true,
                        ..WindowRule::default()
                    });
                }
                self.open = Some(class);
                return self.store(rules);
            }
            Msg::Done(r) => {
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    fn name<'a>(&'a self, class: &'a str) -> &'a str {
        self.reading
            .as_ref()
            .and_then(|r| r.names.iter().find(|(id, _)| id.eq_ignore_ascii_case(class)))
            .map_or(class, |(_, n)| n.as_str())
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(reading) = &self.reading else {
            return vec![ui::note("Looking…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let idle = !self.busy;
        for r in &reading.rules {
            let open = self.open.as_ref() == Some(&r.class);
            let name = self.name(&r.class);
            let title = if name == r.class {
                r.class.clone()
            } else {
                format!("{name} ({})", r.class)
            };
            rows.push(ui::item(
                ico::APP_WINDOW,
                title,
                summary(r),
                vec![
                    ui::confirm_action(
                        ico::TRASH,
                        "Remove the rule",
                        self.confirming.as_ref() == Some(&r.class),
                        idle.then(|| Msg::Remove(r.class.clone())),
                    ),
                    ui::disclosure(open, Msg::Toggle(r.class.clone())),
                ],
            ));
            if open {
                let details = self.details(r, idle);
                let count = details.len();
                rows.extend(
                    details
                        .into_iter()
                        .enumerate()
                        .map(|(i, d)| ui::branch(d, i + 1 == count)),
                );
            }
        }
        if reading.rules.is_empty() {
            rows.push(ui::note("No rules yet: every window follows Hyprland's own rules"));
        }
        rows.push(ui::item(
            ico::PLUS,
            "Add a rule".into(),
            "For an app with a window open now".into(),
            vec![if self.adding {
                ui::action("Cancel", Some(Msg::CancelAdd), Action::Normal)
            } else {
                ui::icon_action(ico::PLUS, "Add", idle.then_some(Msg::StartAdd), Action::Normal)
            }],
        ));
        if self.adding {
            let matches = reading
                .open
                .iter()
                .filter(|(c, _)| !reading.rules.iter().any(|r| r.class == *c))
                .filter(|(c, t)| {
                    ui::matches_query(c, &self.query)
                        || ui::matches_query(t, &self.query)
                        || ui::matches_query(self.name(c), &self.query)
                })
                .take(8)
                .map(|(c, t)| ui::PickerMatch {
                    label: self.name(c).to_string(),
                    font: None,
                    detail: if self.name(c) == c { t.clone() } else { c.clone() },
                    on_pick: Msg::Add(c.clone()),
                })
                .collect();
            let picker = ui::search_picker("Search open windows", &self.query, Msg::Query, matches);
            rows.push(container(picker).padding([4, 14]).into());
        }
        rows
    }

    fn details<'a>(&'a self, r: &'a WindowRule, idle: bool) -> Vec<Element<'a, Msg>> {
        let class = r.class.clone();
        let mut rows = vec![ui::item(
            ico::PICTURE_IN_PICTURE_2,
            "Float".into(),
            "Open on top of the tiled windows".into(),
            vec![ui::switch(
                r.float,
                idle.then_some(move |on| Msg::Float(class.clone(), on)),
            )],
        )];
        if r.float {
            let field = text_input(if r.size.is_empty() { "800 600" } else { &r.size }, &self.size_draft)
                .on_input(Msg::SizeText)
                .on_submit(Msg::SaveSize(r.class.clone()))
                .padding([6, 10])
                .width(120)
                .style(style::field);
            rows.push(ui::item(
                ico::SCALING,
                "Size".into(),
                if r.size.is_empty() {
                    "Width and height in pixels; Enter to save".into()
                } else {
                    "Enter to save; empty Enter lets the app choose".into()
                },
                vec![field.into()],
            ));
        }
        let opacity = OPACITY
            .iter()
            .map(|(v, l)| (*l, r.opacity == *v, idle.then(|| Msg::Opacity(r.class.clone(), *v))))
            .collect();
        rows.push(ui::item(
            ico::BLEND,
            "Opacity".into(),
            "See-through windows show what is behind them".into(),
            vec![ui::select(opacity, Length::Fixed(160.0))],
        ));
        let workspaces = WORKSPACES
            .iter()
            .map(|w| {
                let label = if w.is_empty() { "Where it opens" } else { w };
                (
                    label,
                    r.workspace == *w,
                    idle.then(|| Msg::Workspace(r.class.clone(), w)),
                )
            })
            .collect();
        rows.push(ui::item(
            ico::LAYOUT_GRID,
            "Workspace".into(),
            "Always open on this workspace".into(),
            vec![ui::select(workspaces, Length::Fixed(160.0))],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summarises_rules() {
        let r = WindowRule {
            class: "kitty".into(),
            float: true,
            size: "800 600".into(),
            opacity: Some(90),
            workspace: "2".into(),
        };
        assert_eq!(summary(&r), "Floats at 800 × 600 · 90 % opaque · Opens on workspace 2");
        assert_eq!(
            summary(&WindowRule {
                class: "x".into(),
                ..WindowRule::default()
            }),
            "Does nothing yet"
        );
    }

    #[test]
    fn lists_open_classes_once() {
        let json = r#"[{"class": "kitty", "title": "a"}, {"class": "kitty", "title": "b"}, {"class": "", "title": "c"}, {"class": "org.mozilla.firefox", "title": "d"}]"#;
        assert_eq!(
            parse_classes(json),
            [
                ("kitty".to_string(), "a".to_string()),
                ("org.mozilla.firefox".to_string(), "d".to_string())
            ]
        );
    }
}
