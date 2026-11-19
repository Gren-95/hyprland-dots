//! VPN section of the Network panel, through nmcli: every VPN connection
//! (WireGuard, OpenVPN, OpenConnect, vpnc, Tailscale…) with an on/off switch
//! and Details (type, server, address, DNS, Delete); importing a WireGuard
//! .conf or OpenVPN .ovpn file; and setting up WireGuard by hand.
//! NetworkManager starts a connection the moment it is imported; it is
//! switched off right after and kept from connecting on its own
//! (autoconnect off), so a new VPN is off until it is switched on.

use std::path::PathBuf;

use iced::widget::{column, row, text, text_input};
use iced::{Alignment, Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Vpn {
    pub name: String,
    pub uuid: String,
    /// "WireGuard", "OpenVPN", "Tailscale"…
    pub kind: String,
    pub active: bool,
}

/// What Details shows.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Info {
    pub server: String,
    pub addresses: Vec<String>,
    pub dns: Vec<String>,
}

/// The WireGuard form.
#[derive(Debug, Clone, Default)]
pub struct Form {
    pub name: String,
    pub private_key: String,
    pub address: String,
    pub dns: String,
    pub peer_key: String,
    pub endpoint: String,
    pub allowed_ips: String,
}

#[derive(Debug, Clone, Copy)]
pub enum Field {
    Name,
    PrivateKey,
    Address,
    Dns,
    PeerKey,
    Endpoint,
    AllowedIps,
}

/// Split one line of `nmcli -t` output: ':' and '\' inside a field are
/// escaped with '\'.
fn split_terse(line: &str) -> Vec<String> {
    let mut fields = vec![String::new()];
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        match c {
            '\\' => fields.last_mut().unwrap().extend(chars.next()),
            ':' => fields.push(String::new()),
            c => fields.last_mut().unwrap().push(c),
        }
    }
    fields
}

/// A VPN service type as people name it.
pub fn kind_name(service: &str) -> String {
    let short = service.rsplit('.').next().unwrap_or(service);
    match short {
        "openvpn" => "OpenVPN",
        "openconnect" => "OpenConnect",
        "vpnc" => "Cisco (vpnc)",
        "tailscale" => "Tailscale",
        "pptp" => "PPTP",
        "l2tp" => "L2TP",
        "strongswan" => "IPsec",
        _ => short,
    }
    .to_string()
}

/// `nmcli -t -f NAME,UUID,TYPE,ACTIVE connection show` lines that are VPNs;
/// `service` names a "vpn" connection's service type by uuid.
pub fn parse_vpns(output: &str, service: impl Fn(&str) -> String) -> Vec<Vpn> {
    output
        .lines()
        .map(split_terse)
        .filter(|f| f.len() >= 4 && (f[2] == "vpn" || f[2] == "wireguard"))
        .map(|f| Vpn {
            kind: if f[2] == "wireguard" {
                "WireGuard".into()
            } else {
                kind_name(&service(&f[1]))
            },
            name: f[0].clone(),
            uuid: f[1].clone(),
            active: f[3] == "yes",
        })
        .collect()
}

/// The server of a connection: a WireGuard peer's endpoint=, or an OpenVPN
/// remote= / OpenConnect gateway= in vpn.data.
pub fn parse_server(peers: &str, data: &str) -> String {
    let endpoint = peers.split_whitespace().find_map(|w| w.strip_prefix("endpoint="));
    // vpn.data is "key = value, key = value".
    let from_data = || {
        data.split(',').find_map(|pair| {
            let (key, value) = pair.split_once('=')?;
            matches!(key.trim(), "remote" | "gateway").then(|| value.trim())
        })
    };
    endpoint.or_else(from_data).unwrap_or_default().to_string()
}

fn nmcli(list: &[&str]) -> Result<String, String> {
    system::run_blocking("nmcli", &args(list), None)
}

fn load() -> Result<Vec<Vpn>, String> {
    let out = nmcli(&["-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show"])?;
    Ok(parse_vpns(&out, |uuid| {
        nmcli(&["-g", "vpn.service-type", "connection", "show", "uuid", uuid])
            .unwrap_or_default()
            .trim()
            .to_string()
    }))
}

