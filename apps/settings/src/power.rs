//! Power & lock panel's own part: the battery (charge, health, cycles, charge
//! limit, power, temperature, model, age), refreshed while the panel is
//! open, and the charge limit switch when the laptop supports one. The
//! panel's settings sections follow it (app.rs with_settings).
//!
//! The charge limit is UPower's: EnableChargeThreshold makes UPower write the
//! battery's start and stop levels and keep them after a restart. polkit
//! asks for the password.

use iced::widget::Column;
use iced::{Task, widget::column};
use lucide_iced::bytes as ico;

use crate::infoview;
use crate::sysinfo::{self, Battery};
use crate::system::{self, args};
use crate::ui;

const UPOWER: &str = "org.freedesktop.UPower";
const DEVICE: &str = "org.freedesktop.UPower.Device";

/// UPower's charge limit: on, and the levels it charges between.
#[derive(Debug, Clone, PartialEq)]
pub struct Limit {
    pub path: String,
    pub enabled: bool,
    pub start: u32,
    pub end: u32,
}

/// `busctl get-property … ChargeThresholdSupported ChargeThresholdEnabled
/// ChargeStartThreshold ChargeEndThreshold`: "b true", "b false", "u 75",
/// "u 80". None when the battery has no limit.
pub fn parse_limit(path: &str, out: &str) -> Option<Limit> {
    let values: Vec<&str> = out
        .lines()
        .filter_map(|l| l.split_once(' ').map(|(_, v)| v.trim()))
        .collect();
    let [supported, enabled, start, end] = values.as_slice() else {
        return None;
    };
    (*supported == "true").then(|| Limit {
        path: path.to_string(),
        enabled: *enabled == "true",
        start: start.parse().unwrap_or(0),
        end: end.parse().unwrap_or(100),
    })
}

fn read_limit() -> Option<Limit> {
    let devices = system::run_blocking("upower", &args(&["-e"]), None).ok()?;
    let path = devices.lines().find(|l| l.contains("/battery_"))?.trim().to_string();
    let out = system::run_blocking(
        "busctl",
        &args(&[
            "get-property",
            UPOWER,
            &path,
            DEVICE,
            "ChargeThresholdSupported",
            "ChargeThresholdEnabled",
            "ChargeStartThreshold",
            "ChargeEndThreshold",
        ]),
        None,
    )
    .ok()?;
    parse_limit(&path, &out)
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub battery: Option<Battery>,
    pub limit: Option<Limit>,
}

fn read() -> Reading {
    Reading {
        battery: sysinfo::battery(),
        limit: read_limit(),
    }
}

#[derive(Default)]
pub struct State {
    /// None until read.
    reading: Option<Reading>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Reading),
    SetLimit(bool),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return Task::perform(system::spawn(read), |r| Msg::Refreshed(r.unwrap_or_default())),
            Msg::Refreshed(r) => self.reading = Some(r),
            Msg::SetLimit(on) => {
                let Some(limit) = self.reading.as_ref().and_then(|r| r.limit.clone()) else {
                    return Task::none();
                };
                self.busy = true;
                let list = args(&[
                    "call",
                    UPOWER,
                    &limit.path,
                    DEVICE,
                    "EnableChargeThreshold",
                    "b",
                    if on { "true" } else { "false" },
                ]);
                return Task::perform(system::run("busctl", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::Done(r) => {
                self.busy = false;
                self.error = r.err().map(|e| system::polkit_error(&e));
                return self.update(Msg::Refresh);
            }
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, body: Column<'a, Msg>) -> Column<'a, Msg> {
        let Some(reading) = &self.reading else {
            return body.push(column![]);
        };
        let mut body = match &reading.battery {
            Some(b) => infoview::battery(body, b),
            None => body,
        };
        if let Some(limit) = &reading.limit {
            let mut rows = Vec::new();
            if let Some(e) = &self.error {
                rows.push(ui::error(e));
            }
            rows.push(ui::item(
                ico::BATTERY_PLUS,
                "Limit charging".into(),
                format!(
                    "Stops at {} %, resumes below {} % · needs password",
                    limit.end, limit.start
                ),
                vec![ui::switch(limit.enabled, (!self.busy).then_some(Msg::SetLimit))],
            ));
            body = ui::section(body, "Battery health", rows);
        }
        body
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_charge_limit() {
        let p = "/org/freedesktop/UPower/devices/battery_BAT0";
        let l = parse_limit(p, "b true\nb false\nu 75\nu 80\n").unwrap();
        assert!(!l.enabled);
        assert_eq!((l.start, l.end), (75, 80));
        assert_eq!(parse_limit(p, "b false\nb false\nu 0\nu 100\n"), None);
        assert_eq!(parse_limit(p, "garbage"), None);
    }
}
