//! Keyboard panel: layouts, the layout switch shortcut, Caps Lock, Num Lock
//! and key repeat, stored and applied through hypr.rs.

use std::fmt;

use iced::widget::{Column, column, container, pick_list, row, slider, text, text_input, toggler};
use iced::{Alignment, Element, Length, Task};

use crate::hypr::{Keyboard, Settings};
use crate::style::{self, Action};
use crate::system;
use crate::ui;

const XKB_LIST: &str = "/usr/share/X11/xkb/rules/evdev.lst";
/// Most search matches listed when adding a layout.
const MAX_MATCHES: usize = 8;

/// Layout switch shortcuts: (XKB option, label). Super+Space is taken by
/// the wallpaper deck, so it is not offered.
const SWITCHES: &[(&str, &str)] = &[
    ("", "None"),
    ("grp:alt_shift_toggle", "Alt+Shift"),
    ("grp:ctrl_shift_toggle", "Ctrl+Shift"),
    ("grp:caps_toggle", "Caps Lock"),
    ("grp:toggle", "Right Alt"),
    ("grp:menu_toggle", "Menu key"),
];
/// Caps Lock behaviours: (XKB option, label).
const CAPS: &[(&str, &str)] = &[
    ("", "Caps Lock"),
    ("caps:none", "Off"),
    ("caps:escape", "Escape"),
    ("ctrl:nocaps", "Ctrl"),
    ("caps:swapescape", "Swap with Esc"),
];

/// One entry of the XKB layout list.
#[derive(Debug, Clone, PartialEq)]
pub struct LayoutInfo {
    pub layout: String,
    pub variant: String,
    pub name: String,
}

/// Layouts and variants from evdev.lst: "! layout" lines are "  code  Name",
/// "! variant" lines are "  variant  layout: Name".
pub fn parse_xkb_list(text: &str) -> Vec<LayoutInfo> {
    let mut list = Vec::new();
    let mut section = "";
    for line in text.lines() {
        if let Some(name) = line.strip_prefix("! ") {
            section = if name == "layout" {
                "layout"
            } else if name == "variant" {
                "variant"
            } else {
                ""
            };
            continue;
        }
        let line = line.trim();
        let Some((code, rest)) = line.split_once(char::is_whitespace) else {
            continue;
        };
        let rest = rest.trim();
        match section {
            "layout" => list.push(LayoutInfo {
                layout: code.into(),
                variant: String::new(),
                name: rest.into(),
            }),
            "variant" => {
                if let Some((layout, name)) = rest.split_once(": ") {
                    list.push(LayoutInfo {
                        layout: layout.into(),
                        variant: code.into(),
                        name: name.into(),
                    });
                }
            }
            _ => {}
        }
    }
    list
}

/// Entries whose name or code contains every word of the query.
pub fn find<'a>(catalog: &'a [LayoutInfo], query: &str) -> Vec<&'a LayoutInfo> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() {
        return Vec::new();
    }
    catalog
        .iter()
        .filter(|l| {
            let hay = format!("{} {} {}", l.name, l.layout, l.variant).to_lowercase();
            words.iter().all(|w| hay.contains(w))
        })
        .take(MAX_MATCHES)
        .collect()
}

