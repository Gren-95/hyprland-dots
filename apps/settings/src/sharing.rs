//! Sharing panel: what lets others reach this computer. Remote access
//! (WayVNC, its address, login and options behind Details in vnc.rs), remote
//! login over SSH (sshd, switched through systemctl, so polkit asks for the
//! password), and whether Tailscale connects this computer to the tailnet
//! (its controls stay on the Network panel).

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system::{self, args};
use crate::tailscale;
use crate::ui;

/// What the panel shows, read off the UI thread.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Probe {
    pub vnc_running: bool,
    /// sshd: None when it is not installed, else (enabled, running).
    pub ssh: Option<(bool, bool)>,
    /// None when Tailscale is not installed.
    pub tailscale: Option<tailscale::Status>,
    /// This computer's first IPv4 address on the local network.
    pub lan_ip: String,
}

/// `systemctl show -p LoadState,UnitFileState,ActiveState`: (enabled,
/// running), or None for a unit that does not exist.
pub fn parse_unit(out: &str) -> Option<(bool, bool)> {
    let get = |key: &str| {
        out.lines()
            .find_map(|l| l.strip_prefix(&format!("{key}=")))
            .unwrap_or_default()
    };
    (get("LoadState") == "loaded").then(|| (get("UnitFileState") == "enabled", get("ActiveState") == "active"))
}

/// `hostname -I`: the first IPv4 address.
pub fn first_ipv4(out: &str) -> String {
    out.split_whitespace()
        .find(|a| a.contains('.'))
        .unwrap_or_default()
        .to_string()
}

fn wayvnc_script() -> String {
    crate::store::home()
        .join(".config/scripts/wayvnc-toggle.sh")
        .to_string_lossy()
        .into_owned()
}

fn probe() -> Probe {
    let vnc_running = system::run_blocking("pgrep", &args(&["-x", "wayvnc"]), None).is_ok();
    let ssh = system::run_blocking(
        "systemctl",
        &args(&["show", "sshd.service", "-p", "LoadState,UnitFileState,ActiveState"]),
        None,
    )
    .ok()
    .and_then(|o| parse_unit(&o));
    let tailscale = system::run_blocking("tailscale", &args(&["status", "--json"]), None)
        .ok()
        .and_then(|o| tailscale::parse_status(&o));
    let lan_ip = first_ipv4(&system::run_blocking("hostname", &args(&["-I"]), None).unwrap_or_default());
    Probe {
        vnc_running,
        ssh,
        tailscale,
        lan_ip,
    }
}

