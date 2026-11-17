//! Bluetooth panel: power, paired devices and pairing new ones through
//! bluetoothctl.

use iced::widget::Column;
use iced::{Element, Task};

use crate::airpods::{self, AirPods};
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// How long a scan for new devices runs.
const SCAN_SECONDS: &str = "20";

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub powered: bool,
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
}

#[derive(Default)]
pub struct State {
    snapshot: Option<Snapshot>,
    /// MAC of the device being worked on, or "power".
    busy: Option<String>,
    scanning: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Snapshot, String>),
    SetPower(bool),
    Scan,
    ScanDone(Result<(), String>),
    Connect(String),
    Disconnect(String),
    Pair(String),
    Forget(String),
    /// An AirPods control, for the device with this MAC.
    AirPods(String, airpods::Action),
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

/// A name bluez made up from the address ("AA-BB-…") is no name at all.
fn has_real_name(mac: &str, name: &str) -> bool {
    !name.is_empty() && name != mac.replace(':', "-")
}

fn bluetoothctl(list: &[&str]) -> Result<String, String> {
    system::run_blocking("bluetoothctl", &args(list), None)
}

fn snapshot() -> Result<Snapshot, String> {
    let powered = parse_powered(&bluetoothctl(&["show"])?);
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

fn glyph(icon: &str) -> &'static str {
    match icon {
        i if i.starts_with("audio-head") => "󰋋",
        i if i.starts_with("audio") => "󰓃",
        "input-mouse" => "󰍽",
        "input-keyboard" => "󰌌",
        "input-gaming" => "󰊴",
        "phone" => "󰏲",
        "computer" => "󰇄",
        _ => "󰂯",
    }
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return refresh(),
            Msg::Refreshed(Ok(snapshot)) => self.snapshot = Some(snapshot),
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::SetPower(on) => {
                self.busy = Some("power".into());
                return act(args(&["power", if on { "on" } else { "off" }]));
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
            Msg::Forget(mac) => {
                self.busy = Some(mac.clone());
                return act(vec!["remove".into(), mac]);
            }
            Msg::Pair(mac) => {
                self.busy = Some(mac.clone());
                return pair(mac);
            }
            Msg::AirPods(mac, action) => {
                self.busy = Some(mac.clone());
                let list = airpods::command(&mac, &action);
                return Task::perform(system::run("bash", list, None), |r| Msg::Done(r.map(|_| ())));
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
        let power = iced::widget::toggler(snap.powered).on_toggle_maybe(idle.then_some(Msg::SetPower));
        body = ui::section(
            body,
            "Bluetooth",
            vec![ui::item(
                "󰂯",
                "Bluetooth".into(),
                if snap.powered { "On".into() } else { "Off".into() },
                vec![power.into()],
            )],
        );
        if !snap.powered {
            return body;
        }
        let mut paired: Vec<Element<'a, Msg>> = snap.paired.iter().map(|d| self.paired_row(d)).collect();
        if paired.is_empty() {
            paired.push(ui::note("No paired devices"));
        }
        for a in &snap.airpods {
            let mac = a.mac.clone();
            let rows = airpods::rows(a, idle, move |action| Msg::AirPods(mac.clone(), action));
            body = ui::section(body, "AirPods", rows);
        }
        body = ui::section(body, "Paired devices", paired);

        let scan_label = if self.scanning { "Scanning…" } else { "Scan" };
        let mut nearby = vec![ui::item(
            "󰂰",
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

    fn paired_row<'a>(&'a self, d: &'a Device) -> Element<'a, Msg> {
        let mut detail = vec![if d.connected {
            "Connected".to_string()
        } else {
            "Not connected".to_string()
        }];
        if let Some(b) = d.battery {
            detail.push(format!("Battery {b}%"));
        }
        let idle = self.busy.is_none();
        let controls = if self.busy.as_deref() == Some(d.mac.as_str()) {
            vec![ui::note("Working…")]
        } else {
            vec![
                ui::action("Forget", idle.then(|| Msg::Forget(d.mac.clone())), Action::Danger),
                if d.connected {
                    ui::action(
                        "Disconnect",
                        idle.then(|| Msg::Disconnect(d.mac.clone())),
                        Action::Normal,
                    )
                } else {
                    ui::action("Connect", idle.then(|| Msg::Connect(d.mac.clone())), Action::Primary)
                },
            ]
        };
        ui::item(glyph(&d.icon), d.name.clone(), detail.join(" · "), controls)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        assert_eq!(parse_info("X", "Y", "\tConnected: no\n").battery, None);
    }

    #[test]
    fn reads_power_and_skips_made_up_names() {
        assert!(parse_powered("Controller 98:59 (public)\n\tPowered: yes\n"));
        assert!(!parse_powered("\tPowered: no\n"));
        assert!(!has_real_name("AA:BB:CC", "AA-BB-CC"));
        assert!(has_real_name("AA:BB:CC", "JBL"));
    }
}
