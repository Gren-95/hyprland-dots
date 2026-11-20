//! Tailscale in the VPN list of the Network panel, when it is installed,
//! through the tailscale CLI (the user is the operator, so `tailscale set`
//! needs no root). At a glance one row: on or off and the tailnet. Its
//! Details hold the rest: this device's address to copy, the exit node,
//! options (Tailscale DNS, subnet routes, shields up, offering this device
//! as an exit node), and the devices of the tailnet (collapsed again) with
//! their address to copy and Taildrop: send a file to one, fetch files sent
//! here into ~/Downloads.

use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;
use serde_json::Value as Json;

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// Where `tailscale file get` puts files sent to this device.
const RECEIVED: &str = "Downloads";

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Peer {
    pub name: String,
    pub os: String,
    pub ip: String,
    pub online: bool,
    pub exit_option: bool,
    pub exit_node: bool,
    /// "2026-11-11", for devices that are offline.
    pub last_seen: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Status {
    /// "Running", "Stopped", "NeedsLogin"…
    pub state: String,
    pub tailnet: String,
    pub name: String,
    pub ip: String,
    pub peers: Vec<Peer>,
}

/// What `tailscale debug prefs` says about the options.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Prefs {
    pub dns: bool,
    pub routes: bool,
    pub shields_up: bool,
    pub offer_exit: bool,
    pub lan_access: bool,
}

