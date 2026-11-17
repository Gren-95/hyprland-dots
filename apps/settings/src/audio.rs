//! Sound panel: output and input devices and app volumes through PipeWire.
//! `pw-dump` lists the nodes (pactl's JSON drops names with non-ASCII
//! characters); `wpctl` reads and sets volume, mute and the defaults, as it
//! also handles volumes kept on the device route.

use iced::widget::{Column, container, row, slider, text, toggler};
use iced::{Alignment, Element, Length, Task};

use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub outputs: Vec<Node>,
    pub inputs: Vec<Node>,
    pub apps: Vec<Node>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Node {
    pub id: u32,
    pub label: String,
    /// node.name, e.g. "bluez_output.CC_22_FE_32_52_E4.1".
    pub name: String,
    pub is_default: bool,
    /// wpctl's scale: 1.0 is 100%.
    pub volume: f32,
    pub muted: bool,
}

#[derive(Default)]
pub struct State {
    snapshot: Option<Snapshot>,
    /// Node whose slider is being dragged, with the shown volume.
    dragging: Option<(u32, f32)>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Result<Snapshot, String>),
    SetDefault(u32),
    /// A slider moved; written on VolumeCommit.
    Volume(u32, f32),
    VolumeCommit,
    SetMute(u32, bool),
    Done(Result<(), String>),
}

/// Kind of node, from media.class.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Class {
    Output,
    Input,
    App,
}

/// What `pw-dump` says about audio.
#[derive(Debug, Default)]
pub struct Dump {
    pub nodes: Vec<DumpNode>,
    pub default_sink: String,
    pub default_source: String,
}

#[derive(Debug, PartialEq)]
pub struct DumpNode {
    pub id: u32,
    pub class: Class,
    pub name: String,
    pub label: String,
}

