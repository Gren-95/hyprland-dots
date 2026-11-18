//! Keyboard shortcuts panel: the key binds from hypr-binds.sh, each movable
//! to other keys. A move is kept in settings.lua (hypr.rs `binds`: the old
//! keys unbound, the action bound to the new ones) and applied to the live
//! Hyprland at once; keys.lua is never edited.

use std::collections::BTreeMap;

use iced::widget::{Column, Row, column, container, row, text, text_input};
use iced::{Alignment, Element, Length, Task};
use serde_json::Value as Json;

use crate::hypr::{self, Rebind, Settings};
use crate::style::{self, Action};
use crate::system;
use crate::ui;

/// Modifier names in Hyprland's order, with their modmask bit.
const MODS: [(&str, u64); 4] = [("SUPER", 64), ("CTRL", 4), ("ALT", 8), ("SHIFT", 1)];
/// MODS as people write them.
const MOD_LABELS: [&str; 4] = ["Super", "Ctrl", "Alt", "Shift"];
/// Keys a shortcut can use (xkb names as Hyprland writes them).
const KEYS: &[&str] = &[
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
    "F1",
    "F2",
    "F3",
    "F4",
    "F5",
    "F6",
    "F7",
    "F8",
    "F9",
    "F10",
    "F11",
    "F12",
    "Return",
    "space",
    "Tab",
    "Escape",
    "BackSpace",
    "Delete",
    "Insert",
    "Home",
    "End",
    "Prior",
    "Next",
    "left",
    "right",
    "up",
    "down",
    "Print",
    "comma",
    "period",
    "slash",
    "semicolon",
    "apostrophe",
    "bracketleft",
    "bracketright",
    "minus",
    "equal",
    "grave",
    "backslash",
    "KP_Add",
    "KP_Subtract",
    "KP_Enter",
    "XF86AudioRaiseVolume",
    "XF86AudioLowerVolume",
    "XF86AudioMute",
    "XF86AudioMicMute",
    "XF86AudioPlay",
    "XF86AudioNext",
    "XF86AudioPrev",
    "XF86MonBrightnessUp",
    "XF86MonBrightnessDown",
    "XF86Calculator",
];
const MAX_KEY_MATCHES: usize = 8;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Bind {
    pub combo: String,
    pub description: String,
    pub action: String,
    pub locked: bool,
    pub repeating: bool,
}

/// "SUPER + CTRL + R" from a modmask and a key.
pub fn combo_of(modmask: u64, key: &str) -> String {
    let mut parts: Vec<&str> = MODS
        .iter()
        .filter(|(_, bit)| modmask & bit != 0)
        .map(|(m, _)| *m)
        .collect();
    parts.push(key);
    parts.join(" + ")
}

/// Same keys: the same modifiers and key (letters in any case).
pub fn same_combo(a: &str, b: &str) -> bool {
    let norm = |c: &str| {
        let mut parts: Vec<String> = c.split('+').map(|p| p.trim().to_uppercase()).collect();
        let key = parts.pop().unwrap_or_default();
        parts.sort();
        (parts, key)
    };
    norm(a) == norm(b)
}

/// Keyboard binds from hypr-binds.sh, without mouse buttons and switches.
pub fn parse_binds(json: &str) -> Result<Vec<Bind>, String> {
    let v: Json = serde_json::from_str(json).map_err(|e| format!("hypr-binds.sh: {e}"))?;
    Ok(v.as_array()
        .ok_or("hypr-binds.sh: not a list")?
        .iter()
        .filter(|b| !b["mouse"].as_bool().unwrap_or(false))
        .filter(|b| b["submap"].as_str().unwrap_or("").is_empty())
        .filter_map(|b| {
            let key = b["key"].as_str()?;
            if key.starts_with("switch:") || key.starts_with("mouse") {
                return None;
            }
            Some(Bind {
                combo: combo_of(b["modmask"].as_u64().unwrap_or(0), key),
                description: b["description"].as_str().unwrap_or_default().to_string(),
                action: b["lua"].as_str().unwrap_or_default().to_string(),
                locked: b["locked"].as_bool().unwrap_or(false),
                repeating: b["repeat"].as_bool().unwrap_or(false),
            })
        })
        .collect())
}