#[derive(Default)]
pub struct State {
    probe: Option<Probe>,
    vnc_open: bool,
    vnc: crate::vnc::State,
    /// What is being switched, until the next probe shows it.
    busy: Option<&'static str>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Probe),
    /// The switch flips it (the toggle script starts or stops it).
    Vnc,
    ToggleVnc,
    VncDetails(crate::vnc::Msg),
    Ssh(bool),
    /// Handled by the app: open the Network panel.
    OpenNetwork,
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return Task::perform(system::spawn(probe), |p| Msg::Refreshed(p.unwrap_or_default())),
            Msg::Refreshed(p) => {
                self.probe = Some(p);
                self.busy = None;
            }
            Msg::Vnc => {
                self.busy = Some("vnc");
                return Task::perform(system::run("bash", vec![wayvnc_script()], None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::ToggleVnc => {
                self.vnc_open = !self.vnc_open;
                if self.vnc_open {
                    return self.vnc.update(crate::vnc::Msg::Load).map(Msg::VncDetails);
                }
            }
            Msg::VncDetails(m) => return self.vnc.update(m).map(Msg::VncDetails),
            Msg::Ssh(on) => {
                self.busy = Some("ssh");
                let verb = if on { "enable" } else { "disable" };
                // systemctl asks polkit, which shows the password prompt.
                let list = args(&[verb, "--now", "sshd.service"]);
                return Task::perform(system::run("systemctl", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::OpenNetwork => {}
            Msg::Done(r) => {
                self.error = r
                    .err()
                    .map(|_| "Not changed: the password was not given, or it did not start".into());
                // Remote access may have started or stopped: its address too.
                let vnc = if self.vnc_open {
                    self.vnc.update(crate::vnc::Msg::Load).map(Msg::VncDetails)
                } else {
                    Task::none()
                };
                return Task::batch([self.update(Msg::Refresh), vnc]);
            }
        }
        Task::none()
    }

    fn state_line(&self, key: &str, running: bool, what: String) -> String {
        if self.busy == Some(key) {
            "Switching…".into()
        } else if running {
            what
        } else {
            "Off".into()
        }
    }

    pub fn screen_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(p) = &self.probe else {
            return vec![ui::note("Looking…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let detail = self.state_line("vnc", p.vnc_running, format!("On · VNC on port {}", self.vnc.port()));
        rows.push(ui::item(
            ico::MONITOR_UP,
            "Remote access".into(),
            detail,
            vec![
                ui::disclosure(self.vnc_open, Msg::ToggleVnc),
                ui::switch(p.vnc_running, self.busy.is_none().then_some(|_| Msg::Vnc)),
            ],
        ));
        if self.vnc_open {
            let details: Vec<Element<'_, Msg>> = self.vnc.rows().into_iter().map(|r| r.map(Msg::VncDetails)).collect();
            let count = details.len();
            rows.extend(
                details
                    .into_iter()
                    .enumerate()
                    .map(|(i, d)| ui::branch(d, i + 1 == count)),
            );
        }
        rows
    }

    /// SSH, when sshd is installed.
    pub fn login_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(p) = &self.probe else { return Vec::new() };
        let Some((enabled, running)) = p.ssh else {
            return vec![ui::note("OpenSSH server is not installed")];
        };
        let user = std::env::var("USER").unwrap_or_default();
        let target = if p.lan_ip.is_empty() {
            "On".to_string()
        } else {
            format!("On · ssh {user}@{}", p.lan_ip)
        };
        let detail = self.state_line("ssh", running, target);
        vec![ui::item(
            ico::TERMINAL,
            "Remote login".into(),
            format!("{detail} · switching asks for your password"),
            vec![ui::switch(enabled || running, self.busy.is_none().then_some(Msg::Ssh))],
        )]
    }

    /// Whether Tailscale connects this computer; managed on Network.
    pub fn tailnet_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(p) = &self.probe else { return Vec::new() };
        let Some(ts) = &p.tailscale else { return Vec::new() };
        let detail = match ts.state.as_str() {
            "Running" => format!("Reachable as {} ({}) on {}", ts.name, ts.ip, ts.tailnet),
            "NeedsLogin" => "Not logged in".into(),
            "Stopped" => "Off: only the local network can reach this computer".into(),
            other => other.to_string(),
        };
        vec![ui::item(
            if ts.state == "Running" {
                ico::SHIELD_CHECK
            } else {
                ico::SHIELD
            },
            "Tailscale".into(),
            detail,
            vec![ui::action("Network settings", Some(Msg::OpenNetwork), Action::Normal)],
        )]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_ssh_unit() {
        assert_eq!(
            parse_unit("LoadState=loaded\nUnitFileState=disabled\nActiveState=inactive\n"),
            Some((false, false))
        );
        assert_eq!(
            parse_unit("LoadState=loaded\nUnitFileState=enabled\nActiveState=active\n"),
            Some((true, true))
        );
        assert_eq!(
            parse_unit("LoadState=not-found\nUnitFileState=\nActiveState=inactive\n"),
            None
        );
    }

    #[test]
    fn finds_the_lan_address() {
        assert_eq!(first_ipv4("192.168.1.20 100.64.0.3 fd7a::1 \n"), "192.168.1.20");
        assert_eq!(first_ipv4("fd7a::1"), "");
    }
}
