//! System services (root-level systemd units) on the Services panel. Two
//! collapsed lists: the services set differently from the distribution's
//! default (the ones someone chose), and every enabled one. A switch runs
//! `systemctl enable --now` or `disable --now`; systemd asks for the password
//! itself through polkit (the shell's prompt), so the app never runs as
//! root. Services the desktop cannot work without are shown without one.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::system::{self, args};
use crate::ui;

/// Units that keep the system or this desktop alive: listed, never switched
/// from here (a prefix match, so systemd-* covers its family).
const CORE: &[&str] = &[
    "dbus",
    "systemd-",
    "gdm",
    "getty@",
    "NetworkManager",
    "accounts-daemon",
    "polkit",
    "udisks2",
    "upower",
    "auditd",
    "selinux-",
    "lvm2-",
    "rpmdb-",
    "chronyd",
    "firewalld",
];

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Service {
    pub id: String,
    pub description: String,
    pub enabled: bool,
    /// The distribution's default (preset) is enabled.
    pub preset_enabled: bool,
    pub running: bool,
}

impl Service {
    pub fn changed(&self) -> bool {
        self.enabled != self.preset_enabled
    }

    pub fn core(&self) -> bool {
        CORE.iter().any(|c| self.id.starts_with(c))
    }
}

/// `systemctl list-unit-files --type=service --no-legend`: (unit, state,
/// preset) for units that are enabled or disabled (not static, masked…).
pub fn parse_files(out: &str) -> Vec<(String, bool, bool)> {
    out.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let (unit, state, preset) = (*f.first()?, *f.get(1)?, *f.get(2).unwrap_or(&""));
            matches!(state, "enabled" | "disabled").then(|| (unit.to_string(), state == "enabled", preset == "enabled"))
        })
        .collect()
}

/// `systemctl show -p Id,Description,ActiveState …`: id -> (description,
/// running).
pub fn parse_show(out: &str) -> Vec<(String, String, bool)> {
    out.split("\n\n")
        .filter_map(|b| {
            let get = |k: &str| {
                b.lines()
                    .find_map(|l| l.strip_prefix(&format!("{k}=")))
                    .unwrap_or_default()
            };
            let id = get("Id");
            (!id.is_empty()).then(|| {
                (
                    id.to_string(),
                    get("Description").to_string(),
                    get("ActiveState") == "active",
                )
            })
        })
        .collect()
}

fn load() -> Vec<Service> {
    let files = system::run_blocking(
        "systemctl",
        &args(&["list-unit-files", "--type=service", "--no-legend", "--no-pager"]),
        None,
    )
    .unwrap_or_default();
    // Enabled ones, and disabled ones that differ from the default.
    let wanted: Vec<(String, bool, bool)> = parse_files(&files)
        .into_iter()
        .filter(|(u, enabled, preset)| !u.contains("@.") && (*enabled || enabled != preset))
        .collect();
    if wanted.is_empty() {
        return Vec::new();
    }
    let mut list = args(&["show", "-p", "Id,Description,ActiveState"]);
    list.extend(wanted.iter().map(|(u, ..)| u.clone()));
    let shown = parse_show(&system::run_blocking("systemctl", &list, None).unwrap_or_default());
    let mut services: Vec<Service> = wanted
        .into_iter()
        .map(|(id, enabled, preset_enabled)| {
            let (description, running) = shown
                .iter()
                .find(|(i, ..)| *i == id)
                .map(|(_, d, r)| (d.clone(), *r))
                .unwrap_or_default();
            Service {
                description: if description.is_empty() {
                    id.clone()
                } else {
                    description
                },
                id,
                enabled,
                preset_enabled,
                running,
            }
        })
        .collect();
    services.sort_by_key(|s| s.description.to_lowercase());
    services
}

