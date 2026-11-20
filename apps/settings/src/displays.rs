//! Displays panel: every monitor with its mode, scale, rotation and
//! position, from `hyprctl monitors -j`. A change is applied at once
//! (`hyprctl eval hl.monitor(...)`), then asks to be kept: unless Keep is
//! pressed within REVERT_AFTER seconds the previous setup comes back, so a
//! mode without a picture undoes itself. A kept setup is saved to
//! settings.json and settings.lua (hypr.rs), so it holds after a restart.

use iced::widget::text_input;
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::hypr::{self, MonitorSetup};
use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

/// Seconds a changed setup waits for Keep.
pub const REVERT_AFTER: u32 = 15;

const SCALES: &[f64] = &[1.0, 1.25, 1.5, 1.75, 2.0];
const ROTATIONS: &[(i64, &str)] = &[(0, "Normal"), (1, "90°"), (2, "180°"), (3, "270°")];

#[derive(Debug, Clone, PartialEq)]
pub struct Monitor {
    pub name: String,
    pub description: String,
    pub setup: MonitorSetup,
    /// (mode as hl.monitor takes it, "1920x1200@60.00"; its label), the
    /// mode in use first when the list lacks it.
    pub modes: Vec<(String, String)>,
}

/// `hyprctl monitors -j`.
pub fn parse_monitors(json: &str) -> Result<Vec<Monitor>, String> {
    let list: serde_json::Value = serde_json::from_str(json).map_err(|e| format!("unexpected hyprctl output: {e}"))?;
    Ok(list
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| {
            let name = m["name"].as_str()?.to_string();
            let mode = format!(
                "{}x{}@{:.2}",
                m["width"].as_i64()?,
                m["height"].as_i64()?,
                m["refreshRate"].as_f64()?
            );
            let mut modes: Vec<(String, String)> = m["availableModes"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|v| v.as_str())
                .map(|s| {
                    let md = s.trim_end_matches("Hz").to_string();
                    let label = mode_label(&md);
                    (md, label)
                })
                .collect();
            if !modes.iter().any(|(_, l)| *l == mode_label(&mode)) {
                modes.insert(0, (mode.clone(), mode_label(&mode)));
            }
            Some(Monitor {
                description: m["description"].as_str().unwrap_or_default().to_string(),
                setup: MonitorSetup {
                    output: name.clone(),
                    mode,
                    position: format!("{}x{}", m["x"].as_i64()?, m["y"].as_i64()?),
                    scale: m["scale"].as_f64()?,
                    transform: m["transform"].as_i64()?,
                },
                modes,
                name,
            })
        })
        .collect())
}

/// "1920x1200@60.00" as "1920 × 1200, 60 Hz".
pub fn mode_label(mode: &str) -> String {
    let (size, rate) = mode.split_once('@').unwrap_or((mode, ""));
    let size = size.replace('x', " × ");
    match rate.parse::<f64>() {
        Ok(r) => format!("{size}, {} Hz", (r * 100.0).round() / 100.0),
        Err(_) => size,
    }
}

fn read() -> Result<Vec<Monitor>, String> {
    parse_monitors(&system::run_blocking("hyprctl", &args(&["monitors", "-j"]), None)?)
}

fn night_script() -> String {
    crate::store::home()
        .join(".config/scripts/night.sh")
        .to_string_lossy()
        .into_owned()
}

/// `night.sh status`: on or off; None when it cannot say.
fn read_night() -> Option<bool> {
    let out = system::run_blocking("bash", &[night_script(), "status".into()], None).ok()?;
    match out.trim() {
        "on" => Some(true),
        "off" => Some(false),
        _ => None,
    }
}

fn apply(setup: MonitorSetup) -> Task<Msg> {
    let call = match setup.lua_call() {
        Ok(c) => c,
        Err(e) => return Task::done(Msg::Applied(Err(e))),
    };
    Task::perform(system::run("hyprctl", vec!["eval".into(), call], None), |r| {
        Msg::Applied(r.map(|_| ()))
    })
}

/// A change waiting for Keep.
#[derive(Debug, Clone)]
struct Pending {
    previous: MonitorSetup,
    new: MonitorSetup,
    left: u32,
}

#[derive(Default)]
pub struct State {
    monitors: Option<Result<Vec<Monitor>, String>>,
    pending: Option<Pending>,
    night: Option<bool>,
    position_draft: Option<(String, String)>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Result<Vec<Monitor>, String>),
    NightRead(Option<bool>),
    Night(bool),
    NightDone(Result<(), String>),
    Change(MonitorSetup),
    PositionText(String, String),
    SavePosition(String),
    Applied(Result<(), String>),
    Keep,
    Revert,
    Second,
    Saved(Result<(), String>),
}

