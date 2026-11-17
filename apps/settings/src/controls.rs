//! One setting as a row: its label and help text with the control that edits
//! it (toggle, slider, choice, text entry or a list of flags).

use std::collections::HashMap;
use std::fmt;

use iced::widget::{button, column, container, pick_list, row, slider, text, text_input, toggler, tooltip};
use iced::{Alignment, Element, Length};

use crate::app::Message;
use crate::reveal;
use crate::schema::{Control, Setting};
use crate::store::Value;
use crate::style;
use crate::ui;

/// Width of a control beside its label.
const CONTROL_WIDTH: f32 = 300.0;

/// A pick-list entry: shows the label, stores the value.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Choice {
    value: &'static str,
    label: &'static str,
}

impl fmt::Display for Choice {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.label)
    }
}

/// `draft` is the text being typed into an entry, not yet applied.
/// `stacked` puts the control under its label (narrow panels).
pub fn setting_row<'a>(
    s: &'static Setting,
    values: &HashMap<&'static str, Value>,
    draft: Option<&'a String>,
    fonts: &[&'static str],
    stacked: bool,
    highlighted: bool,
) -> Element<'a, Message> {
    let title: Element<'a, Message> = if is_default(s, values) {
        text(s.label).size(14).color(style::FG).into()
    } else {
        // Changed from the default: offer to put it back (UI.md).
        let reset = button(text("↺").size(13))
            .on_press(Message::Reset(s.file))
            .padding([0, 6])
            .style(style::action(style::Action::Normal));
        let reset = tooltip(
            reset,
            container(text("Reset to default").size(12))
                .padding([3, 8])
                .style(style::card),
            tooltip::Position::Top,
        );
        row![text(s.label).size(14).color(style::FG), reset]
            .spacing(8)
            .align_y(Alignment::Center)
            .into()
    };
    let label = column![title, text(s.help).size(12).color(style::MUTED_DEEP)]
        .spacing(2)
        .width(Length::Fill);
    let control = control(s, values, draft, fonts, stacked);
    let line: Element<'a, Message> = match s.control {
        // A toggle is small enough to stay beside its label.
        Control::Toggle => row![label, control].spacing(16).align_y(Alignment::Center).into(),
        // A multi-select group goes under its label; so does every control
        // when the panel is narrow.
        Control::Flags(_) | Control::Toggles(_) | Control::Font => column![label, control].spacing(8).into(),
        _ if stacked => column![label, control].spacing(10).into(),
        _ => row![label, control].spacing(16).align_y(Alignment::Center).into(),
    };
    // The id lets a search result scroll to this row (reveal.rs).
    container(line)
        .id(reveal::row_id(s.file))
        .padding([10, 14])
        .style(if highlighted {
            style::highlight
        } else {
            container::transparent
        })
        .into()
}

