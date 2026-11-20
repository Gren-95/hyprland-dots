//! Gaming panel: the game mode switch (scripts/gamemode.sh, whose state is
//! $XDG_RUNTIME_DIR/gamemode), connected controllers with their battery
//! (joysticks in /proc/bus/input/devices, batteries from UPower) and
//! Hyprland's display options for games. What game mode does is ordinary
//! settings (schema.rs).

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::hyprpage::{Row, Section};
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// Hyprland options that matter in games.
pub const DISPLAY: &[Section] = &[Section {
    title: "Display",
    rows: &[
        Row::IntChoice {
            option: "misc:vrr",
            label: "Variable refresh rate",
            help: "Lets the screen follow the game's frame rate (VRR, FreeSync, G-Sync)",
            options: &[
                (0, "Off"),
                (1, "Always"),
                (2, "Fullscreen"),
                (3, "Fullscreen games and video"),
            ],
        },
        Row::Toggle {
            option: "general:allow_tearing",
            label: "Allow tearing",
            help: "Fullscreen games skip vsync for lower input lag; the desktop stays vsynced",
        },
        Row::IntChoice {
            option: "render:direct_scanout",
            label: "Direct scanout",
            help: "Fullscreen games go to the screen without compositing, for less lag",
            options: &[(0, "Off"), (1, "On"), (2, "Games only")],
        },
    ],
}];

/// A connected game controller.
#[derive(Debug, Clone, PartialEq)]
pub struct Controller {
    pub name: String,
    /// Battery percent, when the controller reports one.
    pub battery: Option<u32>,
    /// UPower's state: "charging", "discharging", "fully-charged"…
    pub state: String,
}

/// Names of the joysticks in /proc/bus/input/devices (a block whose
/// handlers include jsN), once each.
pub fn parse_joysticks(devices: &str) -> Vec<String> {
    let mut names: Vec<String> = Vec::new();
    for block in devices.split("\n\n") {
        let name = block
            .lines()
            .find_map(|l| l.strip_prefix("N: Name="))
            .map(|n| n.trim_matches('"').to_string());
        let js = block
            .lines()
            .find_map(|l| l.strip_prefix("H: Handlers="))
            .is_some_and(|h| h.split_whitespace().any(|w| w.starts_with("js")));
        if let Some(name) = name.filter(|n| js && !n.is_empty() && !names.contains(n)) {
            names.push(name);
        }
    }
    names
}

/// The gaming-input devices of `upower -d`: (model, percent, state).
pub fn parse_upower(dump: &str) -> Vec<(String, Option<u32>, String)> {
    dump.split("Device: ")
        .filter(|b| b.lines().any(|l| l.trim() == "gaming-input"))
        .map(|b| {
            let field = |key: &str| {
                b.lines()
                    .find_map(|l| l.trim().strip_prefix(key))
                    .map(|v| v.trim().trim_matches('\'').to_string())
                    .unwrap_or_default()
            };
            let percent = field("percentage:")
                .split(|c: char| !c.is_ascii_digit())
                .next()
                .and_then(|n| n.parse().ok());
            (field("model:"), percent, field("state:"))
        })
        .collect()
}

/// Joysticks with the battery UPower knows for them (matched by name), and
/// UPower's controllers that are not joysticks (some report only there).
pub fn controllers(joysticks: &[String], batteries: &[(String, Option<u32>, String)]) -> Vec<Controller> {
    let matches = |js: &str, model: &str| !model.is_empty() && (js.contains(model) || model.contains(js));
    let mut list: Vec<Controller> = joysticks
        .iter()
        .map(|name| {
            let battery = batteries.iter().find(|(m, ..)| matches(name, m));
            Controller {
                name: name.clone(),
                battery: battery.and_then(|b| b.1),
                state: battery.map(|b| b.2.clone()).unwrap_or_default(),
            }
        })
        .collect();
    for (model, percent, state) in batteries {
        if !joysticks.iter().any(|j| matches(j, model)) {
            let name = if model.is_empty() {
                "Controller".to_string()
            } else {
                model.clone()
            };
            list.push(Controller {
                name,
                battery: *percent,
                state: state.clone(),
            });
        }
    }
    list
}

fn read_controllers() -> Vec<Controller> {
    let devices = std::fs::read_to_string("/proc/bus/input/devices").unwrap_or_default();
    let dump = system::run_blocking("upower", &args(&["-d"]), None).unwrap_or_default();
    controllers(&parse_joysticks(&devices), &parse_upower(&dump))
}

#[derive(Default)]
pub struct State {
    /// None until read.
    on: Option<bool>,
    controllers: Vec<Controller>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(bool, Vec<Controller>),
    /// Show the Bluetooth panel to connect a controller (app.rs handles it).
    OpenBluetooth,
    Set(bool),
    Done(Result<(), String>),
}

