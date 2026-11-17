//! Network panel: Wi-Fi, wired devices and VPN connections through nmcli.

use iced::widget::{Column, text_input};
use iced::{Element, Task};

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub wifi_enabled: bool,
    pub networks: Vec<Wifi>,
    pub wired: Vec<Wired>,
    pub vpns: Vec<Vpn>,
    /// Names of saved Wi-Fi connections.
    pub saved: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Wifi {
    pub ssid: String,
    pub signal: u8,
    /// Empty for an open network.
    pub security: String,
    pub in_use: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Wired {
    pub device: String,
    pub state: String,
    pub connection: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Vpn {
    pub name: String,
    pub active: bool,
}

#[derive(Default)]
pub struct State {
    snapshot: Option<Snapshot>,
    /// What is being done right now, shown in place of its buttons.
    busy: Option<String>,
    /// Network whose password is being asked for.
    prompt: Option<String>,
    password: String,
    /// The hidden network form: name and password.
    hidden_ssid: String,
    hidden_password: String,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Snapshot, String>),
    SetWifi(bool),
    Rescan,
    Connect(String),
    Password(String),
    SubmitPassword,
    CancelPassword,
    Disconnect(String),
    Forget(String),
    SetVpn(String, bool),
    /// An action finished; refresh to show its effect.
    HiddenSsid(String),
    HiddenPassword(String),
    JoinHidden,
    Done(Result<(), String>),
}

/// Split one line of `nmcli -t` output: fields are separated by ':', and
/// ':' or '\' inside a field are escaped with '\'.
pub fn split_terse(line: &str) -> Vec<String> {
    let mut fields = vec![String::new()];
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => {
                if let Some(next) = chars.next() {
                    fields.last_mut().unwrap().push(next);
                }
            }
            ':' => fields.push(String::new()),
            _ => fields.last_mut().unwrap().push(c),
        }
    }
    fields
}

/// `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list`: one entry per
/// SSID (the strongest access point, connected if any is), hidden networks
/// left out, strongest first with the connected one on top.
pub fn parse_wifi(output: &str) -> Vec<Wifi> {
    let mut networks: Vec<Wifi> = Vec::new();
    for line in output.lines() {
        let f = split_terse(line);
        if f.len() < 4 || f[1].is_empty() {
            continue;
        }
        let security = if f[3] == "--" { String::new() } else { f[3].clone() };
        let wifi = Wifi {
            ssid: f[1].clone(),
            signal: f[2].parse().unwrap_or(0),
            security,
            in_use: f[0] == "*",
        };
        match networks.iter_mut().find(|n| n.ssid == wifi.ssid) {
            Some(known) => {
                known.in_use |= wifi.in_use;
                known.signal = known.signal.max(wifi.signal);
            }
            None => networks.push(wifi),
        }
    }
    networks.sort_by(|a, b| b.in_use.cmp(&a.in_use).then(b.signal.cmp(&a.signal)));
    networks
}

/// `nmcli -t -f NAME,TYPE,ACTIVE connection show`: saved Wi-Fi names and
/// VPN connections (OpenVPN and the like, and WireGuard).
pub fn parse_connections(output: &str) -> (Vec<String>, Vec<Vpn>) {
    let mut saved = Vec::new();
    let mut vpns = Vec::new();
    for line in output.lines() {
        let f = split_terse(line);
        if f.len() < 3 {
            continue;
        }
        match f[1].as_str() {
            "802-11-wireless" => saved.push(f[0].clone()),
            "vpn" | "wireguard" => vpns.push(Vpn {
                name: f[0].clone(),
                active: f[2] == "yes",
            }),
            _ => {}
        }
    }
    (saved, vpns)
}

