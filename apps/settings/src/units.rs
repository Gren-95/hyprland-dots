//! Systemd user services on the Services panel. Your own units (in
//! ~/.config/systemd/user, the dots' daemons among them) have a switch that
//! enables and starts, or disables and stops, them, and Restart. The
//! system's enabled user units are listed read-only in a collapsed list:
//! switching off PipeWire's session manager by accident is not worth a
//! switch. Units a timer starts (the Jellyfin sync) belong to Scheduled.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Unit {
    pub id: String,
    pub description: String,
    pub enabled: bool,
    pub running: bool,
    /// From ~/.config/systemd/user rather than the system.
    pub own: bool,
}

/// `systemctl --user show -p Id,Description,FragmentPath,ActiveState,
/// UnitFileState,TriggeredBy …`: blocks of key=value lines separated by a
/// blank line. Masked units, units a timer starts and units with no file are
/// left out; `home` tells your own units apart.
pub fn parse_show(out: &str, home: &str) -> Vec<Unit> {
    out.split("\n\n")
        .filter_map(|block| {
            let get = |key: &str| {
                block
                    .lines()
                    .find_map(|l| l.strip_prefix(&format!("{key}=")))
                    .unwrap_or_default()
                    .to_string()
            };
            let (state, path) = (get("UnitFileState"), get("FragmentPath"));
            if path.is_empty() || state == "masked" || !get("TriggeredBy").is_empty() {
                return None;
            }
            let own = path.starts_with(&format!("{home}/.config/systemd/user/"));
            // Your own units whatever their state; the system's only when on.
            if !own && state != "enabled" {
                return None;
            }
            let id = get("Id");
            Some(Unit {
                description: Some(get("Description"))
                    .filter(|d| !d.is_empty())
                    .unwrap_or_else(|| id.clone()),
                id,
                enabled: state == "enabled",
                running: get("ActiveState") == "active",
                own,
            })
        })
        .collect()
}

/// Whether `service` has a timer of the same name.
pub fn has_timer(service: &str, timers: &[&str]) -> bool {
    let stem = service.trim_end_matches(".service");
    timers.iter().any(|t| t.trim_end_matches(".timer") == stem)
}

fn load() -> Vec<Unit> {
    let files = system::run_blocking(
        "systemctl",
        &args(&[
            "--user",
            "list-unit-files",
            "--type=service",
            "--no-legend",
            "--no-pager",
        ]),
        None,
    )
    .unwrap_or_default();
    let timers = system::run_blocking(
        "systemctl",
        &args(&["--user", "list-unit-files", "--type=timer", "--no-legend", "--no-pager"]),
        None,
    )
    .unwrap_or_default();
    let timers: Vec<&str> = timers.lines().filter_map(|l| l.split_whitespace().next()).collect();
    // A service with a timer of its own name runs on a schedule (Scheduled
    // shows it), even while the timer is off and TriggeredBy is empty.
    let names: Vec<&str> = files
        .lines()
        .filter_map(|l| l.split_whitespace().next())
        .filter(|n| !n.contains('@'))
        .filter(|n| !has_timer(n, &timers))
        .collect();
    if names.is_empty() {
        return Vec::new();
    }
    let mut list = args(&[
        "--user",
        "show",
        "-p",
        "Id,Description,FragmentPath,ActiveState,UnitFileState,TriggeredBy",
    ]);
    list.extend(names.iter().map(|n| n.to_string()));
    let out = system::run_blocking("systemctl", &list, None).unwrap_or_default();
    let home = crate::store::home().to_string_lossy().into_owned();
    let mut units = parse_show(&out, &home);
    units.sort_by_key(|u| u.description.to_lowercase());
    units
}

