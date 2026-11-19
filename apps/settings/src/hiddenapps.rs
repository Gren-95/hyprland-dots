//! Apps hidden from the launcher (hidden-apps.json: desktop id -> true, set
//! with Ctrl+D in the launcher), listed by name on the Launcher panel with a
//! button to show each again.

use iced::Element;
use lucide_iced::bytes as ico;
use serde_json::{Map, Value as Json};

use crate::defaultapps;
use crate::store::{Kind, Store, Value};
use crate::style::Action;
use crate::system;
use crate::ui;

const FILE: &str = "hidden-apps.json";

/// A hidden app: its desktop id and the name to show.
#[derive(Debug, Clone, PartialEq)]
pub struct Hidden {
    pub id: String,
    pub name: String,
}

#[derive(Default)]
pub struct State {
    hidden: Option<Vec<Hidden>>,
    /// The list is open, and its search.
    open: bool,
    query: String,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Vec<Hidden>),
    Show(String),
    Toggle,
    Query(String),
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

fn read_ids() -> Map<String, Json> {
    match store().read(FILE, Kind::Json) {
        Some(Value::Json(Json::Object(m))) => m,
        _ => Map::new(),
    }
}

/// Hidden ids with names from `names` (desktop id without ".desktop" ->
/// name); an id with no installed app keeps its id as name. By name.
pub fn named(ids: &Map<String, Json>, names: &[(String, String)]) -> Vec<Hidden> {
    let mut list: Vec<Hidden> = ids
        .iter()
        .filter(|(_, on)| on.as_bool() == Some(true))
        .map(|(id, _)| Hidden {
            id: id.clone(),
            name: names
                .iter()
                .find(|(i, _)| i == id)
                .map_or_else(|| id.clone(), |(_, n)| n.clone()),
        })
        .collect();
    list.sort_by_key(|h| h.name.to_lowercase());
    list
}

fn load() -> Vec<Hidden> {
    let names: Vec<(String, String)> = defaultapps::installed()
        .into_iter()
        .map(|a| (a.id.trim_end_matches(".desktop").to_string(), a.name))
        .collect();
    named(&read_ids(), &names)
}

impl State {
    pub fn update(&mut self, msg: Msg) -> iced::Task<Msg> {
        match msg {
            Msg::Load => return iced::Task::perform(system::spawn(load), |l| Msg::Loaded(l.unwrap_or_default())),
            Msg::Loaded(list) => self.hidden = Some(list),
            Msg::Toggle => {
                self.open = !self.open;
                self.query.clear();
            }
            Msg::Query(q) => self.query = q,
            Msg::Show(id) => {
                let mut ids = read_ids();
                ids.remove(&id);
                match store().write(FILE, &Value::Json(Json::Object(ids))) {
                    Ok(()) => {
                        self.error = None;
                        if let Some(list) = &mut self.hidden {
                            list.retain(|h| h.id != id);
                        }
                    }
                    Err(e) => self.error = Some(format!("Could not show the app again: {e}")),
                }
            }
        }
        iced::Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        match &self.hidden {
            None => rows.push(ui::note("Loading…")),
            Some(list) if list.is_empty() => {
                rows.push(ui::note("No hidden apps. Hide one with Ctrl+D in the launcher"))
            }
            Some(list) => {
                let entries = list
                    .iter()
                    .filter(|h| ui::matches_query(&h.name, &self.query) || ui::matches_query(&h.id, &self.query))
                    .map(|h| {
                        let detail = if h.name == h.id { String::new() } else { h.id.clone() };
                        ui::item(
                            ico::EYE_OFF,
                            h.name.clone(),
                            detail,
                            vec![ui::action("Show again", Some(Msg::Show(h.id.clone())), Action::Normal)],
                        )
                    })
                    .collect();
                let summary = format!("{} hidden from the launcher (Ctrl+D there)", list.len());
                rows.extend(ui::collapsed_list(
                    ico::EYE_OFF,
                    "Hidden apps",
                    summary,
                    self.open,
                    Msg::Toggle,
                    &self.query,
                    Msg::Query,
                    entries,
                    list.len(),
                ));
            }
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_hidden_apps_and_keeps_unknown_ids() {
        let ids = serde_json::json!({"org.gnome.Evince": true, "zz-gone": true, "off": false});
        let names = vec![("org.gnome.Evince".to_string(), "Document Viewer".to_string())];
        let list = named(ids.as_object().unwrap(), &names);
        assert_eq!(list.len(), 2);
        assert_eq!(
            list[0],
            Hidden {
                id: "org.gnome.Evince".into(),
                name: "Document Viewer".into()
            }
        );
        assert_eq!(list[1].name, "zz-gone");
    }
}
