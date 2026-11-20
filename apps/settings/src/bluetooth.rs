//! Bluetooth panel: power, visibility, paired devices (connect, rename,
//! trust, block, forget) and pairing new ones through bluetoothctl.

use iced::widget::{Column, container, text_input};
use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::airpods::{self, AirPods};
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// How long a scan for new devices runs.
const SCAN_SECONDS: &str = "20";
/// How long the computer stays visible to other devices.
const VISIBLE_SECONDS: &str = "180";

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub powered: bool,
    /// Other devices can find this computer.
    pub discoverable: bool,
    /// Connected AirPods, with their extra controls.
    pub airpods: Vec<AirPods>,
    pub paired: Vec<Device>,
    /// Devices seen nearby that are not paired.
    pub nearby: Vec<Device>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Device {
    pub mac: String,
    pub name: String,
    /// bluetoothctl icon name, e.g. "audio-headphones".
    pub icon: String,
    pub connected: bool,
    pub battery: Option<u8>,
    /// Connects again on its own, without asking.
    pub trusted: bool,
    /// Refused: it cannot connect until unblocked.
    pub blocked: bool,
}

#[derive(Default)]
pub struct State {
    snapshot: Option<Snapshot>,
    /// MAC of the device being worked on, or "power".
    busy: Option<String>,
    scanning: bool,
    /// Device being renamed: MAC and the name typed so far.
    renaming: Option<(String, String)>,
    /// Device whose Forget was picked once; picking it again forgets it.
    confirming: Option<String>,
    /// Device whose Details (AirPods controls) are open.
    details_open: Option<String>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Snapshot, String>),
    SetPower(bool),
    SetVisible(bool),
    /// Trust or stop trusting a device.
    Trust(String, bool),
    /// Block or unblock a device.
    Block(String, bool),
    Scan,
    ScanDone(Result<(), String>),
    Connect(String),
    Disconnect(String),
    Pair(String),
    Forget(String),
    /// Show or hide a device's Details.
    ToggleDetails(String),
    /// An AirPods control, for the device with this MAC.
    AirPods(String, airpods::Action),
    StartRename(String, String),
    RenameText(String),
    SaveRename,
    CancelRename,
    Done(Result<(), String>),
}

/// `bluetoothctl devices [Paired]`: "Device <MAC> <name>" lines.
pub fn parse_devices(output: &str) -> Vec<(String, String)> {
    output
        .lines()
        .filter_map(|line| {
            let rest = line.strip_prefix("Device ")?;
            let (mac, name) = rest.split_once(' ').unwrap_or((rest, ""));
            Some((mac.to_string(), name.trim().to_string()))
        })
        .collect()
}

/// `bluetoothctl info <MAC>`: the fields the panel shows.
pub fn parse_info(mac: &str, name: &str, output: &str) -> Device {
    let mut device = Device {
        mac: mac.to_string(),
        name: name.to_string(),
        ..Device::default()
    };
    for line in output.lines() {
        let Some((key, value)) = line.trim().split_once(": ") else {
            continue;
        };
        match key {
            "Icon" => device.icon = value.to_string(),
            "Connected" => device.connected = value == "yes",
            "Trusted" => device.trusted = value == "yes",
            "Blocked" => device.blocked = value == "yes",
            // "0x64 (100)": the decimal value is in brackets.
            "Battery Percentage" => {
                device.battery = value
                    .split_once('(')
                    .and_then(|(_, v)| v.trim_end_matches(')').parse().ok())
            }
            _ => {}
        }
    }
    device
}

/// `bluetoothctl show`: whether the adapter is powered.
pub fn parse_powered(output: &str) -> bool {
    output.lines().any(|l| l.trim() == "Powered: yes")
}

/// `bluetoothctl show`: whether other devices can find the adapter.
pub fn parse_discoverable(output: &str) -> bool {
    output.lines().any(|l| l.trim() == "Discoverable: yes")
}

/// A name bluez made up from the address ("AA-BB-…") is no name at all.
fn has_real_name(mac: &str, name: &str) -> bool {
    !name.is_empty() && name != mac.replace(':', "-")
}

fn bluetoothctl(list: &[&str]) -> Result<String, String> {
    system::run_blocking("bluetoothctl", &args(list), None)
}