impl State {
    /// A change is waiting for Keep: the app ticks every second.
    pub fn counting(&self) -> bool {
        self.pending.is_some()
    }

    fn current(&self, output: &str) -> Option<MonitorSetup> {
        match &self.monitors {
            Some(Ok(list)) => list.iter().find(|m| m.name == output).map(|m| m.setup.clone()),
            _ => None,
        }
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::batch([
                    Task::perform(system::spawn(read), |r| {
                        Msg::Loaded(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
                    }),
                    Task::perform(system::spawn(read_night), |r| Msg::NightRead(r.flatten())),
                ]);
            }
            Msg::NightRead(on) => self.night = on,
            Msg::Night(on) => {
                let list = vec![night_script(), if on { "on" } else { "off" }.into()];
                return Task::perform(system::run("bash", list, None), |r| Msg::NightDone(r.map(|_| ())));
            }
            Msg::NightDone(r) => {
                self.error = r.err().map(|e| format!("Night light not changed: {e}"));
                return Task::perform(system::spawn(read_night), |r| Msg::NightRead(r.flatten()));
            }
            Msg::Loaded(r) => {
                self.monitors = Some(r);
                self.busy = false;
            }
            Msg::Change(new) => {
                // A second change while one waits keeps the first previous.
                let previous = match &self.pending {
                    Some(p) => p.previous.clone(),
                    None => match self.current(&new.output) {
                        Some(c) => c,
                        None => return Task::none(),
                    },
                };
                if previous.output != new.output {
                    self.error = Some("Keep or undo the other display's change first".into());
                    return Task::none();
                }
                self.busy = true;
                self.error = None;
                self.pending = Some(Pending {
                    previous,
                    new: new.clone(),
                    left: REVERT_AFTER,
                });
                return apply(new);
            }
            Msg::PositionText(output, t) => self.position_draft = Some((output, t)),
            Msg::SavePosition(output) => {
                let Some((_, text)) = self.position_draft.take().filter(|(o, _)| *o == output) else {
                    return Task::none();
                };
                let parts: Vec<&str> = text
                    .split(|c: char| c == ',' || c == 'x' || c.is_whitespace())
                    .filter(|p| !p.is_empty())
                    .collect();
                let (Some(Ok(x)), Some(Ok(y)), 2) = (
                    parts.first().map(|p| p.parse::<i64>()),
                    parts.get(1).map(|p| p.parse::<i64>()),
                    parts.len(),
                ) else {
                    self.error = Some("A position is two whole numbers, like 1920 0".into());
                    return Task::none();
                };
                let Some(mut setup) = self.current(&output) else {
                    return Task::none();
                };
                setup.position = format!("{x}x{y}");
                return self.update(Msg::Change(setup));
            }
            Msg::Applied(r) => {
                self.busy = false;
                if let Err(e) = r {
                    self.error = Some(format!("Not changed: {e}"));
                    self.pending = None;
                }
                return self.update(Msg::Load);
            }
            Msg::Second => {
                if let Some(p) = &mut self.pending {
                    p.left = p.left.saturating_sub(1);
                    if p.left == 0 {
                        return self.update(Msg::Revert);
                    }
                }
            }
            Msg::Revert => {
                if let Some(p) = self.pending.take() {
                    self.busy = true;
                    return apply(p.previous);
                }
            }
            Msg::Keep => {
                if let Some(p) = self.pending.take() {
                    self.busy = true;
                    let new = p.new;
                    return Task::perform(
                        hypr::update(move |s| {
                            s.monitors.retain(|m| m.output != new.output);
                            s.monitors.push(new);
                        }),
                        Msg::Saved,
                    );
                }
            }
            Msg::Saved(r) => {
                self.busy = false;
                self.error = r
                    .err()
                    .map(|e| format!("Applied, but not saved for the next start: {e}"));
            }
        }
        Task::none()
    }

    /// The night light switch, for the Night light section.
    pub fn night_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(on) = self.night else { return Vec::new() };
        vec![ui::item(
            ico::MOON,
            "Night light".into(),
            "Warmer colours now; Super+Ctrl+N does the same".into(),
            vec![ui::switch(on, Some(Msg::Night))],
        )]
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let list = match &self.monitors {
            None => return vec![ui::note("Looking…")],
            Some(Err(e)) => return vec![ui::note(format!("Could not read the displays: {e}"))],
            Some(Ok(list)) => list,
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if let Some(p) = &self.pending {
            rows.push(ui::item(
                ico::CIRCLE_QUESTION_MARK,
                "Keep these display settings?".into(),
                format!("Going back in {} s", p.left),
                vec![ui::button_group(vec![
                    ("Go back", Some(Msg::Revert), Action::Normal),
                    ("Keep", Some(Msg::Keep), Action::Primary),
                ])],
            ));
        }
        let idle = !self.busy && self.pending.is_none();
        for m in list {
            rows.push(ui::item(ico::MONITOR, m.name.clone(), m.description.clone(), vec![]));
            rows.extend(
                self.monitor_rows(m, idle)
                    .into_iter()
                    .enumerate()
                    .map(|(i, r)| ui::branch(r, i == 3)),
            );
        }
        rows
    }

    fn monitor_rows<'a>(&'a self, m: &'a Monitor, idle: bool) -> Vec<Element<'a, Msg>> {
        let with = |edit: &dyn Fn(&mut MonitorSetup)| {
            let mut s = m.setup.clone();
            edit(&mut s);
            Msg::Change(s)
        };
        let current_label = mode_label(&m.setup.mode);
        let mode_items: Vec<(&str, bool, Option<Msg>)> = m
            .modes
            .iter()
            .map(|(md, label)| {
                (
                    label.as_str(),
                    *label == current_label,
                    idle.then(|| with(&|s: &mut MonitorSetup| s.mode = md.clone())),
                )
            })
            .collect();
        let scale_items: Vec<(&'static str, bool, Option<Msg>)> = SCALES
            .iter()
            .zip(["100%", "125%", "150%", "175%", "200%"])
            .map(|(sc, label)| {
                (
                    label,
                    (m.setup.scale - sc).abs() < 0.01,
                    idle.then(|| with(&|s: &mut MonitorSetup| s.scale = *sc)),
                )
            })
            .collect();
        let rotation_items: Vec<(&'static str, bool, Option<Msg>)> = ROTATIONS
            .iter()
            .map(|(t, label)| {
                (
                    *label,
                    m.setup.transform == *t,
                    idle.then(|| with(&|s: &mut MonitorSetup| s.transform = *t)),
                )
            })
            .collect();
        let shown = match &self.position_draft {
            Some((o, t)) if *o == m.name => t.clone(),
            _ => m.setup.position.replace('x', " "),
        };
        let name = m.name.clone();
        let position = text_input("0 0", &shown)
            .on_input(move |t| Msg::PositionText(name.clone(), t))
            .on_submit(Msg::SavePosition(m.name.clone()))
            .padding([6, 10])
            .width(Length::Fixed(140.0))
            .style(style::field);
        vec![
            ui::item(
                ico::SCAN,
                "Resolution".into(),
                String::new(),
                vec![ui::select(mode_items, Length::Fixed(240.0))],
            ),
            ui::item(
                ico::ZOOM_IN,
                "Scale".into(),
                String::new(),
                vec![ui::select(scale_items, Length::Fixed(240.0))],
            ),
            ui::item(
                ico::ROTATE_CW,
                "Rotation".into(),
                String::new(),
                vec![ui::select(rotation_items, Length::Fixed(240.0))],
            ),
            ui::item(
                ico::MOVE,
                "Position".into(),
                "In pixels; Enter to apply".into(),
                vec![position.into()],
            ),
        ]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_monitors() {
        let json = r#"[{"name":"eDP-1","description":"Panel","width":1920,"height":1200,"refreshRate":60.003,
            "x":0,"y":0,"scale":1.0,"transform":0,"availableModes":["1920x1200@60.00Hz","1920x1200@48.00Hz"]}]"#;
        let list = parse_monitors(json).unwrap();
        assert_eq!(list[0].setup.mode, "1920x1200@60.00");
        let modes: Vec<&str> = list[0].modes.iter().map(|(m, _)| m.as_str()).collect();
        assert_eq!(modes, ["1920x1200@60.00", "1920x1200@48.00"]);
        assert_eq!(list[0].setup.position, "0x0");
        assert_eq!(mode_label("1920x1200@60.00"), "1920 × 1200, 60 Hz");
        assert_eq!(mode_label("2560x1440@143.97"), "2560 × 1440, 143.97 Hz");
        assert!(parse_monitors("nope").is_err());
    }
}