fn info(uuid: &str) -> Info {
    let field = |name: &str| {
        nmcli(&["-g", name, "connection", "show", "uuid", uuid])
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let list = |s: String| -> Vec<String> {
        s.split([',', ' ', '|'])
            .map(|x| x.trim().replace("\\:", ":"))
            .filter(|x| !x.is_empty())
            .collect()
    };
    Info {
        server: parse_server(&field("wireguard.peers"), &field("vpn.data")).replace("\\:", ":"),
        addresses: list(field("ipv4.addresses")),
        dns: list(field("ipv4.dns")),
    }
}

/// A WireGuard key: 32 bytes in base64 (44 characters ending in '=').
pub fn valid_key(key: &str) -> bool {
    key.len() == 44
        && key.ends_with('=')
        && key[..43]
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/')
}

/// Why the form cannot be used yet, if it cannot.
pub fn form_problem(f: &Form) -> Option<&'static str> {
    if f.name.trim().is_empty() {
        Some("Give it a name")
    } else if !valid_key(f.private_key.trim()) {
        Some("The private key is 44 characters ending in =")
    } else if !f.address.contains('/') && !f.address.contains('.') && !f.address.contains(':') {
        Some("The address is like 10.2.0.2/32")
    } else if !valid_key(f.peer_key.trim()) {
        Some("The server's public key is 44 characters ending in =")
    } else if !f.endpoint.trim().contains(':') {
        Some("The endpoint is host:port")
    } else {
        None
    }
}

/// The form as a wg-quick file, for `nmcli connection import`.
pub fn wg_quick(f: &Form) -> String {
    let mut s = format!(
        "[Interface]\nPrivateKey = {}\nAddress = {}\n",
        f.private_key.trim(),
        f.address.trim()
    );
    if !f.dns.trim().is_empty() {
        s += &format!("DNS = {}\n", f.dns.trim());
    }
    let allowed = if f.allowed_ips.trim().is_empty() {
        "0.0.0.0/0, ::/0"
    } else {
        f.allowed_ips.trim()
    };
    s += &format!(
        "\n[Peer]\nPublicKey = {}\nAllowedIPs = {allowed}\nEndpoint = {}\n",
        f.peer_key.trim(),
        f.endpoint.trim()
    );
    s
}

/// "wireguard" or "openvpn" for a file to import, by name and content.
pub fn import_type(path: &str, content: &str) -> Option<&'static str> {
    if path.ends_with(".ovpn") {
        Some("openvpn")
    } else if content.contains("[Interface]") {
        Some("wireguard")
    } else if path.ends_with(".conf") && content.lines().any(|l| l.trim_start().starts_with("remote ")) {
        Some("openvpn")
    } else {
        None
    }
}

/// The uuid in "Connection 'x' (uuid) successfully added."
pub fn added_uuid(output: &str) -> Option<String> {
    let start = output.rfind('(')? + 1;
    let end = output[start..].find(')')? + start;
    Some(output[start..end].to_string())
}

/// Import `path` as `kind`, switch it off, keep it from connecting on its
/// own and, when given, name it.
fn import(path: &str, kind: &str, name: Option<&str>) -> Result<(), String> {
    let out = nmcli(&["connection", "import", "type", kind, "file", path])?;
    let uuid = added_uuid(&out).ok_or("NetworkManager did not say what it added")?;
    let mut change = vec!["connection", "modify", "uuid", &uuid, "connection.autoconnect", "no"];
    if let Some(name) = name {
        change.extend(["connection.id", name]);
    }
    nmcli(&change)?;
    // NetworkManager already started it; a new VPN starts off.
    let _ = nmcli(&["connection", "down", "uuid", &uuid]);
    Ok(())
}

fn import_file(path: String) -> Result<(), String> {
    let content = std::fs::read_to_string(&path).map_err(|_| "Could not read that file".to_string())?;
    let kind = import_type(&path, &content).ok_or("Not a WireGuard (.conf) or OpenVPN (.ovpn) file")?;
    import(&path, kind, None)
}

/// A free interface name for the file name (it becomes the interface):
/// wg0, wg1… up to 15 characters.
fn free_interface() -> String {
    (0..100)
        .map(|n| format!("wg{n}"))
        .find(|n| !std::path::Path::new("/sys/class/net").join(n).exists())
        .unwrap_or_else(|| "wgdots".into())
}