/// The audio nodes and the default sink and source names from `pw-dump`.
pub fn parse_dump(json: &str) -> Result<Dump, String> {
    let objects: Vec<serde_json::Value> = serde_json::from_str(json).map_err(|e| format!("pw-dump: {e}"))?;
    let mut dump = Dump::default();
    for o in &objects {
        match o["type"].as_str() {
            Some("PipeWire:Interface:Node") => {
                let props = &o["info"]["props"];
                let class = match props["media.class"].as_str() {
                    Some("Audio/Sink") => Class::Output,
                    Some("Audio/Source") => Class::Input,
                    Some("Stream/Output/Audio") => Class::App,
                    _ => continue,
                };
                let Some(id) = o["id"].as_u64() else { continue };
                let name = props["node.name"].as_str().unwrap_or_default().to_string();
                let label = [
                    &props["node.description"],
                    &props["application.name"],
                    &props["node.nick"],
                ]
                .iter()
                .find_map(|v| v.as_str())
                .unwrap_or(&name)
                .to_string();
                dump.nodes.push(DumpNode {
                    id: id as u32,
                    class,
                    name,
                    label,
                });
            }
            Some("PipeWire:Interface:Metadata") if o["props"]["metadata.name"] == "default" => {
                for entry in o["metadata"].as_array().into_iter().flatten() {
                    let value = entry["value"]["name"].as_str().unwrap_or_default().to_string();
                    match entry["key"].as_str() {
                        Some("default.audio.sink") => dump.default_sink = value,
                        Some("default.audio.source") => dump.default_source = value,
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }
    Ok(dump)
}

/// `wpctl get-volume <id>`: "Volume: 0.47" or "Volume: 0.47 [MUTED]".
pub fn parse_volume(output: &str) -> Option<(f32, bool)> {
    let rest = output.trim().strip_prefix("Volume: ")?;
    let volume = rest.split_whitespace().next()?.parse().ok()?;
    Some((volume, rest.contains("[MUTED]")))
}

fn snapshot() -> Result<Snapshot, String> {
    let dump = system::run_blocking("pw-dump", &[], None)?;
    let Dump {
        nodes,
        default_sink,
        default_source,
    } = parse_dump(&dump)?;
    let mut snap = Snapshot::default();
    for DumpNode { id, class, name, label } in nodes {
        let (volume, muted) = system::run_blocking("wpctl", &args(&["get-volume", &id.to_string()]), None)
            .ok()
            .and_then(|out| parse_volume(&out))
            .unwrap_or((0.0, false));
        let is_default = match class {
            Class::Output => name == default_sink,
            Class::Input => name == default_source,
            Class::App => false,
        };
        let node = Node {
            id,
            label,
            name,
            is_default,
            volume,
            muted,
        };
        match class {
            Class::Output => snap.outputs.push(node),
            Class::Input => snap.inputs.push(node),
            Class::App => snap.apps.push(node),
        }
    }
    for list in [&mut snap.outputs, &mut snap.inputs, &mut snap.apps] {
        list.sort_by(|a, b| b.is_default.cmp(&a.is_default).then(a.label.cmp(&b.label)));
    }
    Ok(snap)
}

fn refresh() -> Task<Msg> {
    Task::perform(system::spawn(snapshot), |r| {
        Msg::Refreshed(r.unwrap_or_else(|| Err("pw-dump stopped unexpectedly".into())))
    })
}

fn wpctl(list: Vec<String>) -> Task<Msg> {
    Task::perform(system::run("wpctl", list, None), |r| Msg::Done(r.map(|_| ())))
}

fn device_glyph(node: &Node, input: bool) -> &'static str {
    if input {
        "󰍬"
    } else if node.name.starts_with("bluez") {
        "󰋋"
    } else {
        "󰓃"
    }
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return refresh(),
            Msg::Refreshed(Ok(mut snapshot)) => {
                // Keep showing the dragged value until it is written.
                if let Some((id, volume)) = self.dragging {
                    for n in snapshot
                        .outputs
                        .iter_mut()
                        .chain(&mut snapshot.inputs)
                        .chain(&mut snapshot.apps)
                    {
                        if n.id == id {
                            n.volume = volume;
                        }
                    }
                }
                self.snapshot = Some(snapshot);
            }
            Msg::Refreshed(Err(e)) => self.error = Some(e),
            Msg::SetDefault(id) => {
                self.busy = true;
                return wpctl(vec!["set-default".into(), id.to_string()]);
            }
            Msg::Volume(id, volume) => {
                self.dragging = Some((id, volume));
                if let Some(snap) = &mut self.snapshot {
                    for n in snap.outputs.iter_mut().chain(&mut snap.inputs).chain(&mut snap.apps) {
                        if n.id == id {
                            n.volume = volume;
                        }
                    }
                }
            }
            Msg::VolumeCommit => {
                if let Some((id, volume)) = self.dragging.take() {
                    return wpctl(vec!["set-volume".into(), id.to_string(), format!("{volume:.2}")]);
                }
            }
            Msg::SetMute(id, muted) => {
                return wpctl(vec![
                    "set-mute".into(),
                    id.to_string(),
                    if muted { "1" } else { "0" }.into(),
                ]);
            }
            Msg::Done(result) => {
                self.busy = false;
                self.error = result.err();
                return refresh();
            }
        }
        Task::none()
    }

    /// `max_volume` is the shell's volume ceiling in percent.
    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>, max_volume: i64) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(snap) = &self.snapshot else {
            return ui::section(body, "Output", vec![ui::note("Loading…")]);
        };
        let max = max_volume.max(1) as f32 / 100.0;
        body = ui::section(
            body,
            "Output",
            self.devices(&snap.outputs, false, max, "No output devices"),
        );
        body = ui::section(body, "Input", self.devices(&snap.inputs, true, max, "No input devices"));
        let mut apps: Vec<Element<'a, Msg>> = snap
            .apps
            .iter()
            .map(|n| volume_row("󰎆", n.label.clone(), n, max))
            .collect();
        if apps.is_empty() {
            apps.push(ui::note("Nothing is playing"));
        }
        ui::section(body, "Apps", apps)
    }

    /// The device list, then the volume of the default device.
    fn devices<'a>(&'a self, nodes: &'a [Node], input: bool, max: f32, empty: &'a str) -> Vec<Element<'a, Msg>> {
        if nodes.is_empty() {
            return vec![ui::note(empty)];
        }
        let mut rows: Vec<Element<'a, Msg>> = nodes
            .iter()
            .map(|n| {
                let control = if n.is_default {
                    text("In use").size(13).color(style::FG_MUTED).into()
                } else {
                    ui::action("Use", (!self.busy).then_some(Msg::SetDefault(n.id)), Action::Primary)
                };
                ui::item(device_glyph(n, input), n.label.clone(), String::new(), vec![control])
            })
            .collect();
        if let Some(default) = nodes.iter().find(|n| n.is_default) {
            // The switch is on while the sound is on; off mutes.
            rows.push(volume_row(if input { "󰍬" } else { "󰕾" }, "Volume".into(), default, max));
        }
        rows
    }
}

