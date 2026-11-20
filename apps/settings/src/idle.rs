//! Idle timings: the four "$name = seconds" variables at the top of
//! config/hypr/hypridle.conf. The Power & lock panel edits those lines in
//! place (the file is part of the dots, so the choice travels with them) and
//! restarts hypridle, which reads its config only at start.

use std::fs;
use std::path::PathBuf;

use iced::widget::{Column, column, container, row, slider, text};
use iced::{Alignment, Element, Length, Task};

use crate::style;
use crate::system::{self, args};
use crate::ui;

/// (variable, label, help, min minutes, max minutes, step minutes)
const TIMES: &[(&str, &str, &str, f64, f64, f64)] = &[
    (
        "dim_after",
        "Dim the screen",
        "Also turns the keyboard light off",
        0.5,
        30.0,
        0.5,
    ),
    ("lock_after", "Lock", "Lock the session", 1.0, 60.0, 1.0),
    (
        "screen_off_after",
        "Screen off",
        "Turn the display off",
        1.0,
        120.0,
        1.0,
    ),
    ("suspend_after", "Suspend", "Put the computer to sleep", 5.0, 240.0, 5.0),
];

fn path() -> PathBuf {
    crate::store::home().join(".config/hypr/hypridle.conf")
}

/// The seconds of a "$name = N" line.
pub fn read_var(text: &str, name: &str) -> Option<u64> {
    text.lines().find_map(|l| {
        let (key, value) = l.trim().split_once('=')?;
        (key.trim() == format!("${name}")).then(|| value.trim().parse().ok())?
    })
}

/// The text with the "$name = N" line set to `seconds`; None when the file
/// has no such line.
pub fn write_var(text: &str, name: &str, seconds: u64) -> Option<String> {
    let mut found = false;
    let out: Vec<String> = text
        .lines()
        .map(|l| match l.trim().split_once('=') {
            Some((key, _)) if key.trim() == format!("${name}") => {
                found = true;
                format!("${name} = {seconds}")
            }
            _ => l.to_string(),
        })
        .collect();
    found.then(|| out.join("\n") + "\n")
}

fn minutes_text(seconds: u64) -> String {
    let m = seconds as f64 / 60.0;
    if m.fract() == 0.0 {
        format!("{m:.0} min")
    } else {
        format!("{m:.1} min")
    }
}

#[derive(Default)]
pub struct State {
    /// Seconds per variable, in TIMES order; None until read.
    values: Option<Vec<u64>>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    /// A slider moved: (index into TIMES, minutes).
    Preview(usize, f64),
    Commit(usize),
    Done(Result<(), String>),
}

/// Write one variable, then restart hypridle so it takes the new time.
fn save(name: &'static str, seconds: u64) -> Result<(), String> {
    let target = path();
    let text = fs::read_to_string(&target).map_err(|e| format!("Could not read hypridle.conf: {e}"))?;
    let new = write_var(&text, name, seconds).ok_or_else(|| format!("hypridle.conf has no ${name} line"))?;
    let tmp = target.with_extension("conf.tmp");
    fs::write(&tmp, new)
        .and_then(|()| fs::rename(&tmp, &target))
        .map_err(|e| format!("Could not save hypridle.conf: {e}"))?;
    // Not running is fine: start it either way.
    let _ = system::run_blocking("pkill", &args(&["-x", "hypridle"]), None);
    system::run_blocking("hyprctl", &args(&["dispatch", "hl.dsp.exec_cmd(\"hypridle\")"]), None).map(|_| ())
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                let text = fs::read_to_string(path()).unwrap_or_default();
                let values: Option<Vec<u64>> = TIMES.iter().map(|(name, ..)| read_var(&text, name)).collect();
                match values {
                    Some(v) => self.values = Some(v),
                    None => self.error = Some("hypridle.conf has no idle time variables".into()),
                }
            }
            Msg::Preview(i, minutes) => {
                if let Some(v) = &mut self.values {
                    v[i] = (minutes * 60.0).round() as u64;
                }
            }
            Msg::Commit(i) => {
                if let Some(seconds) = self.values.as_ref().map(|v| v[i]) {
                    let name = TIMES[i].0;
                    return Task::perform(system::spawn(move || save(name, seconds)), |r| {
                        Msg::Done(r.unwrap_or_else(|| Err("saving stopped unexpectedly".into())))
                    });
                }
            }
            Msg::Done(result) => self.error = result.err(),
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(values) = &self.values else {
            return ui::section(body, "When idle", vec![ui::note("Loading…")]);
        };
        let rows = TIMES
            .iter()
            .enumerate()
            .map(|(i, (_, label, help, min, max, step))| {
                let minutes = values[i] as f64 / 60.0;
                let bar = slider(*min..=*max, minutes.clamp(*min, *max), move |m| Msg::Preview(i, m))
                    .step(*step)
                    .on_release(Msg::Commit(i));
                let info = column![
                    text(*label).size(14).color(style::FG),
                    text(*help).size(12).color(style::MUTED_DEEP)
                ]
                .spacing(2)
                .width(Length::Fill);
                let control = row![
                    bar,
                    text(minutes_text(values[i])).size(13).color(style::FG_MUTED).width(72)
                ]
                .spacing(12)
                .width(300)
                .align_y(Alignment::Center);
                container(row![info, control].spacing(16).align_y(Alignment::Center))
                    .padding([10, 14])
                    .into()
            })
            .collect::<Vec<Element<'a, Msg>>>();
        ui::section(body, "When idle", rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CONF: &str = "# top\n$dim_after = 150\n$lock_after = 300\n\nlistener {\n    timeout = $dim_after\n}\n";

    #[test]
    fn reads_and_writes_variables() {
        assert_eq!(read_var(CONF, "dim_after"), Some(150));
        assert_eq!(read_var(CONF, "suspend_after"), None);
        let new = write_var(CONF, "lock_after", 600).unwrap();
        assert_eq!(read_var(&new, "lock_after"), Some(600));
        assert!(new.contains("    timeout = $dim_after\n"));
        assert_eq!(write_var(CONF, "nope", 1), None);
    }

    #[test]
    fn shows_minutes() {
        assert_eq!(minutes_text(150), "2.5 min");
        assert_eq!(minutes_text(300), "5 min");
    }

    #[test]
    fn the_shipped_config_has_every_variable() {
        let conf =
            std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/../../config/hypr/hypridle.conf")).unwrap();
        for (name, ..) in TIMES {
            assert!(read_var(&conf, name).is_some(), "{name}");
        }
    }
}