/// `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status`: ethernet devices
/// NetworkManager manages (not Docker's veth pairs and the like).
pub fn parse_wired(output: &str) -> Vec<Wired> {
    output
        .lines()
        .map(split_terse)
        .filter(|f| f.len() >= 4 && f[1] == "ethernet" && f[2] != "unmanaged")
        .map(|f| Wired {
            device: f[0].clone(),
            state: f[2].clone(),
            connection: f[3].clone(),
        })
        .collect()
}

fn nmcli(list: &[&str]) -> Result<String, String> {
    system::run_blocking("nmcli", &args(list), None)
}

fn snapshot() -> Result<Snapshot, String> {
    let wifi_enabled = nmcli(&["-t", "-f", "WIFI", "radio"])?.trim() == "enabled";
    let networks = if wifi_enabled {
        parse_wifi(&nmcli(&[
            "-t",
            "-f",
            "IN-USE,SSID,SIGNAL,SECURITY",
            "device",
            "wifi",
            "list",
            "--rescan",
            "no",
        ])?)
    } else {
        Vec::new()
    };
    let (saved, vpns) = parse_connections(&nmcli(&["-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"])?);
    let wired = parse_wired(&nmcli(&[
        "-t",
        "-f",
        "DEVICE,TYPE,STATE,CONNECTION",
        "device",
        "status",
    ])?);
    Ok(Snapshot {
        wifi_enabled,
        networks,
        wired,
        vpns,
        saved,
    })
}

fn refresh() -> Task<Msg> {
    Task::perform(system::spawn(snapshot), |r| {
        Msg::Refreshed(r.unwrap_or_else(|| Err("nmcli stopped unexpectedly".into())))
    })
}