/// A volume slider with its label, percentage and mute switch.
fn volume_row<'a>(glyph: &'static str, label: String, n: &Node, max: f32) -> Element<'a, Msg> {
    let id = n.id;
    let bar = slider(0.0..=max, n.volume.min(max), move |v| Msg::Volume(id, v))
        .on_release(Msg::VolumeCommit)
        .step(0.01_f32)
        .width(Length::FillPortion(3));
    let line = row![
        text(glyph).font(style::GLYPH_FONT).size(18).width(26).center(),
        text(label).size(14).color(style::FG).width(Length::FillPortion(2)),
        bar,
        text(format!("{}%", (n.volume * 100.0).round()))
            .size(13)
            .color(style::FG_MUTED)
            .width(48),
        toggler(!n.muted).on_toggle(move |on| Msg::SetMute(id, !on)),
    ]
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_nodes_and_defaults_from_pw_dump() {
        let json = r#"[
          {"id": 144, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Sink",
            "node.name": "bluez_output.CC_22.1", "node.description": "Efe’s AirPods Pro"}}},
          {"id": 75, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Audio/Source",
            "node.name": "alsa_input.pci", "node.description": "Built-in Audio"}}},
          {"id": 60, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Stream/Output/Audio",
            "node.name": "Firefox", "application.name": "Firefox"}}},
          {"id": 30, "type": "PipeWire:Interface:Node", "info": {"props": {"media.class": "Video/Source"}}},
          {"id": 1, "type": "PipeWire:Interface:Metadata", "props": {"metadata.name": "default"},
            "metadata": [{"key": "default.audio.sink", "value": {"name": "bluez_output.CC_22.1"}},
                         {"key": "default.audio.source", "value": {"name": "alsa_input.pci"}}]}
        ]"#;
        let dump = parse_dump(json).unwrap();
        assert_eq!(dump.nodes.len(), 3);
        let first = DumpNode {
            id: 144,
            class: Class::Output,
            name: "bluez_output.CC_22.1".into(),
            label: "Efe’s AirPods Pro".into(),
        };
        assert_eq!(dump.nodes[0], first);
        assert_eq!(dump.nodes[2].class, Class::App);
        assert_eq!(dump.nodes[2].label, "Firefox");
        assert_eq!(dump.default_sink, "bluez_output.CC_22.1");
        assert_eq!(dump.default_source, "alsa_input.pci");
        assert!(parse_dump("nope").is_err());
    }

    #[test]
    fn reads_wpctl_volume() {
        assert_eq!(parse_volume("Volume: 0.47\n"), Some((0.47, false)));
        assert_eq!(parse_volume("Volume: 1.00 [MUTED]"), Some((1.0, true)));
        assert_eq!(parse_volume("error"), None);
    }
}
