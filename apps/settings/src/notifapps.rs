//! Per-app notification rules on the Notifications panel: every app that
//! sent a notification (notif-apps-seen.json, kept by the shell) shows,
//! hides toasts for, or mutes its notifications (notif-app-rules.json:
//! appName -> "quiet" | "mute"; no entry shows them).

use iced::{Element, Length};
use lucide_iced::bytes as ico;
use serde_json::{Map, Value as Json};

use crate::store::{Kind, Store, Value};
use crate::ui;

const SEEN: &str = "notif-apps-seen.json";
const RULES: &str = "notif-app-rules.json";

/// (rule, label); "" shows notifications as usual.
const CHOICES: &[(&str, &str)] = &[("", "Show"), ("quiet", "No toasts"), ("mute", "Mute")];

#[derive(Default)]
pub struct State {
    apps: Vec<String>,
    /// The list is open, and its search.
    open: bool,
    query: String,
    rules: Map<String, Json>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    /// (app name, rule)
    Set(String, &'static str),
    Toggle,
    Query(String),
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

/// The seen list as app names, sorted, without empty ones.
pub fn parse_seen(v: Option<Value>) -> Vec<String> {
    let mut apps: Vec<String> = match v {
        Some(Value::Json(Json::Array(a))) => a.into_iter().filter_map(|x| x.as_str().map(String::from)).collect(),
        _ => Vec::new(),
    };
    apps.retain(|a| !a.trim().is_empty());
    apps.sort_by_key(|a| a.to_lowercase());
    apps.dedup();
    apps
}

/// The rules with `app` set to `rule`; "" removes its entry.
pub fn with_rule(mut rules: Map<String, Json>, app: &str, rule: &str) -> Map<String, Json> {
    if rule.is_empty() {
        rules.remove(app);
    } else {
        rules.insert(app.to_string(), Json::String(rule.to_string()));
    }
    rules
}

impl State {
    pub fn update(&mut self, msg: Msg) {
        match msg {
            Msg::Load => {
                let s = store();
                self.apps = parse_seen(s.read(SEEN, Kind::Json));
                self.rules = match s.read(RULES, Kind::Json) {
                    Some(Value::Json(Json::Object(m))) => m,
                    _ => Map::new(),
                };
            }
            Msg::Toggle => {
                self.open = !self.open;
                self.query.clear();
            }
            Msg::Query(q) => self.query = q,
            Msg::Set(app, rule) => {
                let rules = with_rule(self.rules.clone(), &app, rule);
                match store().write(RULES, &Value::Json(Json::Object(rules.clone()))) {
                    Ok(()) => {
                        self.rules = rules;
                        self.error = None;
                    }
                    Err(e) => self.error = Some(format!("Could not save the rule: {e}")),
                }
            }
        }
    }

    /// One row per app with its rule as a dropdown.
    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if self.apps.is_empty() {
            rows.push(ui::note("Apps show up here once they send a notification"));
        }
        let entries = self
            .apps
            .iter()
            .filter(|app| ui::matches_query(app, &self.query))
            .map(|app| {
                let current = self.rules.get(app).and_then(Json::as_str).unwrap_or("");
                let items = CHOICES
                    .iter()
                    .map(|(rule, label)| (*label, *rule == current, Some(Msg::Set(app.clone(), rule))))
                    .collect();
                let glyph = match current {
                    "mute" => ico::BELL_OFF,
                    "quiet" => ico::BELL_MINUS,
                    _ => ico::BELL,
                };
                ui::item(
                    glyph,
                    app.clone(),
                    String::new(),
                    vec![ui::select(items, Length::Fixed(160.0))],
                )
            })
            .collect();
        if !self.apps.is_empty() {
            let changed = self.rules.len();
            let summary = match changed {
                0 => format!("{} apps, all shown", self.apps.len()),
                n => format!("{} apps, {n} without toasts or muted", self.apps.len()),
            };
            rows.extend(ui::collapsed_list(
                ico::BELL,
                "Per app",
                summary,
                self.open,
                Msg::Toggle,
                &self.query,
                Msg::Query,
                entries,
                self.apps.len(),
            ));
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_seen_apps_once_by_name() {
        let seen = Value::Json(serde_json::json!(["kitty", "", "Firefox", "kitty"]));
        assert_eq!(parse_seen(Some(seen)), ["Firefox", "kitty"]);
        assert!(parse_seen(None).is_empty());
    }

    #[test]
    fn showing_removes_the_rule() {
        let rules = with_rule(Map::new(), "kitty", "mute");
        assert_eq!(rules["kitty"], "mute");
        assert!(with_rule(rules, "kitty", "").is_empty());
    }
}