#[derive(Default)]
pub struct State {
    units: Option<Vec<Unit>>,
    busy: Option<String>,
    system_open: bool,
    query: String,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Vec<Unit>),
    Switch(String, bool),
    Restart(String),
    ToggleSystem,
    Query(String),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |u| Msg::Loaded(u.unwrap_or_default())),
            Msg::Loaded(u) => {
                self.units = Some(u);
                self.busy = None;
            }
            Msg::Switch(id, on) => {
                self.busy = Some(id.clone());
                let verb = if on { "enable" } else { "disable" };
                let list = vec!["--user".into(), verb.into(), "--now".into(), id];
                return Task::perform(system::run("systemctl", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::Restart(id) => {
                self.busy = Some(id.clone());
                let list = vec!["--user".into(), "restart".into(), id];
                return Task::perform(system::run("systemctl", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::ToggleSystem => {
                self.system_open = !self.system_open;
                self.query.clear();
            }
            Msg::Query(q) => self.query = q,
            Msg::Done(r) => {
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    /// Your own units, a switch and Restart each.
    pub fn own_rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let Some(units) = &self.units else {
            return vec![ui::note("Looking…")];
        };
        for u in units.iter().filter(|u| u.own) {
            let busy = self.busy.as_deref() == Some(u.id.as_str());
            let state = match (busy, u.running) {
                (true, _) => "Working…",
                (_, true) => "Running",
                (_, false) => "Stopped",
            };
            let id = u.id.clone();
            let mut controls = Vec::new();
            if u.running {
                controls.push(ui::action(
                    "Restart",
                    (!busy).then(|| Msg::Restart(u.id.clone())),
                    Action::Normal,
                ));
            }
            controls.push(ui::switch(
                u.enabled,
                (!busy).then_some(move |on| Msg::Switch(id.clone(), on)),
            ));
            rows.push(ui::item(
                if u.running { ico::CIRCLE_CHECK } else { ico::CIRCLE },
                u.description.clone(),
                format!("{state} · {}", u.id),
                controls,
            ));
        }
        rows
    }

    /// The system's enabled user units, collapsed and read-only.
    pub fn system_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(units) = &self.units else { return Vec::new() };
        let system: Vec<&Unit> = units.iter().filter(|u| !u.own).collect();
        if system.is_empty() {
            return Vec::new();
        }
        let running = system.iter().filter(|u| u.running).count();
        let entries = system
            .iter()
            .filter(|u| ui::matches_query(&u.description, &self.query) || ui::matches_query(&u.id, &self.query))
            .map(|u| {
                let state = if u.running { "Running" } else { "Waiting until needed" };
                ui::item(
                    if u.running { ico::CIRCLE_CHECK } else { ico::CIRCLE },
                    u.description.clone(),
                    format!("{state} · {}", u.id),
                    vec![],
                )
            })
            .collect();
        ui::collapsed_list(
            ico::SERVER,
            "System services",
            format!(
                "{} enabled, {running} running; part of the system, shown only",
                system.len()
            ),
            self.system_open,
            Msg::ToggleSystem,
            &self.query,
            Msg::Query,
            entries,
            system.len(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sorts_own_and_system_units() {
        let out = "Id=battery-notify.service\nDescription=Low-battery notifications\nFragmentPath=/h/u/.config/systemd/user/battery-notify.service\nActiveState=active\nUnitFileState=enabled\nTriggeredBy=\n\n\
Id=jellyfin-sync.service\nDescription=Jellyfin sync\nFragmentPath=/h/u/.config/systemd/user/jellyfin-sync.service\nActiveState=inactive\nUnitFileState=static\nTriggeredBy=jellyfin-sync.timer\n\n\
Id=wireplumber.service\nDescription=Multimedia Service Session Manager\nFragmentPath=/usr/lib/systemd/user/wireplumber.service\nActiveState=active\nUnitFileState=enabled\nTriggeredBy=\n\n\
Id=foo.service\nDescription=Foo\nFragmentPath=/usr/lib/systemd/user/foo.service\nActiveState=inactive\nUnitFileState=disabled\nTriggeredBy=\n\n\
Id=swaync.service\nDescription=\nFragmentPath=/dev/null\nActiveState=inactive\nUnitFileState=masked\nTriggeredBy=\n";
        let units = parse_show(out, "/h/u");
        let ids: Vec<(&str, bool)> = units.iter().map(|u| (u.id.as_str(), u.own)).collect();
        assert_eq!(ids, [("battery-notify.service", true), ("wireplumber.service", false)]);
        assert!(units[0].enabled && units[0].running);
        assert!(has_timer("jellyfin-sync.service", &["jellyfin-sync.timer"]));
        assert!(!has_timer("battery-notify.service", &["jellyfin-sync.timer"]));
    }
}