/// Binds whose description, keys or action contain every word.
pub fn filter<'a>(binds: &'a [Bind], query: &str) -> Vec<(usize, &'a Bind)> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    binds
        .iter()
        .enumerate()
        .filter(|(_, b)| {
            let hay = format!("{} {} {}", b.description, b.combo, b.action).to_lowercase();
            words.iter().all(|w| hay.contains(w))
        })
        .collect()
}

#[derive(Debug, Clone, Default)]
struct Editor {
    /// Index into `binds`.
    index: usize,
    mods: [bool; 4],
    key: String,
    key_query: String,
}

impl Editor {
    fn combo(&self) -> String {
        let mut parts: Vec<&str> = MODS
            .iter()
            .zip(self.mods)
            .filter(|(_, on)| *on)
            .map(|((m, _), _)| *m)
            .collect();
        parts.push(&self.key);
        parts.join(" + ")
    }
}

#[derive(Default)]
pub struct State {
    binds: Vec<Bind>,
    /// Moved binds by original combo.
    moved: BTreeMap<String, Rebind>,
    loaded: bool,
    query: String,
    editor: Option<Editor>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Result<(Vec<Bind>, BTreeMap<String, Rebind>), String>),
    Search(String),
    Edit(usize),
    ToggleMod(usize),
    KeyQuery(String),
    PickKey(&'static str),
    Save,
    Cancel,
    Reset(usize),
    Applied(Result<(), String>),
}

fn load() -> Result<(Vec<Bind>, BTreeMap<String, Rebind>), String> {
    let script = crate::store::home()
        .join(".config/scripts/hypr-binds.sh")
        .to_string_lossy()
        .into_owned();
    let binds = parse_binds(&system::run_blocking("bash", &[script], None)?)?;
    Ok((binds, Settings::load().binds))
}

impl State {
    /// The original keys of a bind now on `combo`, when it was moved.
    fn original_of(&self, combo: &str) -> Option<&String> {
        self.moved
            .iter()
            .find(|(_, r)| same_combo(&r.combo, combo))
            .map(|(orig, _)| orig)
    }

    /// The bind (other than `index`) already on `combo`.
    fn taken_by(&self, combo: &str, index: usize) -> Option<&Bind> {
        self.binds
            .iter()
            .enumerate()
            .find(|(i, b)| *i != index && same_combo(&b.combo, combo))
            .map(|(_, b)| b)
    }