#[derive(Default)]
pub struct State {
    settings: Option<Settings>,
    catalog: Vec<LayoutInfo>,
    filter: String,
    test: String,
    /// Repeat slider being dragged, shown but not applied yet.
    dragging: bool,
    /// Layout whose Remove was clicked once; a second click removes it.
    confirming: Option<usize>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Option<Settings>),
    Filter(String),
    Add(usize),
    Remove(usize),
    MoveUp(usize),
    Switch(&'static str),
    Caps(&'static str),
    Numlock(bool),
    Delay(i64),
    Rate(i64),
    CommitRepeat,
    Test(String),
    Applied(Result<(), String>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Pick(&'static str, &'static str);

impl fmt::Display for Pick {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.1)
    }
}

impl State {
    fn name_of(&self, layout: &str, variant: &str) -> String {
        self.catalog
            .iter()
            .find(|l| l.layout == layout && l.variant == variant)
            .map(|l| l.name.clone())
            .unwrap_or_else(|| {
                if variant.is_empty() {
                    layout.to_string()
                } else {
                    format!("{layout} ({variant})")
                }
            })
    }

    /// Change the keyboard settings and apply them.
    fn change(&mut self, edit: impl FnOnce(&mut Keyboard)) -> Task<Msg> {
        let Some(settings) = &mut self.settings else {
            return Task::none();
        };
        edit(&mut settings.keyboard);
        let keyboard = settings.keyboard.clone();
        Task::perform(crate::hypr::update(move |s| s.keyboard = keyboard), Msg::Applied)
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(msg, Msg::Remove(_) | Msg::Load | Msg::Loaded(_) | Msg::Applied(_)) {
            self.confirming = None;
        }
        match msg {
            Msg::Load => {
                if self.catalog.is_empty() {
                    self.catalog = parse_xkb_list(&std::fs::read_to_string(XKB_LIST).unwrap_or_default());
                }
                if self.settings.is_none() {
                    return Task::perform(system::spawn(Settings::load), Msg::Loaded);
                }
            }
            Msg::Loaded(Some(settings)) => self.settings = Some(settings),
            Msg::Loaded(None) => self.error = Some("Could not read the Hyprland settings".into()),
            Msg::Filter(text) => self.filter = text,
            Msg::Add(index) => {
                let matches = find(&self.catalog, &self.filter);
                if let Some(l) = matches.get(index).map(|l| (l.layout.clone(), l.variant.clone())) {
                    self.filter.clear();
                    return self.change(|k| {
                        if !k.layouts.contains(&l) {
                            k.layouts.push(l);
                        }
                    });
                }
            }
            Msg::Remove(i) if self.confirming != Some(i) => self.confirming = Some(i),
            Msg::Remove(i) => {
                self.confirming = None;
                return self.change(|k| {
                    if k.layouts.len() > 1 && i < k.layouts.len() {
                        k.layouts.remove(i);
                    }
                });
            }
            Msg::MoveUp(i) => {
                return self.change(|k| {
                    if i > 0 && i < k.layouts.len() {
                        k.layouts.swap(i - 1, i);
                    }
                });
            }
            Msg::Switch(option) => return self.change(|k| k.switch = option.to_string()),
            Msg::Caps(option) => return self.change(|k| k.caps = option.to_string()),
            Msg::Numlock(on) => return self.change(|k| k.numlock = on),
            Msg::Delay(ms) => {
                self.dragging = true;
                if let Some(s) = &mut self.settings {
                    s.keyboard.repeat_delay = ms;
                }
            }
            Msg::Rate(rate) => {
                self.dragging = true;
                if let Some(s) = &mut self.settings {
                    s.keyboard.repeat_rate = rate;
                }
            }
            Msg::CommitRepeat => {
                self.dragging = false;
                return self.change(|_| {});
            }
            Msg::Test(text) => self.test = text,
            Msg::Applied(result) => self.error = result.err(),
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(settings) = &self.settings else {
            return ui::section(body, "Layouts", vec![ui::note("Loading…")]);
        };
        let k = &settings.keyboard;
        body = ui::section(body, "Layouts", self.layout_rows(k));

        let switch = SWITCHES.iter().map(|(o, l)| Pick(o, l)).collect::<Vec<_>>();
        let current = switch.iter().find(|p| p.0 == k.switch).cloned();
        let caps = CAPS
            .iter()
            .map(|(o, l)| (*l, k.caps == *o, Some(Msg::Caps(o))))
            .collect::<Vec<_>>();
        body = ui::section(
            body,
            "Keys",
            vec![
                ui::item(
                    "󰌌",
                    "Switch layout with".into(),
                    "Cycles through the layouts above".into(),
                    vec![pick_list(switch, current, |p| Msg::Switch(p.0)).width(220).into()],
                ),
                ui::item(
                    "󰘲",
                    "Caps Lock key".into(),
                    "What the Caps Lock key does".into(),
                    vec![ui::choice(caps, Length::Fixed(220.0))],
                ),
                ui::item(
                    "󰎠",
                    "Num Lock on at start".into(),
                    "Turn Num Lock on when Hyprland starts".into(),
                    vec![toggler(k.numlock).on_toggle(Msg::Numlock).into()],
                ),
            ],
        );

        let delay = slider(150..=1000, k.repeat_delay.clamp(150, 1000) as i32, |v| {
            Msg::Delay(v as i64)
        })
        .step(10)
        .on_release(Msg::CommitRepeat);
        let rate = slider(5..=80, k.repeat_rate.clamp(5, 80) as i32, |v| Msg::Rate(v as i64))
            .step(1)
            .on_release(Msg::CommitRepeat);
        ui::section(
            body,
            "Key repeat",
            vec![
                slider_row(
                    "Delay",
                    "How long a key is held before it repeats",
                    delay.into(),
                    format!("{} ms", k.repeat_delay),
                ),
                slider_row(
                    "Speed",
                    "Repeats per second while held",
                    rate.into(),
                    format!("{} /s", k.repeat_rate),
                ),
                container(
                    text_input("Type here to try the repeat", &self.test)
                        .on_input(Msg::Test)
                        .padding([7, 10])
                        .style(style::field),
                )
                .padding([6, 14])
                .into(),
            ],
        )
    }

    fn layout_rows<'a>(&'a self, k: &'a Keyboard) -> Vec<Element<'a, Msg>> {
        let count = k.layouts.len();
        let mut rows: Vec<Element<'a, Msg>> = k
            .layouts
            .iter()
            .enumerate()
            .map(|(i, (layout, variant))| {
                let detail = if i == 0 {
                    format!("{layout} · default")
                } else {
                    layout.clone()
                };
                let remove = if self.confirming == Some(i) { "Sure?" } else { "Remove" };
                let buttons = ui::button_group(vec![
                    ("Up", (i > 0).then_some(Msg::MoveUp(i)), Action::Normal),
                    (remove, (count > 1).then_some(Msg::Remove(i)), Action::Danger),
                ]);
                ui::item("󰌌", self.name_of(layout, variant), detail, vec![buttons])
            })
            .collect();
        let matches = find(&self.catalog, &self.filter)
            .into_iter()
            .enumerate()
            .map(|(i, l)| ui::PickerMatch {
                label: l.name.clone(),
                font: None,
                detail: if l.variant.is_empty() {
                    l.layout.clone()
                } else {
                    format!("{} ({})", l.layout, l.variant)
                },
                on_pick: Msg::Add(i),
            })
            .collect();
        let picker = ui::search_picker(
            "Add a layout: type a language or country",
            &self.filter,
            Msg::Filter,
            matches,
        );
        rows.push(container(picker).padding([8, 14]).into());
        rows
    }
}

fn slider_row<'a>(label: &'a str, help: &'a str, bar: Element<'a, Msg>, value: String) -> Element<'a, Msg> {
    let line = row![
        column![
            text(label).size(14).color(style::FG),
            text(help).size(12).color(style::MUTED_DEEP)
        ]
        .spacing(2)
        .width(Length::Fill),
        container(bar).width(220),
        text(value).size(13).color(style::FG_MUTED).width(72),
    ]
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIST: &str = "! model\n  pc105  Generic 105-key PC\n\n! layout\n  us              English (US)\n  ee              Estonian\n\n! variant\n  nodeadkeys      ee: Estonian (no dead keys)\n  colemak         us: English (Colemak)\n\n! option\n  grp                  Switching to another layout\n";

    #[test]
    fn reads_layouts_and_variants() {
        let list = parse_xkb_list(LIST);
        assert_eq!(list.len(), 4);
        assert_eq!(
            list[1],
            LayoutInfo {
                layout: "ee".into(),
                variant: String::new(),
                name: "Estonian".into()
            }
        );
        assert_eq!(
            list[2],
            LayoutInfo {
                layout: "ee".into(),
                variant: "nodeadkeys".into(),
                name: "Estonian (no dead keys)".into()
            }
        );
    }

    #[test]
    fn finds_by_words() {
        let list = parse_xkb_list(LIST);
        let names: Vec<_> = find(&list, "estonian dead").iter().map(|l| l.variant.clone()).collect();
        assert_eq!(names, ["nodeadkeys"]);
        assert_eq!(find(&list, "colemak")[0].layout, "us");
        assert!(find(&list, "").is_empty());
    }
}
