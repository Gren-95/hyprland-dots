//! Network panel: Wi-Fi, wired devices and VPN connections through nmcli.

use iced::widget::{Column, column, text_input};
use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub wifi_enabled: bool,
    pub networks: Vec<Wifi>,
    pub wired: Vec<Wired>,
    /// Names of saved Wi-Fi connections.
    pub saved: Vec<String>,
    /// Addresses, gateway and DNS of the connection the default route uses.
    /// Addresses, gateway and DNS of each connected Wi-Fi and wired device.
    pub details: Vec<crate::sysinfo::Network>,
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
    /// Network whose Forget was clicked once; a second click forgets it.
    confirming: Option<String>,
    /// Device whose details are shown.
    details_open: Option<String>,
    /// The hidden network dialog is open.
    hidden_open: bool,
    vpn: crate::vpn::State,
    tailscale: crate::tailscale::State,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Box<Snapshot>, String>),
    SetWifi(bool),
    Rescan,
    Connect(String),
    Password(String),
    SubmitPassword,
    CancelPassword,
    Disconnect(String),
    Forget(String),
    Vpn(crate::vpn::Msg),
    Tailscale(crate::tailscale::Msg),
    /// An action finished; refresh to show its effect.
    HiddenSsid(String),
    HiddenPassword(String),
    JoinHidden,
    Done(Result<(), String>),
    /// Show or hide a device's details.
    ToggleDetails(String),
    /// Open or close the hidden network dialog.
    HiddenDialog(bool),
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

/// `nmcli -t -f NAME,TYPE,ACTIVE connection show`: saved Wi-Fi names. VPNs
/// are vpn.rs's.
pub fn parse_connections(output: &str) -> Vec<String> {
    output
        .lines()
        .map(split_terse)
        .filter(|f| f.len() >= 3 && f[1] == "802-11-wireless")
        .map(|f| f[0].clone())
        .collect()
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

/// Wi-Fi and ethernet devices of `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION
/// device status` that are connected.
pub fn connected_devices(output: &str) -> Vec<String> {
    output
        .lines()
        .map(split_terse)
        .filter(|f| f.len() >= 3 && (f[1] == "wifi" || f[1] == "ethernet") && f[2] == "connected")
        .map(|f| f[0].clone())
        .collect()
}

/// The name field of the hidden network dialog, focused when it opens.
const HIDDEN_SSID_ID: &str = "hidden-ssid";

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
    let saved = parse_connections(&nmcli(&["-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"])?);
    let status = nmcli(&["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"])?;
    let wired = parse_wired(&status);
    let details = connected_devices(&status)
        .iter()
        .filter_map(|d| crate::sysinfo::device_network(d))
        .collect();
    Ok(Snapshot {
        wifi_enabled,
        networks,
        wired,
        saved,
        details,
    })
}

fn refresh() -> Task<Msg> {
    Task::perform(system::spawn(snapshot), |r| {
        Msg::Refreshed(
            r.unwrap_or_else(|| Err("nmcli stopped unexpectedly".into()))
                .map(Box::new),
        )
    })
}