fn snapshot() -> Result<Snapshot, String> {
    let show = bluetoothctl(&["show"])?;
    let (powered, discoverable) = (parse_powered(&show), parse_discoverable(&show));
    let paired_ids = parse_devices(&bluetoothctl(&["devices", "Paired"])?);
    let mut paired: Vec<Device> = paired_ids
        .iter()
        .map(|(mac, name)| bluetoothctl(&["info", mac]).map(|info| parse_info(mac, name, &info)))
        .collect::<Result<_, _>>()?;
    paired.sort_by(|a, b| b.connected.cmp(&a.connected).then(a.name.cmp(&b.name)));
    let nearby = parse_devices(&bluetoothctl(&["devices"])?)
        .into_iter()
        .filter(|(mac, name)| has_real_name(mac, name) && !paired_ids.iter().any(|(p, _)| p == mac))
        .map(|(mac, name)| Device {
            mac,
            name,
            ..Device::default()
        })
        .collect();
    let airpods = paired
        .iter()
        .filter(|d| d.connected && airpods::is_airpods(&d.name))
        .map(|d| airpods::read(&d.mac, &d.name))
        .collect();
    Ok(Snapshot {
        powered,
        discoverable,
        airpods,
        paired,
        nearby,
    })
}

fn refresh() -> Task<Msg> {
    Task::perform(system::spawn(snapshot), |r| {
        Msg::Refreshed(r.unwrap_or_else(|| Err("bluetoothctl stopped unexpectedly".into())))
    })
}

fn act(list: Vec<String>) -> Task<Msg> {
    Task::perform(system::run("bluetoothctl", list, None), |r| Msg::Done(r.map(|_| ())))
}

/// Pair, trust (so it reconnects on its own) and connect.
fn pair(mac: String) -> Task<Msg> {
    let steps = move || -> Result<(), String> {
        for verb in ["pair", "trust", "connect"] {
            bluetoothctl(&[verb, &mac])?;
        }
        Ok(())
    };
    Task::perform(system::spawn(steps), |r| {
        Msg::Done(r.unwrap_or_else(|| Err("pairing stopped unexpectedly".into())))
    })
}

/// The bluez object path of a device, from `busctl --list tree org.bluez`.
pub fn device_path(tree: &str, mac: &str) -> Option<String> {
    let suffix = format!("/dev_{}", mac.replace(':', "_"));
    tree.lines()
        .map(str::trim)
        .find(|l| l.ends_with(&suffix))
        .map(String::from)
}

/// Set a device's alias (the name shown everywhere) over D-Bus.
fn rename(mac: &str, name: &str) -> Result<(), String> {
    let tree = system::run_blocking("busctl", &args(&["--list", "tree", "org.bluez"]), None)?;
    let path = device_path(&tree, mac).ok_or_else(|| format!("bluez does not know {mac}"))?;
    system::run_blocking(
        "busctl",
        &args(&[
            "set-property",
            "org.bluez",
            &path,
            "org.bluez.Device1",
            "Alias",
            "s",
            name,
        ]),
        None,
    )
    .map(|_| ())
}