/// Run nmcli with `list`, then report Done.
fn act(list: Vec<String>, stdin: Option<String>) -> Task<Msg> {
    Task::perform(system::run("nmcli", list, stdin), |r| Msg::Done(r.map(|_| ())))
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return refresh(),
            Msg::Refreshed(Ok(snapshot)) => self.snapshot = Some(snapshot),
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::SetWifi(on) => {
                self.busy = Some("wifi".into());
                return act(args(&["radio", "wifi", if on { "on" } else { "off" }]), None);
            }
            Msg::Rescan => {
                self.busy = Some("rescan".into());
                return act(args(&["device", "wifi", "rescan"]), None);
            }
            Msg::Connect(ssid) => {
                let snapshot = self.snapshot.as_ref();
                let saved = snapshot.is_some_and(|s| s.saved.contains(&ssid));
                let open = snapshot
                    .and_then(|s| s.networks.iter().find(|n| n.ssid == ssid))
                    .is_some_and(|n| n.security.is_empty());
                if saved {
                    self.busy = Some(ssid.clone());
                    return act(vec!["connection".into(), "up".into(), "id".into(), ssid], None);
                }
                if open {
                    self.busy = Some(ssid.clone());
                    return act(vec!["device".into(), "wifi".into(), "connect".into(), ssid], None);
                }
                self.prompt = Some(ssid);
                self.password.clear();
            }
            Msg::Password(text) => self.password = text,
            Msg::CancelPassword => {
                self.prompt = None;
                self.password.clear();
            }
            Msg::SubmitPassword => {
                if let Some(ssid) = self.prompt.take() {
                    self.busy = Some(ssid.clone());
                    // --ask reads the password from stdin, so it never shows
                    // up in the process list.
                    let password = std::mem::take(&mut self.password);
                    let list = vec!["--ask".into(), "device".into(), "wifi".into(), "connect".into(), ssid];
                    return act(list, Some(format!("{password}\n")));
                }
            }
            Msg::Disconnect(name) => {
                self.busy = Some(name.clone());
                return act(vec!["connection".into(), "down".into(), "id".into(), name], None);
            }
            Msg::Forget(name) => {
                self.busy = Some(name.clone());
                return act(vec!["connection".into(), "delete".into(), "id".into(), name], None);
            }
            Msg::SetVpn(name, on) => {
                self.busy = Some(name.clone());
                let verb = if on { "up" } else { "down" };
                return act(vec!["connection".into(), verb.into(), "id".into(), name], None);
            }
            Msg::HiddenSsid(text) => self.hidden_ssid = text,
            Msg::HiddenPassword(text) => self.hidden_password = text,
            Msg::JoinHidden => {
                let ssid = self.hidden_ssid.trim().to_string();
                if ssid.is_empty() {
                    return Task::none();
                }
                self.busy = Some(ssid.clone());
                let password = std::mem::take(&mut self.hidden_password);
                self.hidden_ssid.clear();
                let mut list = args(&["device", "wifi", "connect"]);
                list.push(ssid);
                list.extend(args(&["hidden", "yes"]));
                if password.is_empty() {
                    return act(list, None);
                }
                // --ask reads the password from stdin, never the command line.
                list.insert(0, "--ask".into());
                return act(list, Some(format!("{password}\n")));
            }
            Msg::Done(result) => {
                self.busy = None;
                self.error = result.err();
                return refresh();
            }
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(snap) = &self.snapshot else {
            return ui::section(body, "Wi-Fi", vec![ui::note("Loading…")]);
        };
        let idle = self.busy.is_none();
        let toggle = iced::widget::toggler(snap.wifi_enabled).on_toggle_maybe(idle.then_some(Msg::SetWifi));
        let mut wifi = vec![ui::item(
            "󰖩",
            "Wi-Fi".into(),
            if snap.wifi_enabled { "On".into() } else { "Off".into() },
            vec![
                ui::action(
                    "Scan",
                    (idle && snap.wifi_enabled).then_some(Msg::Rescan),
                    Action::Normal,
                ),
                toggle.into(),
            ],
        )];
        if snap.wifi_enabled && snap.networks.is_empty() {
            wifi.push(ui::note("No networks found"));
        }
        for n in &snap.networks {
            wifi.push(self.network_row(n, snap.saved.contains(&n.ssid)));
            if self.prompt.as_deref() == Some(n.ssid.as_str()) {
                wifi.push(self.password_row());
            }
        }
        if snap.wifi_enabled {
            let join = (idle && !self.hidden_ssid.trim().is_empty()).then_some(Msg::JoinHidden);
            let fields = vec![
                text_input("Hidden network name", &self.hidden_ssid)
                    .on_input(Msg::HiddenSsid)
                    .on_submit(Msg::JoinHidden),
                text_input("Password (empty if open)", &self.hidden_password)
                    .secure(true)
                    .on_input(Msg::HiddenPassword)
                    .on_submit(Msg::JoinHidden),
            ];
            wifi.push(
                iced::widget::container(ui::fields_group(fields, vec![("Join", join, Action::Primary)]))
                    .padding([8, 14])
                    .into(),
            );
        }
        body = ui::section(body, "Wi-Fi", wifi);
        if !snap.wired.is_empty() {
            let rows = snap
                .wired
                .iter()
                .map(|w| {
                    let detail = if w.connection.is_empty() {
                        w.state.clone()
                    } else {
                        format!("{} · {}", w.connection, w.state)
                    };
                    ui::item("󰈀", w.device.clone(), detail, vec![])
                })
                .collect();
            body = ui::section(body, "Wired", rows);
        }
        if !snap.vpns.is_empty() {
            let rows = snap
                .vpns
                .iter()
                .map(|v| {
                    let name = v.name.clone();
                    let toggle = iced::widget::toggler(v.active)
                        .on_toggle_maybe(idle.then_some(move |on| Msg::SetVpn(name.clone(), on)));
                    let state = if self.busy.as_deref() == Some(v.name.as_str()) {
                        "Working…"
                    } else if v.active {
                        "Connected"
                    } else {
                        "Off"
                    };
                    ui::item("󰦝", v.name.clone(), state.into(), vec![toggle.into()])
                })
                .collect();
            body = ui::section(body, "VPN", rows);
        }
        body
    }

    fn network_row<'a>(&'a self, n: &'a Wifi, saved: bool) -> Element<'a, Msg> {
        let glyph = match n.signal {
            75.. => "󰤨",
            50..=74 => "󰤥",
            25..=49 => "󰤢",
            _ => "󰤟",
        };
        let mut detail = vec![format!("{}%", n.signal)];
        detail.push(if n.security.is_empty() {
            "Open".into()
        } else {
            format!("󰌾 {}", n.security)
        });
        if n.in_use {
            detail.insert(0, "Connected".into());
        } else if saved {
            detail.insert(0, "Saved".into());
        }
        let busy = self.busy.as_deref() == Some(n.ssid.as_str());
        let idle = self.busy.is_none();
        let controls: Vec<Element<'a, Msg>> = if busy {
            vec![ui::note("Working…")]
        } else {
            let mut buttons = Vec::new();
            if saved {
                buttons.push(("Forget", idle.then(|| Msg::Forget(n.ssid.clone())), Action::Danger));
            }
            buttons.push(if n.in_use {
                (
                    "Disconnect",
                    idle.then(|| Msg::Disconnect(n.ssid.clone())),
                    Action::Normal,
                )
            } else {
                ("Connect", idle.then(|| Msg::Connect(n.ssid.clone())), Action::Primary)
            });
            vec![ui::button_group(buttons)]
        };
        ui::item(glyph, n.ssid.clone(), detail.join(" · "), controls)
    }

    fn password_row(&self) -> Element<'_, Msg> {
        let field = text_input("Password", &self.password)
            .secure(true)
            .on_input(Msg::Password)
            .on_submit(Msg::SubmitPassword);
        let ok = (!self.password.is_empty()).then_some(Msg::SubmitPassword);
        let buttons = vec![
            ("Cancel", Some(Msg::CancelPassword), Action::Normal),
            ("Connect", ok, Action::Primary),
        ];
        iced::widget::container(ui::input_group(field, buttons))
            .padding([4, 14])
            .into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_escaped_terse_fields() {
        assert_eq!(split_terse(r"*:Cafe\: Free:70:WPA2"), ["*", "Cafe: Free", "70", "WPA2"]);
        assert_eq!(split_terse(r"a\\b:"), [r"a\b", ""]);
    }

    #[test]
    fn merges_access_points_and_sorts() {
        let out = " :TimeCapsule:99:WPA2:AE\\:9C\n:Tele2:52:WPA2:9A\n*:TimeCapsule:69:WPA2:B2\n ::49:WPA2:9E\n :Cafe:80:--:01\n";
        let nets = parse_wifi(out);
        let names: Vec<_> = nets.iter().map(|n| n.ssid.as_str()).collect();
        assert_eq!(names, ["TimeCapsule", "Cafe", "Tele2"]);
        assert!(nets[0].in_use);
        assert_eq!(nets[0].signal, 99);
        assert_eq!(nets[1].security, "");
    }

    #[test]
    fn finds_saved_wifi_and_vpns() {
        let out = "TimeCapsule:802-11-wireless:yes\ndocker0:bridge:yes\nwork:vpn:no\nwg0:wireguard:yes\niPhone :802-11-wireless:no\n";
        let (saved, vpns) = parse_connections(out);
        assert_eq!(saved, ["TimeCapsule", "iPhone "]);
        assert_eq!(
            vpns,
            [
                Vpn {
                    name: "work".into(),
                    active: false
                },
                Vpn {
                    name: "wg0".into(),
                    active: true
                }
            ]
        );
    }

    #[test]
    fn lists_ethernet_devices_only() {
        let out = "wlp0s20f3:wifi:connected:TimeCapsule\nenp3s0:ethernet:unavailable:\nveth1:ethernet:unmanaged:\ndocker0:bridge:connected:docker0\n";
        assert_eq!(
            parse_wired(out),
            [Wired {
                device: "enp3s0".into(),
                state: "unavailable".into(),
                connection: String::new()
            }]
        );
    }
}