pub fn parse_status(json: &str) -> Option<Status> {
    let v: Json = serde_json::from_str(json).ok()?;
    let s = |x: &Json| x.as_str().unwrap_or_default().to_string();
    let mut peers: Vec<Peer> = v["Peer"]
        .as_object()
        .into_iter()
        .flat_map(|m| m.values())
        .map(|p| Peer {
            name: s(&p["HostName"]),
            os: s(&p["OS"]),
            ip: p["TailscaleIPs"][0].as_str().unwrap_or_default().to_string(),
            online: p["Online"].as_bool().unwrap_or(false),
            exit_option: p["ExitNodeOption"].as_bool().unwrap_or(false),
            exit_node: p["ExitNode"].as_bool().unwrap_or(false),
            last_seen: p["LastSeen"]
                .as_str()
                .filter(|t| !t.starts_with("0001"))
                .map(|t| t.chars().take(10).collect())
                .unwrap_or_default(),
        })
        .collect();
    // Online first, then by name.
    peers.sort_by(|a, b| {
        b.online
            .cmp(&a.online)
            .then(a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Some(Status {
        state: s(&v["BackendState"]),
        tailnet: s(&v["CurrentTailnet"]["Name"]),
        name: s(&v["Self"]["HostName"]),
        ip: v["Self"]["TailscaleIPs"][0].as_str().unwrap_or_default().to_string(),
        peers,
    })
}

pub fn parse_prefs(json: &str) -> Option<Prefs> {
    let v: Json = serde_json::from_str(json).ok()?;
    let b = |k: &str| v[k].as_bool().unwrap_or(false);
    let routes: Vec<&str> = v["AdvertiseRoutes"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Json::as_str)
        .collect();
    Some(Prefs {
        dns: b("CorpDNS"),
        routes: b("RouteAll"),
        shields_up: b("ShieldsUp"),
        offer_exit: routes.contains(&"0.0.0.0/0"),
        lan_access: b("ExitNodeAllowLANAccess"),
    })
}

fn tailscale(list: &[&str]) -> Result<String, String> {
    system::run_blocking("tailscale", &args(list), None)
}

fn installed() -> bool {
    std::process::Command::new("tailscale")
        .arg("version")
        .output()
        .is_ok_and(|o| o.status.success())
}

/// None when Tailscale is not installed.
fn load() -> Option<(Status, Option<Prefs>)> {
    if !installed() {
        return None;
    }
    let status = parse_status(&tailscale(&["status", "--json"]).unwrap_or_default()).unwrap_or_default();
    let prefs = tailscale(&["debug", "prefs"]).ok().and_then(|p| parse_prefs(&p));
    Some((status, prefs))
}

/// An option as `tailscale set` takes it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Opt {
    Dns,
    Routes,
    ShieldsUp,
    OfferExit,
    LanAccess,
}

impl Opt {
    fn flag(self) -> &'static str {
        match self {
            Opt::Dns => "--accept-dns",
            Opt::Routes => "--accept-routes",
            Opt::ShieldsUp => "--shields-up",
            Opt::OfferExit => "--advertise-exit-node",
            Opt::LanAccess => "--exit-node-allow-lan-access",
        }
    }
}

#[derive(Default)]
pub struct State {
    /// None until read; Some(None) when Tailscale is not installed.
    data: Option<Option<(Status, Option<Prefs>)>>,
    /// Details are open.
    open: bool,
    /// The Options switch tree is open.
    options_open: bool,
    devices_open: bool,
    busy: bool,
    /// A short note after an action ("Copied", "Sent", "3 files in Downloads").
    note: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    /// wl-copy finished: the note to show, or why it failed.
    Copied(Result<String, String>),
    Refreshed(Option<(Status, Option<Prefs>)>),
    Power(bool),
    ExitNode(String),
    Set(Opt, bool),
    ToggleDetails,
    ToggleDevices,
    ToggleOptions,
    Copy(String),
    Send(String),
    SendPicked(String, Result<Option<String>, String>),
    Receive,
    Done(Result<String, String>),
}

fn run(list: Vec<String>) -> Task<Msg> {
    Task::perform(system::run("tailscale", list, None), Msg::Done)
}

impl State {
    pub fn installed(&self) -> bool {
        matches!(self.data, Some(Some(_)))
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Copied(Ok(note)) => self.note = Some(note),
            Msg::Copied(Err(e)) => self.error = Some(format!("Could not copy: {e}")),
            Msg::Refresh => return Task::perform(system::spawn(load), |d| Msg::Refreshed(d.flatten())),
            Msg::Refreshed(d) => self.data = Some(d),
            Msg::Power(on) => {
                self.busy = true;
                return run(args(&[if on { "up" } else { "down" }]));
            }
            Msg::ExitNode(ip) => {
                self.busy = true;
                return run(vec!["set".into(), format!("--exit-node={ip}")]);
            }
            Msg::Set(opt, on) => {
                self.busy = true;
                return run(vec!["set".into(), format!("{}={on}", opt.flag())]);
            }
            Msg::ToggleDetails => self.open = !self.open,
            Msg::ToggleDevices => self.devices_open = !self.devices_open,
            Msg::ToggleOptions => self.options_open = !self.options_open,
            Msg::Copy(text) => {
                return Task::perform(system::run("wl-copy", vec![text.clone()], None), move |r| {
                    Msg::Copied(r.map(|_| format!("Copied {text}")))
                });
            }
            Msg::Send(host) => {
                let list = args(&["--file-selection", "--title=Send a file with Taildrop"]);
                return Task::perform(system::pick(list), move |r| Msg::SendPicked(host.clone(), r));
            }
            Msg::SendPicked(_, Ok(None)) => {}
            Msg::SendPicked(_, Err(e)) => self.error = Some(e),
            Msg::SendPicked(host, Ok(Some(path))) => {
                self.busy = true;
                self.note = Some(format!("Sending to {host}…"));
                return Task::perform(
                    system::run(
                        "tailscale",
                        vec!["file".into(), "cp".into(), path, format!("{host}:")],
                        None,
                    ),
                    move |r| Msg::Done(r.map(|_| format!("Sent to {host}"))),
                );
            }
            Msg::Receive => {
                self.busy = true;
                let dir = crate::store::home().join(RECEIVED).to_string_lossy().into_owned();
                return Task::perform(
                    system::run(
                        "tailscale",
                        vec![
                            "file".into(),
                            "get".into(),
                            "--verbose".into(),
                            "--conflict=rename".into(),
                            dir,
                        ],
                        None,
                    ),
                    |r| Msg::Done(r.map(|out| received_note(&out))),
                );
            }
            Msg::Done(r) => {
                self.busy = false;
                match r {
                    Ok(note) if !note.trim().is_empty() && note.len() < 80 => self.note = Some(note.trim().into()),
                    Ok(_) => {}
                    Err(e) => self.error = Some(e),
                }
                return self.update(Msg::Refresh);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(Some((status, prefs))) = &self.data else {
            return vec![ui::note("Looking for Tailscale…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let running = status.state == "Running";
        let detail = match status.state.as_str() {
            "Running" => format!("Tailscale · Connected to {}", status.tailnet),
            "NeedsLogin" => "Tailscale · Not logged in: run tailscale login".into(),
            "Stopped" => "Tailscale · Off".into(),
            other => format!("Tailscale · {other}"),
        };
        let idle = !self.busy;
        let mut controls = Vec::new();
        if running {
            controls.push(ui::disclosure(self.open, Msg::ToggleDetails));
        }
        controls.push(ui::switch(running, idle.then_some(Msg::Power)));
        rows.push(ui::item(
            if running { ico::SHIELD_CHECK } else { ico::SHIELD },
            "Tailscale".into(),
            detail,
            controls,
        ));
        if !running || !self.open {
            return rows;
        }
        let mut details: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(note) = &self.note {
            details.push(ui::note(note.clone()));
        }
        details.push(ui::item(
            ico::NETWORK,
            format!("This device · {}", status.name),
            status.ip.clone(),
            vec![ui::action(
                "Copy",
                idle.then(|| Msg::Copy(status.ip.clone())),
                Action::Normal,
            )],
        ));
        // Exit node: none, or one of the devices that offer it.
        let mut items: Vec<(&str, bool, Option<Msg>)> = vec![(
            "None",
            !status.peers.iter().any(|p| p.exit_node),
            idle.then(|| Msg::ExitNode(String::new())),
        )];
        for p in status.peers.iter().filter(|p| p.exit_option) {
            items.push((
                p.name.as_str(),
                p.exit_node,
                (idle && p.online).then(|| Msg::ExitNode(p.ip.clone())),
            ));
        }
        details.push(ui::item(
            ico::GLOBE,
            "Exit node".into(),
            "Send all internet traffic through another device".into(),
            vec![ui::select(items, Length::Fixed(200.0))],
        ));
        if let Some(prefs) = prefs {
            let opt = |label: &'static str, on: bool, o: Opt| (label, on, idle.then_some(Msg::Set(o, !on)));
            let mut options = vec![
                opt("Tailscale DNS", prefs.dns, Opt::Dns),
                opt("Subnet routes", prefs.routes, Opt::Routes),
                opt("Shields up", prefs.shields_up, Opt::ShieldsUp),
                opt("Offer exit node", prefs.offer_exit, Opt::OfferExit),
            ];
            if status.peers.iter().any(|p| p.exit_node) {
                options.push(opt("LAN while exiting", prefs.lan_access, Opt::LanAccess));
            }
            let head = ui::switch_tree_head(&options, self.options_open, Msg::ToggleOptions);
            let row = ui::item(
                ico::SLIDERS_HORIZONTAL,
                "Options".into(),
                "DNS, routes, incoming connections, exit node".into(),
                vec![head],
            );
            details.push(if self.options_open {
                iced::widget::column![row].extend(ui::switch_rows(options)).into()
            } else {
                row
            });
        }
        let online = status.peers.iter().filter(|p| p.online).count();
        let devices_row = ui::item(
            ico::MONITOR_SMARTPHONE,
            "Devices".into(),
            format!("{online} of {} online", status.peers.len()),
            vec![
                ui::action("Receive files", idle.then_some(Msg::Receive), Action::Normal),
                ui::disclosure(self.devices_open, Msg::ToggleDevices),
            ],
        );
        // The devices hang one level deeper, under the Devices row.
        let mut devices = iced::widget::column![];
        if self.devices_open {
            let count = status.peers.len();
            for (i, p) in status.peers.iter().enumerate() {
                let mut detail = vec![p.os.clone(), p.ip.clone()];
                if !p.online && !p.last_seen.is_empty() {
                    detail.push(format!("seen {}", p.last_seen));
                }
                if p.exit_node {
                    detail.push("exit node".into());
                }
                let buttons = vec![
                    ("Copy", idle.then(|| Msg::Copy(p.ip.clone())), Action::Normal),
                    (
                        "Send file…",
                        (idle && p.online).then(|| Msg::Send(p.name.clone())),
                        Action::Normal,
                    ),
                ];
                let row = ui::item(
                    if p.online { ico::CIRCLE_CHECK } else { ico::CIRCLE },
                    p.name.clone(),
                    detail.join(" · "),
                    vec![ui::button_group(buttons)],
                );
                devices = devices.push(ui::branch(row, i + 1 == count));
            }
        }
        details.push(iced::widget::column![devices_row, devices].into());
        // The details hang under the Tailscale row as a tree.
        let count = details.len();
        rows.extend(
            details
                .into_iter()
                .enumerate()
                .map(|(i, d)| ui::branch(d, i + 1 == count)),
        );
        rows
    }
}

/// What `tailscale file get --verbose` moved ("moved 2/2 files"), as a
/// short note.
pub fn received_note(output: &str) -> String {
    let moved = output
        .lines()
        .find_map(|l| l.trim().strip_prefix("moved "))
        .and_then(|rest| rest.split('/').next()?.trim().parse::<usize>().ok())
        .unwrap_or(0);
    match moved {
        0 => "No files waiting".into(),
        1 => format!("1 file in {RECEIVED}"),
        n => format!("{n} files in {RECEIVED}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_status_and_prefs() {
        let json = r#"{"BackendState":"Running","CurrentTailnet":{"Name":"me.github"},
            "Self":{"HostName":"laptop","TailscaleIPs":["100.84.190.99","fd7a::1"]},
            "Peer":{"a":{"HostName":"nas","OS":"linux","Online":true,"ExitNodeOption":true,"ExitNode":false,"TailscaleIPs":["100.92.89.63"],"LastSeen":"0001-01-01T00:00:00Z"},
                    "b":{"HostName":"Phone","OS":"iOS","Online":false,"TailscaleIPs":["100.97.213.107"],"LastSeen":"2026-11-19T19:28:18.1Z"}}}"#;
        let s = parse_status(json).unwrap();
        assert_eq!(
            (s.state.as_str(), s.tailnet.as_str(), s.ip.as_str()),
            ("Running", "me.github", "100.84.190.99")
        );
        assert_eq!(s.peers[0].name, "nas");
        assert!(s.peers[0].exit_option && s.peers[0].last_seen.is_empty());
        assert_eq!(s.peers[1].last_seen, "2026-11-19");
        let prefs =
            parse_prefs(r#"{"CorpDNS":true,"RouteAll":true,"ShieldsUp":false,"AdvertiseRoutes":["0.0.0.0/0","::/0"]}"#)
                .unwrap();
        assert!(prefs.dns && prefs.routes && !prefs.shields_up && prefs.offer_exit && !prefs.lan_access);
        assert!(!parse_prefs(r#"{"AdvertiseRoutes":null}"#).unwrap().offer_exit);
    }

    #[test]
    fn notes_received_files() {
        assert_eq!(received_note(""), "No files waiting");
        assert_eq!(received_note("moved 0/0 files\n"), "No files waiting");
        assert_eq!(
            received_note("wrote Downloads/a.txt\nmoved 2/2 files\n"),
            "2 files in Downloads"
        );
    }
}