/// Run nmcli with `list`, then report Done.
fn act(list: Vec<String>, stdin: Option<String>) -> Task<Msg> {
    Task::perform(system::run("nmcli", list, stdin), |r| Msg::Done(r.map(|_| ())))
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(
            msg,
            Msg::Forget(_) | Msg::Refresh | Msg::Refreshed(_) | Msg::ToggleDetails(_) | Msg::Vpn(_) | Msg::Tailscale(_)
        ) {
            self.confirming = None;
        }
        match msg {
            Msg::Refresh => {
                return Task::batch([
                    refresh(),
                    self.vpn.update(crate::vpn::Msg::Refresh).map(Msg::Vpn),
                    self.tailscale
                        .update(crate::tailscale::Msg::Refresh)
                        .map(Msg::Tailscale),
                ]);
            }
            Msg::Refreshed(Ok(snapshot)) => self.snapshot = Some(*snapshot),
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::ToggleDetails(device) => {
                self.details_open = if self.details_open.as_ref() == Some(&device) {
                    None
                } else {
                    Some(device)
                };
            }
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
            Msg::Forget(name) if self.confirming.as_ref() != Some(&name) => self.confirming = Some(name),
            Msg::Forget(name) => {
                self.confirming = None;
                self.busy = Some(name.clone());
                return act(vec!["connection".into(), "delete".into(), "id".into(), name], None);
            }
            Msg::Vpn(m) => return self.vpn.update(m).map(Msg::Vpn),
            Msg::Tailscale(m) => return self.tailscale.update(m).map(Msg::Tailscale),
            Msg::HiddenSsid(text) => self.hidden_ssid = text,
            Msg::HiddenPassword(text) => self.hidden_password = text,
            Msg::HiddenDialog(open) => {
                self.hidden_open = open;
                if open {
                    return iced::widget::operation::focus(HIDDEN_SSID_ID);
                }
                self.hidden_ssid.clear();
                self.hidden_password.clear();
            }
            Msg::JoinHidden => {
                let ssid = self.hidden_ssid.trim().to_string();
                if ssid.is_empty() {
                    return Task::none();
                }
                self.hidden_open = false;
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
        let toggle = ui::switch(snap.wifi_enabled, idle.then_some(Msg::SetWifi));
        let on = idle && snap.wifi_enabled;
        let mut wifi = vec![ui::item(
            ico::WIFI,
            "Wi-Fi".into(),
            if snap.wifi_enabled { "On".into() } else { "Off".into() },
            vec![
                ui::button_group(vec![
                    ("Scan", on.then_some(Msg::Rescan), Action::Normal),
                    ("+ Hidden", on.then_some(Msg::HiddenDialog(true)), Action::Normal),
                ]),
                toggle,
            ],
        )];
        if snap.wifi_enabled && snap.networks.is_empty() {
            wifi.push(ui::branch(ui::note("No networks found"), true));
        }
        // The networks hang under the Wi-Fi switch as a tree; a network's
        // details or password field stay inside its branch.
        let wifi_device = snap.details.iter().find(|d| d.kind == "Wi-Fi");
        let count = snap.networks.len();
        for (i, n) in snap.networks.iter().enumerate() {
            let device = wifi_device.filter(|_| n.in_use);
            let mut branch =
                column![self.network_row(n, snap.saved.contains(&n.ssid), device.map(|d| d.device.as_str()))];
            if let Some(d) = device.filter(|d| self.details_open.as_ref() == Some(&d.device)) {
                branch = branch.push(crate::infoview::connection_details(d));
            }
            if self.prompt.as_deref() == Some(n.ssid.as_str()) {
                branch = branch.push(self.password_row());
            }
            wifi.push(ui::branch(branch.into(), i + 1 == count));
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
                    let details = snap.details.iter().find(|d| d.device == w.device);
                    let open = details.is_some() && self.details_open.as_ref() == Some(&w.device);
                    let controls = details
                        .map(|_| vec![ui::disclosure(open, Msg::ToggleDetails(w.device.clone()))])
                        .unwrap_or_default();
                    let row = ui::item(ico::ETHERNET_PORT, w.device.clone(), detail, controls);
                    match details.filter(|_| open) {
                        Some(d) => column![row, crate::infoview::connection_details(d)].into(),
                        None => row,
                    }
                })
                .collect();
            body = ui::section(body, "Wired", rows);
        }
        // With its own section, Tailscale's NetworkManager entry is left out
        // of the VPN list.
        let tailscale = self.tailscale.installed();
        if tailscale {
            let rows = self
                .tailscale
                .rows()
                .into_iter()
                .map(|r| r.map(Msg::Tailscale))
                .collect();
            body = ui::section(body, "Tailscale", rows);
        }
        let vpns = self.vpn.rows(tailscale).into_iter().map(|r| r.map(Msg::Vpn)).collect();
        body = ui::section(body, "VPN", vpns);
        body
    }

    /// A nearby network; `device` is the Wi-Fi device when this is the one in
    /// use, which gets a Details button.
    fn network_row<'a>(&'a self, n: &'a Wifi, saved: bool, device: Option<&'a str>) -> Element<'a, Msg> {
        let glyph = match n.signal {
            75.. => ico::WIFI,
            50..=74 => ico::WIFI_HIGH,
            25..=49 => ico::WIFI_LOW,
            _ => ico::WIFI_ZERO,
        };
        let mut detail = vec![format!("{}%", n.signal)];
        detail.push(if n.security.is_empty() {
            "Open".into()
        } else {
            n.security.clone()
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
                let forget = if self.confirming.as_ref() == Some(&n.ssid) {
                    "Sure?"
                } else {
                    "Forget"
                };
                buttons.push((forget, idle.then(|| Msg::Forget(n.ssid.clone())), Action::Danger));
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
            let mut controls = Vec::new();
            if let Some(d) = device {
                let open = self.details_open.as_deref() == Some(d);
                controls.push(ui::disclosure(open, Msg::ToggleDetails(d.to_string())));
            }
            controls.push(ui::button_group(buttons));
            controls
        };
        ui::item(glyph, n.ssid.clone(), detail.join(" · "), controls)
    }

    /// The hidden network dialog, while it is open (app.rs lays it over the
    /// window).
    pub fn dialog(&self) -> Option<Element<'_, Msg>> {
        if !self.hidden_open {
            return None;
        }
        let idle = self.busy.is_none();
        let join = (idle && !self.hidden_ssid.trim().is_empty()).then_some(Msg::JoinHidden);
        let content = column![
            iced::widget::text("Join a hidden network")
                .size(18)
                .font(crate::style::FONT_BOLD),
            iced::widget::text("A network that does not show its name. Type it exactly.")
                .size(13)
                .color(crate::style::MUTED_DEEP),
            text_input("Network name", &self.hidden_ssid)
                .id(HIDDEN_SSID_ID)
                .on_input(Msg::HiddenSsid)
                .on_submit(Msg::JoinHidden)
                .padding([8, 10])
                .style(crate::style::field),
            text_input("Password (empty if open)", &self.hidden_password)
                .secure(true)
                .on_input(Msg::HiddenPassword)
                .on_submit(Msg::JoinHidden)
                .padding([8, 10])
                .style(crate::style::field),
            iced::widget::row![
                iced::widget::Space::new().width(iced::Length::Fill),
                ui::button_group(vec![
                    ("Cancel", Some(Msg::HiddenDialog(false)), Action::Normal),
                    ("Join", join, Action::Primary),
                ]),
            ],
        ]
        .spacing(12);
        Some(content.into())
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
    fn finds_connected_devices() {
        let status = "wlp0s20f3:wifi:connected:TimeCapsule\nenp0s31f6:ethernet:unavailable:\ndocker0:bridge:connected (externally):docker0\nlo:loopback:connected (externally):lo\n";
        assert_eq!(connected_devices(status), ["wlp0s20f3"]);
    }

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
    fn finds_saved_wifi() {
        let out = "TimeCapsule:802-11-wireless:yes\ndocker0:bridge:yes\nwork:vpn:no\nwg0:wireguard:yes\niPhone :802-11-wireless:no\n";
        assert_eq!(parse_connections(out), ["TimeCapsule", "iPhone "]);
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