#[derive(Default)]
pub struct State {
    services: Option<Vec<Service>>,
    busy: Option<String>,
    changed_open: bool,
    all_open: bool,
    query: String,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Vec<Service>),
    Switch(String, bool),
    ToggleChanged,
    ToggleAll,
    Query(String),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |s| Msg::Loaded(s.unwrap_or_default())),
            Msg::Loaded(s) => {
                self.services = Some(s);
                self.busy = None;
            }
            Msg::Switch(id, on) => {
                self.busy = Some(id.clone());
                let verb = if on { "enable" } else { "disable" };
                // systemctl asks polkit, which shows the password prompt.
                let list = vec![verb.into(), "--now".into(), id];
                return Task::perform(system::run("systemctl", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::ToggleChanged => self.changed_open = !self.changed_open,
            Msg::ToggleAll => {
                self.all_open = !self.all_open;
                self.query.clear();
            }
            Msg::Query(q) => self.query = q,
            Msg::Done(r) => {
                self.error = r.err().map(|e| system::polkit_error(&e));
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    fn row<'a>(&'a self, s: &'a Service) -> Element<'a, Msg> {
        let busy = self.busy.as_deref() == Some(s.id.as_str());
        let state = match (busy, s.running) {
            (true, _) => "Working…",
            (_, true) => "Running",
            (_, false) => "Not running",
        };
        let default = match (s.changed(), s.preset_enabled) {
            (false, _) => "",
            (true, true) => " · on by default",
            (true, false) => " · off by default",
        };
        let detail = format!("{state} · {}{default}", s.id);
        let control = if s.core() {
            vec![ui::note("Left to the system")]
        } else {
            let id = s.id.clone();
            vec![ui::switch(
                s.enabled,
                (!busy).then_some(move |on| Msg::Switch(id.clone(), on)),
            )]
        };
        ui::item(
            if s.running { ico::CIRCLE_CHECK } else { ico::CIRCLE },
            s.description.clone(),
            detail,
            control,
        )
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(services) = &self.services else {
            return vec![ui::note("Looking…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let changed: Vec<&Service> = services.iter().filter(|s| s.changed()).collect();
        let on = changed.iter().filter(|s| s.enabled).count();
        rows.extend(ui::collapsed_list(
            ico::SLIDERS_HORIZONTAL,
            "Changed from the default",
            format!("{on} turned on, {} turned off", changed.len() - on),
            self.changed_open,
            Msg::ToggleChanged,
            "",
            |_| Msg::ToggleChanged,
            changed.iter().map(|s| self.row(s)).collect(),
            0,
        ));
        let enabled: Vec<&Service> = services.iter().filter(|s| s.enabled).collect();
        let running = enabled.iter().filter(|s| s.running).count();
        let entries = enabled
            .iter()
            .filter(|s| ui::matches_query(&s.description, &self.query) || ui::matches_query(&s.id, &self.query))
            .map(|s| self.row(s))
            .collect();
        rows.extend(ui::collapsed_list(
            ico::SERVER,
            "All enabled",
            format!(
                "{} enabled, {running} running; switching asks for your password",
                enabled.len()
            ),
            self.all_open,
            Msg::ToggleAll,
            &self.query,
            Msg::Query,
            entries,
            enabled.len(),
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_unit_files_and_states() {
        let files = "docker.service enabled disabled\nModemManager.service disabled enabled\nfoo.service static -\ngdm.service enabled enabled\n";
        assert_eq!(
            parse_files(files),
            [
                ("docker.service".to_string(), true, false),
                ("ModemManager.service".to_string(), false, true),
                ("gdm.service".to_string(), true, true),
            ]
        );
        let show = "Id=docker.service\nDescription=Docker Application Container Engine\nActiveState=active\n\nId=x.service\nDescription=\nActiveState=inactive\n";
        let s = parse_show(show);
        assert_eq!(
            s[0],
            (
                "docker.service".to_string(),
                "Docker Application Container Engine".to_string(),
                true
            )
        );
        assert!(!s[1].2);
    }

    #[test]
    fn knows_changed_and_core_services() {
        let s = |id: &str, enabled, preset_enabled| Service {
            id: id.into(),
            enabled,
            preset_enabled,
            ..Service::default()
        };
        assert!(s("docker.service", true, false).changed());
        assert!(!s("gdm.service", true, true).changed());
        assert!(s("NetworkManager.service", true, true).core());
        assert!(s("systemd-resolved.service", true, true).core());
        assert!(!s("teamviewerd.service", true, false).core());
    }
}
