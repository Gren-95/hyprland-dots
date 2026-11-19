//! A panel of plain Hyprland options (Mouse & Touchpad, later Windows):
//! declared as sections of rows, read with `hyprctl getoption` and saved
//! through hypr.rs, which writes only the options the user changed.

use std::collections::HashMap;

use iced::widget::{Column, column, container, row, slider, text};
use iced::{Alignment, Element, Length, Task};
use serde_json::{Value as Json, json};

use crate::hypr::{self, Settings};
use crate::style;
use crate::system;
use crate::ui;

pub struct Section {
    pub title: &'static str,
    pub rows: &'static [Row],
}

/// How a slider shows its value.
#[derive(Clone, Copy)]
pub enum Format {
    /// -1..1 as -100%..+100%.
    Signed,
    /// A multiplier, e.g. 1.5×.
    Times,
    /// 0..1 as 0%..100%.
    Percent,
    /// A whole number with a unit.
    Unit(&'static str),
}

pub enum Row {
    Toggle {
        option: &'static str,
        label: &'static str,
        help: &'static str,
    },
    /// A yes/no option shown as two named choices.
    Binary {
        option: &'static str,
        label: &'static str,
        help: &'static str,
        off: &'static str,
        on: &'static str,
    },
    /// A text option with fixed values: (value, label). An empty value
    /// means "not set" (Hyprland's default).
    Choice {
        option: &'static str,
        label: &'static str,
        help: &'static str,
        options: &'static [(&'static str, &'static str)],
    },
    /// A whole-number option with fixed values: (value, label).
    IntChoice {
        option: &'static str,
        label: &'static str,
        help: &'static str,
        options: &'static [(i64, &'static str)],
    },
    Slider {
        option: &'static str,
        label: &'static str,
        help: &'static str,
        min: f64,
        max: f64,
        step: f64,
        format: Format,
        /// Whole numbers (Hyprland int options).
        int: bool,
    },
}

impl Row {
    fn option(&self) -> &'static str {
        match self {
            Row::Toggle { option, .. }
            | Row::Binary { option, .. }
            | Row::Choice { option, .. }
            | Row::IntChoice { option, .. }
            | Row::Slider { option, .. } => option,
        }
    }
}