    /// Move bind `index` to `new` keys (its original keys reset it).
    fn move_to(&mut self, index: usize, new: String) -> Task<Msg> {
        let Some(bind) = self.binds.get(index).cloned() else {
            return Task::none();
        };
        let original = self
            .original_of(&bind.combo)
            .cloned()
            .unwrap_or_else(|| bind.combo.clone());
        let extra = match (
            hypr::unbind_lua(&bind.combo),
            hypr::bind_lua(&new, &bind.action, bind.locked, bind.repeating),
        ) {
            (Ok(u), Ok(b)) => format!("\n{u}\n{b}\n"),
            (Err(e), _) | (_, Err(e)) => {
                self.error = Some(e);
                return Task::none();
            }
        };
        let back_to_original = same_combo(&new, &original);
        let rebind = Rebind {
            combo: new,
            action: bind.action,
            locked: bind.locked,
            repeating: bind.repeating,
        };
        Task::perform(
            hypr::update_with(
                move |s| {
                    if back_to_original {
                        s.binds.remove(&original);
                    } else {
                        s.binds.insert(original, rebind);
                    }
                },
                extra,
            ),
            Msg::Applied,
        )
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::perform(system::spawn(load), |r| {
                    Msg::Loaded(r.unwrap_or_else(|| Err("loading stopped unexpectedly".into())))
                });
            }
            Msg::Loaded(Ok((binds, moved))) => {
                self.binds = binds;
                self.moved = moved;
                self.loaded = true;
            }
            Msg::Loaded(Err(e)) => self.error = Some(e),
            Msg::Search(q) => self.query = q,
            Msg::Edit(index) => {
                if let Some(b) = self.binds.get(index) {
                    let mut parts: Vec<String> = b.combo.split(" + ").map(String::from).collect();
                    let key = parts.pop().unwrap_or_default();
                    let mods = MODS.map(|(m, _)| parts.iter().any(|p| p == m));
                    self.editor = Some(Editor {
                        index,
                        mods,
                        key,
                        key_query: String::new(),
                    });
                }
            }
            Msg::ToggleMod(i) => {
                if let Some(e) = &mut self.editor {
                    e.mods[i] = !e.mods[i];
                }
            }
            Msg::KeyQuery(q) => {
                if let Some(e) = &mut self.editor {
                    e.key_query = q;
                }
            }
            Msg::PickKey(key) => {
                if let Some(e) = &mut self.editor {
                    e.key = key.to_string();
                    e.key_query.clear();
                }
            }
            Msg::Cancel => self.editor = None,
            Msg::Save => {
                if let Some(editor) = self.editor.take() {
                    let new = editor.combo();
                    if let Some(other) = self.taken_by(&new, editor.index) {
                        self.error = Some(format!("{new} is already used by: {}", label(other)));
                        self.editor = Some(editor);
                        return Task::none();
                    }
                    return self.move_to(editor.index, new);
                }
            }
            Msg::Reset(index) => {
                if let Some(original) = self.binds.get(index).and_then(|b| self.original_of(&b.combo)).cloned() {
                    if let Some(other) = self.taken_by(&original, index) {
                        self.error = Some(format!("{original} is now used by: {}", label(other)));
                        return Task::none();
                    }
                    return self.move_to(index, original);
                }
            }
            Msg::Applied(r) => {
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
        if !self.loaded {
            return ui::section(body, "Shortcuts", vec![ui::note("Loading…")]);
        }
        let search = text_input("Search shortcuts: what they do or their keys", &self.query)
            .on_input(Msg::Search)
            .padding([7, 10])
            .style(style::field);
        body = body.push(search);
        let mut rows: Vec<Element<'a, Msg>> = Vec::new();
        for (i, b) in filter(&self.binds, &self.query) {
            rows.push(self.bind_row(i, b));
            if let Some(editor) = self.editor.as_ref().filter(|e| e.index == i) {
                rows.push(self.editor_view(editor));
            }
        }
        if rows.is_empty() {
            rows.push(ui::note("No shortcut matches"));
        }
        ui::section(body, "Shortcuts", rows)
    }

    fn bind_row<'a>(&'a self, i: usize, b: &'a Bind) -> Element<'a, Msg> {
        let moved = self.original_of(&b.combo);
        let mut info = column![text(label(b)).size(14).color(style::FG)]
            .spacing(2)
            .width(Length::Fill);
        if let Some(original) = moved {
            info = info.push(text(format!("Was {original}")).size(12).color(style::MUTED_DEEP));
        }
        let mut buttons = Vec::new();
        if moved.is_some() {
            buttons.push(("↺", Some(Msg::Reset(i)), Action::Normal));
        }
        buttons.push(("Change", Some(Msg::Edit(i)), Action::Normal));
        let line = row![info, keycaps(&b.combo), ui::button_group(buttons)]
            .spacing(12)
            .align_y(Alignment::Center);
        container(line).padding([8, 14]).into()
    }