/// Write the form to a private file in the runtime directory (it holds the
/// private key), import it, and remove it again.
fn create(form: Form) -> Result<(), String> {
    let dir = PathBuf::from(std::env::var("XDG_RUNTIME_DIR").map_err(|_| "No runtime directory")?);
    let path = dir.join(format!("{}.conf", free_interface()));
    {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut file = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
            .map_err(|e| format!("Could not write the setup file: {e}"))?;
        file.write_all(wg_quick(&form).as_bytes())
            .map_err(|e| format!("Could not write the setup file: {e}"))?;
    }
    let result = import(&path.to_string_lossy(), "wireguard", Some(form.name.trim()));
    let _ = std::fs::remove_file(&path);
    result
}

#[derive(Default)]
pub struct State {
    vpns: Vec<Vpn>,
    /// Connection whose Details are open, with what they show once read.
    open: Option<(String, Option<Info>)>,
    /// Connection being switched or removed.
    busy: Option<String>,
    /// Connection whose Delete was clicked once.
    confirming: Option<String>,
    form: Option<Form>,
    adding: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Vec<Vpn>, String>),
    Set(String, bool),
    ToggleDetails(String),
    Detailed(String, Info),
    Delete(String),
    Import,
    Picked(Option<String>),
    Create,
    Edit(Field, String),
    Add,
    CancelForm,
    Done(Result<(), String>),
}