#[derive(Default)]
pub struct State {
    values: HashMap<&'static str, Json>,
    loaded: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(HashMap<&'static str, Json>),
    Set(&'static str, Json),
    /// A slider moved (option, value, whole numbers only); written on Commit.
    Preview(&'static str, f64, bool),
    Commit(&'static str),
    Applied(Result<(), String>),
}

fn options_of(sections: &'static [Section]) -> Vec<&'static str> {
    sections.iter().flat_map(|s| s.rows.iter()).map(Row::option).collect()
}

/// A number from an option value: a number, or the first number of a list
/// like "2 2 2 2" (gaps).
fn number(value: &Json) -> f64 {
    value
        .as_f64()
        .or_else(|| {
            value
                .as_str()
                .and_then(|s| s.split_whitespace().next())
                .and_then(|n| n.parse().ok())
        })
        .unwrap_or(0.0)
}

fn format_value(v: f64, format: Format) -> String {
    match format {
        Format::Signed => format!("{:+.0}%", v * 100.0),
        Format::Times => format!("{v:.1}×"),
        Format::Percent => format!("{:.0}%", v * 100.0),
        Format::Unit(unit) => format!("{v:.0} {unit}"),
    }
}

impl State {
    pub fn update(&mut self, msg: Msg, sections: &'static [Section]) -> Task<Msg> {
        match msg {
            Msg::Load => {
                let names = options_of(sections);
                let read = move || {
                    let settings = Settings::load();
                    names
                        .into_iter()
                        .filter_map(|n| hypr::option_value(&settings, n).map(|v| (n, v)))
                        .collect()
                };
                return Task::perform(system::spawn(read), |v| Msg::Loaded(v.unwrap_or_default()));
            }
            Msg::Loaded(values) => {
                self.values = values;
                self.loaded = true;
            }
            Msg::Preview(option, v, int) => {
                self.values
                    .insert(option, if int { json!(v.round() as i64) } else { json!(v) });
            }
            Msg::Commit(option) => {
                if let Some(v) = self.values.get(option).cloned() {
                    return self.save(option, v);
                }
            }
            Msg::Set(option, v) => {
                self.values.insert(option, v.clone());
                return self.save(option, v);
            }
            Msg::Applied(result) => self.error = result.err(),
        }
        Task::none()
    }

    fn save(&self, option: &'static str, value: Json) -> Task<Msg> {
        // An empty choice means "not set" (the device's own): Hyprland will
        // not take "" as a value, so the option is dropped from settings.lua
        // and Hyprland reloads its config to forget it.
        if value == Json::String(String::new()) {
            return Task::perform(
                async move {
                    hypr::update(move |s| {
                        s.options.remove(option);
                    })
                    .await?;
                    system::run("hyprctl", vec!["reload".into()], None).await.map(|_| ())
                },
                Msg::Applied,
            );
        }
        Task::perform(
            hypr::update(move |s| {
                s.options.insert(option.to_string(), value);
            }),
            Msg::Applied,
        )
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>, sections: &'static [Section]) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        if !self.loaded {
            return ui::section(
                body,
                sections.first().map_or("", |s| s.title),
                vec![ui::note("Loading…")],
            );
        }
        for section in sections {
            let rows = section.rows.iter().filter_map(|r| self.row(r)).collect();
            body = ui::section(body, section.title, rows);
        }
        body
    }

    /// A row, or nothing when this Hyprland does not have the option.
    fn row<'a>(&'a self, r: &'static Row) -> Option<Element<'a, Msg>> {
        let value = self.values.get(r.option())?;
        let (label, help, control): (&str, &str, Element<'a, Msg>) = match r {
            Row::Toggle { option, label, help } => {
                let on = value.as_bool().unwrap_or(false);
                (label, help, ui::switch(on, Some(move |b| Msg::Set(option, json!(b)))))
            }
            Row::Binary {
                option,
                label,
                help,
                off,
                on,
            } => {
                let is_on = value.as_bool().unwrap_or(false);
                let items = vec![
                    (*off, !is_on, Some(Msg::Set(option, json!(false)))),
                    (*on, is_on, Some(Msg::Set(option, json!(true)))),
                ];
                (label, help, ui::segmented(items, Length::Fixed(300.0)))
            }
            Row::Choice {
                option,
                label,
                help,
                options,
            } => {
                let current = value.as_str().unwrap_or("");
                let items = options
                    .iter()
                    .map(|(v, l)| (*l, *v == current, Some(Msg::Set(option, json!(v)))))
                    .collect();
                (label, help, ui::choice(items, Length::Fixed(300.0)))
            }
            Row::IntChoice {
                option,
                label,
                help,
                options,
            } => {
                let current = number(value) as i64;
                let items = options
                    .iter()
                    .map(|(v, l)| (*l, *v == current, Some(Msg::Set(option, json!(v)))))
                    .collect();
                (label, help, ui::choice(items, Length::Fixed(300.0)))
            }
            Row::Slider {
                option,
                label,
                help,
                min,
                max,
                step,
                format,
                int,
            } => {
                let v = value.as_f64().unwrap_or_else(|| number(value)).max(*min);
                let int = *int;
                let bar = slider(*min..=*max, v.clamp(*min, *max), move |x| Msg::Preview(option, x, int))
                    .step(*step)
                    .on_release(Msg::Commit(option));
                let shown = format_value(v, *format);
                let control = row![bar, text(shown).size(13).color(style::FG_MUTED).width(72)]
                    .spacing(12)
                    .width(300)
                    .align_y(Alignment::Center);
                (label, help, control.into())
            }
        };
        let info = column![
            text(label).size(14).color(style::FG),
            text(help).size(12).color(style::MUTED_DEEP)
        ]
        .spacing(2)
        .width(Length::Fill);
        Some(
            container(row![info, control].spacing(16).align_y(Alignment::Center))
                .padding([10, 14])
                .into(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_numbers_from_lists() {
        assert_eq!(number(&json!(3)), 3.0);
        assert_eq!(number(&json!("2 2 2 2")), 2.0);
        assert_eq!(number(&json!("x")), 0.0);
    }

    #[test]
    fn formats_values() {
        assert_eq!(format_value(0.25, Format::Signed), "+25%");
        assert_eq!(format_value(-0.5, Format::Signed), "-50%");
        assert_eq!(format_value(1.5, Format::Times), "1.5×");
        assert_eq!(format_value(500.0, Format::Unit("px")), "500 px");
    }
}