fn control<'a>(
    s: &'static Setting,
    values: &HashMap<&'static str, Value>,
    draft: Option<&'a String>,
    fonts: &[&'static str],
    stacked: bool,
) -> Element<'a, Message> {
    let file = s.file;
    // Under the label the control takes the full width; beside it, a fixed
    // one so the controls line up.
    let width = if stacked {
        Length::Fill
    } else {
        Length::Fixed(CONTROL_WIDTH)
    };
    let value = values.get(s.file).cloned().unwrap_or_else(|| s.default_value());
    match (&s.control, value) {
        (Control::Toggle, Value::Bool(on)) => toggler(on)
            .on_toggle(move |b| Message::Set(file, Value::Bool(b)))
            .into(),
        (Control::Number { min, max, step, unit }, Value::Int(n)) => {
            let shown = n.clamp(*min, *max) as i32;
            let bar = slider(*min as i32..=*max as i32, shown, move |v| {
                Message::Preview(file, Value::Int(v as i64))
            })
            .on_release(Message::Commit(file))
            .step(*step as i32);
            slider_row(bar.into(), format!("{n} {unit}").trim().to_string(), width)
        }
        (
            Control::Scale {
                min,
                max,
                step,
                percent,
            },
            Value::Real(n),
        ) => {
            let label = if *percent {
                format!("{}%", (n * 100.0).round())
            } else {
                format!("{n:.2}×")
            };
            let bar = slider(*min..=*max, n.clamp(*min, *max), move |v| {
                Message::Preview(file, Value::Real(v))
            })
            .on_release(Message::Commit(file))
            .step(*step);
            slider_row(bar.into(), label, width)
        }
        (Control::Choice(options), Value::Text(current)) if fits_segments(options) => {
            let items = options
                .iter()
                .map(|(value, label)| {
                    let msg = Message::Set(file, Value::Text(value.to_string()));
                    (*label, *value == current, Some(msg))
                })
                .collect();
            ui::segmented(items, width)
        }
        (Control::Choice(options), Value::Text(current)) => {
            let choices: Vec<Choice> = options.iter().map(|(value, label)| Choice { value, label }).collect();
            let selected = choices.iter().find(|c| c.value == current).cloned();
            pick_list(choices, selected, move |c| {
                Message::Set(file, Value::Text(c.value.to_string()))
            })
            .width(width)
            .into()
        }
        (Control::Entry { placeholder }, Value::Text(current)) => {
            let input = text_input(placeholder, draft.map(String::as_str).unwrap_or(&current))
                .on_input(move |t| Message::Draft(file, t))
                .on_submit(Message::Submit(file))
                .padding([7, 10])
                .style(style::field)
                .width(width);
            match draft {
                Some(d) if *d != current => column![input, text("Press Enter to apply").size(11).color(style::YELLOW)]
                    .spacing(4)
                    .into(),
                _ => input.into(),
            }
        }
        (Control::Flags(flags), Value::Json(map)) => {
            let items = flags
                .iter()
                .map(|(key, label)| {
                    let on = map.get(*key).and_then(|v| v.as_bool()).unwrap_or(false);
                    let mut next = map.as_object().cloned().unwrap_or_default();
                    next.insert(key.to_string(), serde_json::Value::Bool(!on));
                    (
                        *label,
                        on,
                        Some(Message::Set(file, Value::Json(serde_json::Value::Object(next)))),
                    )
                })
                .collect();
            ui::multi_select(items, Length::Fill)
        }
        (Control::Font, Value::Text(current)) => {
            let matches = crate::fonts::find(fonts, draft.map(String::as_str).unwrap_or(""))
                .into_iter()
                .map(|name| ui::PickerMatch {
                    label: name.to_string(),
                    font: Some(iced::Font::with_name(name)),
                    detail: if name == current {
                        "In use".into()
                    } else {
                        String::new()
                    },
                    on_pick: Message::Set(file, Value::Text(name.to_string())),
                })
                .collect();
            // The current font, drawn in itself when it is installed.
            let mut shown = text(current.clone()).size(15).color(style::FG);
            if let Some(name) = fonts.iter().find(|f| **f == current) {
                shown = shown.font(iced::Font::with_name(name));
            }
            column![
                shown,
                ui::search_picker(
                    "Search installed fonts",
                    draft.map(String::as_str).unwrap_or(""),
                    move |t| Message::Draft(file, t),
                    matches
                ),
            ]
            .spacing(8)
            .into()
        }
        (Control::NumberChoice(options), Value::Int(current)) => {
            let items = options
                .iter()
                .map(|(n, label)| (*label, *n == current, Some(Message::Set(file, Value::Int(*n)))))
                .collect();
            ui::choice(items, width)
        }
        (Control::Toggles(toggles), _) => {
            let items = toggles
                .iter()
                .map(|t| {
                    let on = matches!(values.get(t.file), Some(Value::Bool(true)))
                        || (values.get(t.file).is_none() && t.default);
                    (t.label, on, Some(Message::Set(t.file, Value::Bool(!on))))
                })
                .collect();
            ui::multi_select(items, Length::Fill)
        }
        (Control::Pair { options, none, both }, Value::Text(current)) => {
            let on = pair_state(&current, options, both);
            let items = (0..2)
                .map(|i| {
                    let mut next = on;
                    next[i] = !next[i];
                    let stored = pair_value(next, options, none, both);
                    (
                        options[i].1,
                        on[i],
                        Some(Message::Set(file, Value::Text(stored.to_string()))),
                    )
                })
                .collect();
            ui::multi_select(items, width)
        }
        // Values are read with the setting's own type and defaults are tested
        // to match, so a mismatch is a schema bug.
        (control, value) => text(format!("{file}: {value:?} does not fit {}", control.name()))
            .color(style::RED)
            .into(),
    }
}

/// Which of a pair's two options the stored value turns on.
fn pair_state(value: &str, options: &[(&str, &str); 2], both: &str) -> [bool; 2] {
    if value == both {
        [true, true]
    } else {
        [value == options[0].0, value == options[1].0]
    }
}

/// The stored value for a pair's on/off state.
fn pair_value<'s>(on: [bool; 2], options: &[(&'s str, &str); 2], none: &'s str, both: &'s str) -> &'s str {
    match on {
        [true, true] => both,
        [true, false] => options[0].0,
        [false, true] => options[1].0,
        [false, false] => none,
    }
}

/// Whether every file of the setting holds its default.
pub fn is_default(s: &Setting, values: &HashMap<&'static str, Value>) -> bool {
    s.files()
        .into_iter()
        .all(|(file, _, default)| values.get(file).is_none_or(|v| *v == default))
}

/// Two options are a joined button group, more a dropdown (UI.md).
fn fits_segments(options: &[(&str, &str)]) -> bool {
    options.len() == 2
}

/// A slider with its value written beside it.
fn slider_row<'a>(bar: Element<'a, Message>, value: String, width: Length) -> Element<'a, Message> {
    row![bar, text(value).size(13).color(style::FG_MUTED).width(72)]
        .spacing(12)
        .width(width)
        .align_y(Alignment::Center)
        .into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pair_maps_both_ways() {
        let options = [("output", "System sound"), ("input", "Microphone")];
        for (value, on) in [
            ("none", [false, false]),
            ("output", [true, false]),
            ("input", [false, true]),
            ("both", [true, true]),
        ] {
            assert_eq!(pair_state(value, &options, "both"), on);
            assert_eq!(pair_value(on, &options, "none", "both"), value);
        }
        assert_eq!(pair_state("junk", &options, "both"), [false, false]);
    }

    #[test]
    fn knows_when_a_setting_is_at_its_default() {
        let s = crate::schema::all_settings().find(|s| s.file == "bar-height").unwrap();
        let mut values = HashMap::new();
        assert!(is_default(s, &values));
        values.insert("bar-height", Value::Int(36));
        assert!(is_default(s, &values));
        values.insert("bar-height", Value::Int(40));
        assert!(!is_default(s, &values));
        let group = crate::schema::all_settings()
            .find(|s| s.file == "sysmon-show-cpu")
            .unwrap();
        values.insert("sysmon-show-ram", Value::Bool(false));
        assert!(!is_default(group, &values));
    }

    #[test]
    fn only_two_options_become_segments() {
        assert!(fits_segments(&[("center", "Top centre"), ("right", "Top right")]));
        assert!(!fits_segments(&[("a", "A"), ("b", "B"), ("c", "C")]));
    }
}