/// The first word of the state file: "on" or "off".
pub fn parse_state(text: &str) -> bool {
    text.split_whitespace().next() == Some("on")
}

fn read_state() -> bool {
    let dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_default();
    parse_state(&std::fs::read_to_string(format!("{dir}/gamemode")).unwrap_or_default())
}

fn script() -> String {
    crate::store::home()
        .join(".config/scripts/gamemode.sh")
        .to_string_lossy()
        .into_owned()
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => {
                return Task::perform(system::spawn(|| (read_state(), read_controllers())), |r| {
                    let (on, list) = r.unwrap_or_default();
                    Msg::Refreshed(on, list)
                });
            }
            Msg::Refreshed(on, list) => {
                self.on = Some(on);
                self.controllers = list;
            }
            Msg::OpenBluetooth => {}
            Msg::Set(on) => {
                self.busy = true;
                let arg = if on { "on" } else { "off" };
                return Task::perform(system::run("bash", vec![script(), arg.into()], None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::Done(r) => {
                self.busy = false;
                self.error = r.err();
                return self.update(Msg::Refresh);
            }
        }
        Task::none()
    }

    /// One row per controller, then the button to connect one.
    pub fn controller_rows(&self) -> Vec<Element<'_, Msg>> {
        let pads: Vec<Element<'_, Msg>> = self
            .controllers
            .iter()
            .map(|c| {
                let detail = match (c.battery, c.state.as_str()) {
                    (Some(p), "charging") => format!("{p} % · charging"),
                    (Some(p), _) => format!("{p} %"),
                    (None, _) => "Connected".into(),
                };
                let glyph = match c.battery {
                    Some(0..=20) => ico::BATTERY_LOW,
                    _ => ico::GAMEPAD_2,
                };
                ui::item(glyph, c.name.clone(), detail, vec![])
            })
            .collect();
        // One row at a glance; connected controllers hang under it.
        let summary = match pads.len() {
            0 => "None connected".to_string(),
            1 => "1 connected".to_string(),
            n => format!("{n} connected"),
        };
        let mut rows = vec![ui::item(
            ico::GAMEPAD_2,
            "Controllers".into(),
            summary,
            vec![ui::icon_action(
                ico::ARROW_UP_RIGHT,
                "Bluetooth settings",
                Some(Msg::OpenBluetooth),
                Action::Normal,
            )],
        )];
        let count = pads.len();
        rows.extend(pads.into_iter().enumerate().map(|(i, p)| ui::branch(p, i + 1 == count)));
        rows
    }

    /// The game mode row.
    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let on = self.on.unwrap_or(false);
        let detail = match (self.busy, self.on) {
            (true, _) => "Switching…",
            (_, None) => "",
            (_, Some(true)) => "On: the settings below are in effect",
            (_, Some(false)) => "Off",
        };
        let switch = ui::switch(on, (!self.busy && self.on.is_some()).then_some(Msg::Set));
        rows.push(ui::item(
            ico::GAMEPAD_2,
            "Game mode".into(),
            detail.into(),
            vec![switch],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_controllers_and_their_battery() {
        let devices = "I: Bus=0003\nN: Name=\"AT Translated Set 2 keyboard\"\nH: Handlers=sysrq kbd event3\n\nI: Bus=0005\nN: Name=\"Xbox Wireless Controller\"\nH: Handlers=event20 js0\n\nN: Name=\"Xbox Wireless Controller\"\nH: Handlers=event21 js1\n";
        let joysticks = parse_joysticks(devices);
        assert_eq!(joysticks, ["Xbox Wireless Controller"]);
        let dump = "Device: /org/freedesktop/UPower/devices/battery_BAT0\n  model: DELL\n  battery\n    percentage: 80%\n\nDevice: /org/freedesktop/UPower/devices/gaming_input_ps\n  model: Wireless Controller\n  gaming-input\n    state: charging\n    percentage: 55,5%\n";
        let batteries = parse_upower(dump);
        assert_eq!(
            batteries,
            [("Wireless Controller".to_string(), Some(55), "charging".to_string())]
        );
        let list = controllers(&joysticks, &batteries);
        assert_eq!(list.len(), 1);
        assert_eq!(list[0].battery, Some(55));
        let wired = controllers(&["8BitDo Pro 2".to_string()], &[]);
        assert_eq!(wired[0].battery, None);
    }

    #[test]
    fn reads_the_state_file() {
        assert!(parse_state("on balanced\n"));
        assert!(!parse_state("off\n"));
        assert!(!parse_state(""));
    }
}