fn glyph(icon: &str) -> crate::ui::Icon {
    match icon {
        i if i.starts_with("audio-head") => ico::HEADPHONES,
        i if i.starts_with("audio") => ico::SPEAKER,
        "input-mouse" => ico::MOUSE,
        "input-keyboard" => ico::KEYBOARD,
        "input-gaming" => ico::GAMEPAD_2,
        "phone" => ico::SMARTPHONE,
        "computer" => ico::MONITOR,
        _ => ico::BLUETOOTH,
    }
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        if !matches!(
            msg,
            Msg::Forget(_) | Msg::Refresh | Msg::Refreshed(_) | Msg::ToggleDetails(_)
        ) {
            self.confirming = None;
        }
        match msg {
            Msg::Refresh => return refresh(),
            Msg::Refreshed(Ok(snapshot)) => self.snapshot = Some(snapshot),
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::SetPower(on) => {
                self.busy = Some("power".into());
                return act(args(&["power", if on { "on" } else { "off" }]));
            }
            Msg::SetVisible(on) => {
                self.busy = Some("power".into());
                let steps = move || -> Result<(), String> {
                    if on {
                        bluetoothctl(&["discoverable-timeout", VISIBLE_SECONDS])?;
                    }
                    bluetoothctl(&["discoverable", if on { "on" } else { "off" }]).map(|_| ())
                };
                return Task::perform(system::spawn(steps), |r| {
                    Msg::Done(r.unwrap_or_else(|| Err("bluetoothctl stopped unexpectedly".into())))
                });
            }
            Msg::Trust(mac, on) => {
                self.busy = Some(mac.clone());
                return act(vec![if on { "trust" } else { "untrust" }.into(), mac]);
            }
            Msg::Block(mac, on) => {
                self.busy = Some(mac.clone());
                return act(vec![if on { "block" } else { "unblock" }.into(), mac]);
            }
            Msg::Scan => {
                self.scanning = true;
                let list = args(&["--timeout", SCAN_SECONDS, "scan", "on"]);
                return Task::perform(system::run("bluetoothctl", list, None), |r| {
                    Msg::ScanDone(r.map(|_| ()))
                });
            }
            Msg::ScanDone(result) => {
                self.scanning = false;
                self.error = result.err();
                return refresh();
            }
            Msg::Connect(mac) => {
                self.busy = Some(mac.clone());
                return act(vec!["connect".into(), mac]);
            }
            Msg::Disconnect(mac) => {
                self.busy = Some(mac.clone());
                return act(vec!["disconnect".into(), mac]);
            }
            Msg::Forget(mac) if self.confirming.as_ref() != Some(&mac) => self.confirming = Some(mac),
            Msg::Forget(mac) => {
                self.confirming = None;
                self.busy = Some(mac.clone());
                return act(vec!["remove".into(), mac]);
            }
            Msg::Pair(mac) => {
                self.busy = Some(mac.clone());
                return pair(mac);
            }
            Msg::ToggleDetails(mac) => {
                self.details_open = if self.details_open.as_ref() == Some(&mac) {
                    None
                } else {
                    Some(mac)
                };
            }
            Msg::AirPods(mac, action) => {
                self.busy = Some(mac.clone());
                let list = airpods::command(&mac, &action);
                return Task::perform(system::run("bash", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::StartRename(mac, name) => self.renaming = Some((mac, name)),
            Msg::RenameText(text) => {
                if let Some((_, name)) = &mut self.renaming {
                    *name = text;
                }
            }
            Msg::CancelRename => self.renaming = None,
            Msg::SaveRename => {
                if let Some((mac, name)) = self.renaming.take() {
                    let name = name.trim().to_string();
                    if name.is_empty() {
                        return Task::none();
                    }
                    self.busy = Some(mac.clone());
                    return Task::perform(system::spawn(move || rename(&mac, &name)), |r| {
                        Msg::Done(r.unwrap_or_else(|| Err("renaming stopped unexpectedly".into())))
                    });
                }
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
            return ui::section(body, "Bluetooth", vec![ui::note("Loading…")]);
        };
        let idle = self.busy.is_none();
        let power = ui::switch(snap.powered, idle.then_some(Msg::SetPower));
        let mut adapter = vec![ui::item(
            ico::BLUETOOTH,
            "Bluetooth".into(),
            if snap.powered { "On".into() } else { "Off".into() },
            vec![power],
        )];
        if snap.powered {
            adapter.push(ui::item(
                ico::RADIO,
                "Visible to other devices".into(),
                "For 3 minutes, so a phone or another computer can find this one".into(),
                vec![ui::switch(snap.discoverable, idle.then_some(Msg::SetVisible))],
            ));
        }
        body = ui::section(body, "Bluetooth", adapter);
        if !snap.powered {
            return body;
        }
        let mut paired: Vec<Element<'a, Msg>> = Vec::new();
        for d in &snap.paired {
            let extras = snap.airpods.iter().find(|a| a.mac == d.mac);
            paired.push(self.paired_row(d, extras.is_some()));
            // AirPods controls hang under their device, behind Details.
            if let Some(a) = extras.filter(|_| self.details_open.as_ref() == Some(&d.mac)) {
                let mac = a.mac.clone();
                let rows = airpods::rows(a, idle, move |action| Msg::AirPods(mac.clone(), action));
                let count = rows.len();
                paired.extend(rows.into_iter().enumerate().map(|(i, r)| ui::branch(r, i + 1 == count)));
            }
            if let Some((mac, name)) = &self.renaming
                && *mac == d.mac
            {
                let field = text_input("Device name", name)
                    .on_input(Msg::RenameText)
                    .on_submit(Msg::SaveRename);
                let save = (!name.trim().is_empty()).then_some(Msg::SaveRename);
                let buttons = vec![
                    ("Cancel", Some(Msg::CancelRename), Action::Normal),
                    ("Save", save, Action::Primary),
                ];
                paired.push(container(ui::input_group(field, buttons)).padding([4, 14]).into());
            }
        }
        if paired.is_empty() {
            paired.push(ui::note("No paired devices"));
        }
        body = ui::section(body, "Paired devices", paired);

        let scan_label = if self.scanning { "Scanning…" } else { "Scan" };
        let mut nearby = vec![ui::item(
            ico::BLUETOOTH_SEARCHING,
            "Nearby devices".into(),
            "Put the device in pairing mode, then scan".into(),
            vec![ui::action(
                scan_label,
                (!self.scanning).then_some(Msg::Scan),
                Action::Normal,
            )],
        )];
        for d in &snap.nearby {
            let control = if self.busy.as_deref() == Some(d.mac.as_str()) {
                ui::note("Pairing…")
            } else {
                ui::action("Pair", idle.then(|| Msg::Pair(d.mac.clone())), Action::Primary)
            };
            nearby.push(ui::item(glyph(&d.icon), d.name.clone(), d.mac.clone(), vec![control]));
        }
        ui::section(body, "Add a device", nearby)
    }

    /// A paired device; `extras` (AirPods controls) adds a Details button.
    fn paired_row<'a>(&'a self, d: &'a Device, extras: bool) -> Element<'a, Msg> {
        let mut detail = vec![match (d.blocked, d.connected) {
            (true, _) => "Blocked".to_string(),
            (_, true) => "Connected".to_string(),
            _ => "Not connected".to_string(),
        }];
        if let Some(b) = d.battery {
            detail.push(format!("Battery {b}%"));
        }
        let idle = self.busy.is_none();
        let controls = if self.busy.as_deref() == Some(d.mac.as_str()) {
            vec![ui::note("Working…")]
        } else {
            let connect = if d.connected {
                (
                    "Disconnect",
                    idle.then(|| Msg::Disconnect(d.mac.clone())),
                    Action::Normal,
                )
            } else {
                ("Connect", idle.then(|| Msg::Connect(d.mac.clone())), Action::Primary)
            };
            let forget = if self.confirming.as_ref() == Some(&d.mac) {
                "Forget — sure?"
            } else {
                "Forget"
            };
            let trust = if d.trusted { "Ask before connecting" } else { "Trust" };
            let block = if d.blocked { "Unblock" } else { "Block" };
            // A blocked device cannot connect: Unblock is what it needs.
            let main = if d.blocked {
                (
                    "Unblock",
                    idle.then(|| Msg::Block(d.mac.clone(), false)),
                    Action::Normal,
                )
            } else {
                connect
            };
            let mut more = vec![("Rename", idle.then(|| Msg::StartRename(d.mac.clone(), d.name.clone())))];
            if !d.blocked {
                more.push((trust, idle.then(|| Msg::Trust(d.mac.clone(), !d.trusted))));
                more.push((block, idle.then(|| Msg::Block(d.mac.clone(), true))));
            }
            more.push((forget, idle.then(|| Msg::Forget(d.mac.clone()))));
            let actions = ui::more_actions(main, more);
            if extras {
                let open = self.details_open.as_ref() == Some(&d.mac);
                vec![ui::disclosure(open, Msg::ToggleDetails(d.mac.clone())), actions]
            } else {
                vec![actions]
            }
        };
        ui::item(glyph(&d.icon), d.name.clone(), detail.join(" · "), controls)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_device_paths() {
        let tree = "/org/bluez\n/org/bluez/hci0\n/org/bluez/hci0/dev_CC_22_FE_32_52_E4\n/org/bluez/hci0/dev_CC_22_FE_32_52_E4/sep1\n";
        assert_eq!(
            device_path(tree, "CC:22:FE:32:52:E4").as_deref(),
            Some("/org/bluez/hci0/dev_CC_22_FE_32_52_E4")
        );
        assert_eq!(device_path(tree, "AA:BB"), None);
    }

    #[test]
    fn parses_device_lists() {
        let out = "Device CE:05:0F:D2:2B:71 Dell Mouse MS5320W\nDevice F8:71:A6:B7:98:BE iPhone\nnoise\n";
        assert_eq!(
            parse_devices(out),
            [
                ("CE:05:0F:D2:2B:71".to_string(), "Dell Mouse MS5320W".to_string()),
                ("F8:71:A6:B7:98:BE".to_string(), "iPhone".to_string())
            ]
        );
    }

    #[test]
    fn parses_device_info() {
        let out = "Device CC:22 (public)\n\tName: AirPods\n\tIcon: audio-headphones\n\tPaired: yes\n\tConnected: yes\n\tBattery Percentage: 0x5a (90)\n";
        let d = parse_info("CC:22", "AirPods Pro", out);
        assert_eq!(d.name, "AirPods Pro");
        assert_eq!(d.icon, "audio-headphones");
        assert!(d.connected);
        assert_eq!(d.battery, Some(90));
        assert!(!d.trusted && !d.blocked);
        let t = parse_info("X", "Y", "\tTrusted: yes\n\tBlocked: yes\n");
        assert!(t.trusted && t.blocked);
        assert_eq!(parse_info("X", "Y", "\tConnected: no\n").battery, None);
    }

    #[test]
    fn reads_power_and_skips_made_up_names() {
        assert!(parse_powered("Controller 98:59 (public)\n\tPowered: yes\n"));
        assert!(!parse_powered("\tPowered: no\n"));
        assert!(parse_discoverable("\tPowered: yes\n\tDiscoverable: yes\n"));
        assert!(!parse_discoverable("\tDiscoverable: no\n"));
        assert!(!has_real_name("AA:BB:CC", "AA-BB-CC"));
        assert!(has_real_name("AA:BB:CC", "JBL"));
    }
}