fn spawn_done(work: impl FnOnce() -> Result<(), String> + Send + 'static) -> Task<Msg> {
    Task::perform(system::spawn(work), |r| {
        Msg::Done(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
    })
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(msg, Msg::Delete(_) | Msg::Refresh | Msg::Refreshed(_)) {
            self.confirming = None;
        }
        match msg {
            Msg::Refresh => {
                return Task::perform(system::spawn(load), |r| {
                    Msg::Refreshed(r.unwrap_or_else(|| Err("nmcli stopped unexpectedly".into())))
                });
            }
            Msg::Refreshed(Ok(list)) => self.vpns = list,
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::Set(uuid, on) => {
                self.busy = Some(uuid.clone());
                let verb = if on { "up" } else { "down" };
                return spawn_done(move || nmcli(&["connection", verb, "uuid", &uuid]).map(|_| ()));
            }
            Msg::ToggleDetails(uuid) => {
                if self.open.as_ref().is_some_and(|(u, _)| *u == uuid) {
                    self.open = None;
                } else {
                    self.open = Some((uuid.clone(), None));
                    return Task::perform(system::spawn(move || (uuid.clone(), info(&uuid))), |r| {
                        let (uuid, info) = r.unwrap_or_default();
                        Msg::Detailed(uuid, info)
                    });
                }
            }
            Msg::Detailed(uuid, info) => {
                if let Some((open, slot)) = &mut self.open
                    && *open == uuid
                {
                    *slot = Some(info);
                }
            }
            Msg::Delete(uuid) => {
                if self.confirming.as_ref() != Some(&uuid) {
                    self.confirming = Some(uuid);
                } else {
                    self.confirming = None;
                    self.open = None;
                    self.busy = Some(uuid.clone());
                    return spawn_done(move || nmcli(&["connection", "delete", "uuid", &uuid]).map(|_| ()));
                }
            }
            Msg::Import => {
                let list = args(&[
                    "--file-selection",
                    "--title=Import a VPN",
                    "--file-filter=VPN files | *.conf *.ovpn",
                    "--file-filter=All files | *",
                ]);
                return Task::perform(system::run("zenity", list, None), |r| {
                    Msg::Picked(r.ok().map(|p| p.trim().to_string()).filter(|p| !p.is_empty()))
                });
            }
            Msg::Picked(None) => {}
            Msg::Picked(Some(path)) => {
                self.adding = true;
                return spawn_done(move || import_file(path));
            }
            Msg::Create => {
                self.form = Some(Form {
                    allowed_ips: "0.0.0.0/0, ::/0".into(),
                    ..Form::default()
                })
            }
            Msg::Edit(field, value) => {
                if let Some(f) = &mut self.form {
                    let slot = match field {
                        Field::Name => &mut f.name,
                        Field::PrivateKey => &mut f.private_key,
                        Field::Address => &mut f.address,
                        Field::Dns => &mut f.dns,
                        Field::PeerKey => &mut f.peer_key,
                        Field::Endpoint => &mut f.endpoint,
                        Field::AllowedIps => &mut f.allowed_ips,
                    };
                    *slot = value;
                }
            }
            Msg::Add => {
                if let Some(form) = self.form.clone().filter(|f| form_problem(f).is_none()) {
                    self.adding = true;
                    return spawn_done(move || create(form));
                }
            }
            Msg::CancelForm => self.form = None,
            Msg::Done(r) => {
                let ok = r.is_ok();
                self.error = r.err();
                if ok && self.adding {
                    self.form = None;
                }
                self.adding = false;
                self.busy = None;
                return self.update(Msg::Refresh);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if self.vpns.is_empty() {
            rows.push(ui::note("No VPN yet"));
        }
        for v in &self.vpns {
            rows.push(self.vpn_row(v));
            if let Some((_, info)) = self.open.as_ref().filter(|(u, _)| *u == v.uuid) {
                rows.push(self.details(v, info.as_ref()));
            }
        }
        rows.push(self.add_row());
        if let Some(form) = &self.form {
            rows.push(self.form_view(form));
        }
        rows
    }

    fn vpn_row<'a>(&'a self, v: &'a Vpn) -> Element<'a, Msg> {
        let idle = self.busy.is_none() && !self.adding;
        let state = if self.busy.as_ref() == Some(&v.uuid) {
            "Working…"
        } else if v.active {
            "Connected"
        } else {
            "Off"
        };
        let uuid = v.uuid.clone();
        let switch = ui::switch(v.active, idle.then_some(move |on| Msg::Set(uuid.clone(), on)));
        let open = self.open.as_ref().is_some_and(|(u, _)| *u == v.uuid);
        ui::item(
            if v.active { ico::SHIELD_CHECK } else { ico::SHIELD },
            v.name.clone(),
            format!("{} · {state}", v.kind),
            vec![ui::disclosure(open, Msg::ToggleDetails(v.uuid.clone())), switch],
        )
    }

    fn details<'a>(&'a self, v: &'a Vpn, info: Option<&'a Info>) -> Element<'a, Msg> {
        let Some(info) = info else {
            return iced::widget::container(ui::note("Reading…")).padding([0, 52]).into();
        };
        let delete = if self.confirming.as_ref() == Some(&v.uuid) {
            "Sure?"
        } else {
            "Delete"
        };
        let facts = [
            ("Type", v.kind.clone()),
            ("Server", info.server.clone()),
            ("Address", info.addresses.join(", ")),
            ("DNS", info.dns.join(", ")),
        ];
        let mut col = column![].spacing(6);
        for (label, value) in facts.into_iter().filter(|(_, v)| !v.is_empty()) {
            col = col.push(row![
                text(label).size(13).color(style::MUTED_DEEP).width(110),
                text(value).size(13).color(style::FG_MUTED),
            ]);
        }
        col = col.push(ui::action(
            delete,
            self.busy.is_none().then(|| Msg::Delete(v.uuid.clone())),
            Action::Danger,
        ));
        iced::widget::container(col)
            .padding(iced::Padding {
                top: 0.0,
                right: 14.0,
                bottom: 10.0,
                left: 52.0,
            })
            .into()
    }

    fn add_row(&self) -> Element<'_, Msg> {
        let idle = !self.adding && self.form.is_none();
        let detail = if self.adding {
            "Adding…"
        } else {
            "Import a WireGuard (.conf) or OpenVPN (.ovpn) file, or set up WireGuard by hand"
        };
        ui::item(
            ico::PLUS,
            "Add a VPN".into(),
            detail.into(),
            vec![ui::button_group(vec![
                ("Import file…", idle.then_some(Msg::Import), Action::Normal),
                ("WireGuard…", idle.then_some(Msg::Create), Action::Normal),
            ])],
        )
    }

    fn form_view<'a>(&'a self, f: &'a Form) -> Element<'a, Msg> {
        let field = |label: &'a str, hint: &'a str, value: &'a str, which: Field, secret: bool| -> Element<'a, Msg> {
            row![
                text(label).size(13).color(style::FG).width(150),
                text_input(hint, value)
                    .secure(secret)
                    .on_input(move |s| Msg::Edit(which, s))
                    .on_submit(Msg::Add)
                    .padding([6, 10])
                    .size(13)
                    .width(Length::Fill)
                    .style(style::field),
            ]
            .spacing(12)
            .align_y(Alignment::Center)
            .into()
        };
        let problem = form_problem(f);
        let mut col = column![
            text("New WireGuard connection").size(14).color(style::FG),
            text("From your provider's WireGuard setup. It stays off until you switch it on.")
                .size(12)
                .color(style::MUTED_DEEP),
            field("Name", "Work, Proton FI-1…", &f.name, Field::Name, false),
            field(
                "Private key",
                "Your key, 44 characters",
                &f.private_key,
                Field::PrivateKey,
                true
            ),
            field("Address", "10.2.0.2/32", &f.address, Field::Address, false),
            field("DNS", "Optional, 10.2.0.1", &f.dns, Field::Dns, false),
            field("Server public key", "44 characters", &f.peer_key, Field::PeerKey, false),
            field("Endpoint", "host:51820", &f.endpoint, Field::Endpoint, false),
            field(
                "Allowed IPs",
                "0.0.0.0/0, ::/0",
                &f.allowed_ips,
                Field::AllowedIps,
                false
            ),
        ]
        .spacing(8);
        let footer = row![
            text(problem.unwrap_or(""))
                .size(12)
                .color(style::MUTED_DEEP)
                .width(Length::Fill),
            ui::button_group(vec![
                ("Cancel", Some(Msg::CancelForm), Action::Normal),
                (
                    "Add",
                    (problem.is_none() && !self.adding).then_some(Msg::Add),
                    Action::Primary
                ),
            ]),
        ]
        .align_y(Alignment::Center);
        col = col.push(footer);
        iced::widget::container(col).padding([10, 14]).into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "N3IkjWjh9PFh3Wo0srltI6X8pm9EJbc3hTu0sFfxSwE=";

    #[test]
    fn lists_vpns_with_their_kind() {
        let out = "Home Wi-Fi:1:802-11-wireless:yes\nTailscale:2:vpn:yes\nProton FI-33:3:wireguard:no\nWork:4:vpn:no\n";
        let vpns = parse_vpns(out, |uuid| {
            if uuid == "2" {
                "org.freedesktop.NetworkManager.tailscale".into()
            } else {
                "org.freedesktop.NetworkManager.openvpn".into()
            }
        });
        let kinds: Vec<_> = vpns
            .iter()
            .map(|v| (v.name.as_str(), v.kind.as_str(), v.active))
            .collect();
        assert_eq!(
            kinds,
            [
                ("Tailscale", "Tailscale", true),
                ("Proton FI-33", "WireGuard", false),
                ("Work", "OpenVPN", false)
            ]
        );
    }

    #[test]
    fn finds_the_server() {
        let peers = format!("{KEY} allowed-ips=0.0.0.0/0;::/0 endpoint=130.195.221.162:51820 persistent-keepalive=25");
        assert_eq!(parse_server(&peers, ""), "130.195.221.162:51820");
        assert_eq!(
            parse_server("", "connection-type = tls, remote = vpn.example.com:1194, dev = tun"),
            "vpn.example.com:1194"
        );
        assert_eq!(parse_server("", ""), "");
    }

    #[test]
    fn checks_and_writes_the_form() {
        let mut f = Form {
            name: "Test".into(),
            private_key: KEY.into(),
            address: "10.2.0.2/32".into(),
            peer_key: KEY.into(),
            endpoint: "vpn.example.com:51820".into(),
            ..Form::default()
        };
        assert_eq!(form_problem(&f), None);
        let conf = wg_quick(&f);
        assert!(conf.contains("[Peer]\nPublicKey = N3Ikj"));
        assert!(conf.contains("AllowedIPs = 0.0.0.0/0, ::/0"));
        assert!(!conf.contains("DNS"));
        f.private_key = "short".into();
        assert!(form_problem(&f).is_some());
    }

    #[test]
    fn tells_files_and_reads_results() {
        assert_eq!(import_type("a.ovpn", ""), Some("openvpn"));
        assert_eq!(
            import_type("wg0.conf", "[Interface]\nPrivateKey = x\n"),
            Some("wireguard")
        );
        assert_eq!(
            import_type("x.conf", "client\nremote vpn.example.com 1194\n"),
            Some("openvpn")
        );
        assert_eq!(import_type("notes.txt", "hello"), None);
        assert_eq!(
            added_uuid("Connection 'wg0' (4a6274d8-12f2-4d1b-9b92-7ae4df4914e7) successfully added.").as_deref(),
            Some("4a6274d8-12f2-4d1b-9b92-7ae4df4914e7")
        );
    }
}