    fn editor_view<'a>(&'a self, e: &'a Editor) -> Element<'a, Msg> {
        let mods = MOD_LABELS
            .iter()
            .enumerate()
            .map(|(i, m)| (*m, e.mods[i], Some(Msg::ToggleMod(i))))
            .collect();
        let words: Vec<String> = e.key_query.split_whitespace().map(str::to_lowercase).collect();
        let matches = if words.is_empty() {
            Vec::new()
        } else {
            KEYS.iter()
                .filter(|k| words.iter().all(|w| k.to_lowercase().contains(w)))
                .take(MAX_KEY_MATCHES)
                .map(|k| ui::PickerMatch {
                    label: k.to_string(),
                    font: None,
                    detail: String::new(),
                    on_pick: Msg::PickKey(k),
                })
                .collect()
        };
        let new = e.combo();
        let conflict = self
            .taken_by(&new, e.index)
            .map(|b| format!("Already used by: {}", label(b)));
        let line = |title: &'a str, control: Element<'a, Msg>| {
            row![text(title).size(13).color(style::FG_MUTED).width(80), control]
                .spacing(10)
                .align_y(Alignment::Center)
        };
        let mut col = column![
            line("Modifiers", ui::multi_select(mods, Length::Fill)),
            line(
                "Key",
                row![
                    keycaps(&e.key),
                    ui::search_picker("Search a key", &e.key_query, Msg::KeyQuery, matches)
                ]
                .spacing(10)
                .into()
            ),
            line("New keys", keycaps(&new)),
        ]
        .spacing(10);
        if let Some(c) = &conflict {
            col = col.push(text(c.clone()).size(12).color(style::RED));
        }
        let unchanged = self.binds.get(e.index).is_some_and(|b| same_combo(&b.combo, &new));
        let save = (conflict.is_none() && !e.key.is_empty() && !unchanged).then_some(Msg::Save);
        col = col.push(row![
            iced::widget::Space::new().width(Length::Fill),
            ui::button_group(vec![
                ("Cancel", Some(Msg::Cancel), Action::Normal),
                ("Save", save, Action::Primary)
            ])
        ]);
        container(col).padding([8, 14]).style(style::card).into()
    }
}

/// What a bind does, for people: its description, else its action.
fn label(b: &Bind) -> String {
    if b.description.is_empty() {
        b.action.clone()
    } else {
        b.description.clone()
    }
}

/// Keys drawn as keycaps: SUPER + R as [Super] [R].
fn keycaps<'a>(combo: &str) -> Element<'a, Msg> {
    let caps = combo.split(" + ").filter(|p| !p.is_empty()).map(|part| {
        let name = match part {
            "SUPER" => "Super".to_string(),
            "CTRL" => "Ctrl".to_string(),
            "ALT" => "Alt".to_string(),
            "SHIFT" => "Shift".to_string(),
            k => k.to_string(),
        };
        container(text(name).size(12).color(style::FG))
            .padding([2, 7])
            .style(style::keycap)
            .into()
    });
    Row::with_children(caps).spacing(4).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builds_combos() {
        assert_eq!(combo_of(64, "R"), "SUPER + R");
        assert_eq!(combo_of(64 | 1, "S"), "SUPER + SHIFT + S");
        assert_eq!(combo_of(0, "XF86AudioMute"), "XF86AudioMute");
        assert!(same_combo("SHIFT + SUPER + s", "SUPER + SHIFT + S"));
        assert!(!same_combo("SUPER + S", "SUPER + SHIFT + S"));
    }

    #[test]
    fn keeps_keyboard_binds_only() {
        let json = r#"[
          {"modmask":64,"key":"R","description":"Open the app launcher","lua":"hl.dsp.global(\"quickshell:spotlight\")","locked":false,"repeat":false,"mouse":false,"submap":""},
          {"modmask":64,"key":"mouse:272","lua":"hl.dsp.window.drag()","mouse":true,"submap":""},
          {"modmask":0,"key":"switch:on:Lid Switch","lua":"hl.dsp.exec_cmd(\"x\")","mouse":false,"submap":""},
          {"modmask":0,"key":"XF86AudioMute","lua":"hl.dsp.exec_cmd(\"m\")","locked":true,"repeat":false,"mouse":false,"submap":""}
        ]"#;
        let binds = parse_binds(json).unwrap();
        assert_eq!(binds.len(), 2);
        assert_eq!(binds[0].combo, "SUPER + R");
        assert!(binds[1].locked);
        assert_eq!(filter(&binds, "launcher").len(), 1);
        assert_eq!(filter(&binds, "super r").len(), 1);
    }

    #[test]
    fn editor_builds_its_combo() {
        let e = Editor {
            index: 0,
            mods: [true, false, false, true],
            key: "D".into(),
            key_query: String::new(),
        };
        assert_eq!(e.combo(), "SUPER + SHIFT + D");
    }
}
