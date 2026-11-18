//! Gaming panel: the game mode switch (scripts/gamemode.sh, whose state is
//! $XDG_RUNTIME_DIR/gamemode) and Hyprland's display options for games. What
//! game mode does is ordinary settings (schema.rs).

use iced::widget::toggler;
use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::hyprpage::{Row, Section};
use crate::system;
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

#[derive(Default)]
pub struct State {
    /// None until read.
    on: Option<bool>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(bool),
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
            Msg::Refresh => return Task::perform(system::spawn(read_state), |on| Msg::Refreshed(on.unwrap_or(false))),
            Msg::Refreshed(on) => self.on = Some(on),
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
        let switch = toggler(on).on_toggle_maybe((!self.busy && self.on.is_some()).then_some(Msg::Set));
        rows.push(ui::item(
            ico::GAMEPAD_2,
            "Game mode".into(),
            detail.into(),
            vec![switch.into()],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_state_file() {
        assert!(parse_state("on balanced\n"));
        assert!(!parse_state("off\n"));
        assert!(!parse_state(""));
    }
}
