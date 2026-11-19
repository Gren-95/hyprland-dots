//! AirPods section of the Bluetooth panel. The patched librepods daemon
//! writes battery and control state to $XDG_RUNTIME_DIR and takes commands
//! on a socket; scripts/airpods.sh wraps that and the audio codec, the same
//! script the shell's Bluetooth flyout uses.

use lucide_iced::bytes as ico;
use std::path::PathBuf;

use iced::Element;
use iced::Length;

use crate::style;
use crate::system::{self, args};
use crate::ui;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AirPods {
    pub mac: String,
    pub name: String,
    /// librepods' command socket exists.
    pub daemon: bool,
    pub left: Option<Bud>,
    pub right: Option<Bud>,
    pub case: Option<Bud>,
    /// 1 off, 2 noise cancellation, 3 transparency, 4 adaptive.
    pub listening_mode: Option<u8>,
    /// The AirPods allow turning noise control off.
    pub allow_off: bool,
    pub conversation: Option<bool>,
    /// Active card profile, e.g. "a2dp-sink".
    pub profile: String,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Bud {
    pub level: u8,
    pub charging: bool,
}

/// What a control in the section asks for.
#[derive(Debug, Clone)]
pub enum Action {
    Mode(&'static str),
    Conversation(bool),
    Codec(&'static str),
    ResetAudio,
}

const MODES: &[(u8, &str, &str)] = &[
    (1, "off", "Off"),
    (2, "anc", "Noise cancellation"),
    (3, "transparency", "Transparency"),
    (4, "adaptive", "Adaptive"),
];
const CODECS: &[(&str, &str, &str)] = &[
    ("aac", "a2dp-sink", "AAC"),
    ("sbc-xq", "a2dp-sink-sbc_xq", "SBC-XQ"),
    ("sbc", "a2dp-sink-sbc", "SBC"),
];

pub fn is_airpods(name: &str) -> bool {
    name.to_lowercase().contains("airpods")
}

fn runtime_dir() -> PathBuf {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
}

fn script() -> String {
    crate::store::home()
        .join(".config/scripts/airpods.sh")
        .to_string_lossy()
        .into_owned()
}

/// librepods-battery.json: the parts it reports as connected, when the file
/// is about this device.
pub fn parse_battery(json: &str, mac: &str) -> (Option<Bud>, Option<Bud>, Option<Bud>) {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return (None, None, None);
    };
    if !v["mac"].as_str().is_some_and(|m| m.eq_ignore_ascii_case(mac)) {
        return (None, None, None);
    }
    let part = |key: &str| {
        let c = &v["components"][key];
        c["connected"].as_bool().filter(|&on| on).map(|_| Bud {
            level: c["level"].as_u64().unwrap_or(0).min(100) as u8,
            charging: c["charging"].as_bool().unwrap_or(false),
        })
    };
    (part("left"), part("right"), part("case"))
}

/// librepods-controls.json: (listening mode, allow off, conversation awareness).
pub fn parse_controls(json: &str) -> (Option<u8>, bool, Option<bool>) {
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else {
        return (None, false, None);
    };
    (
        v["listening_mode"].as_u64().map(|m| m as u8),
        v["allow_off"].as_bool().unwrap_or(false),
        v["conversation_detect"].as_bool(),
    )
}

/// Read everything about the connected AirPods; runs on a background thread.
pub fn read(mac: &str, name: &str) -> AirPods {
    let dir = runtime_dir();
    let battery = std::fs::read_to_string(dir.join("librepods-battery.json")).unwrap_or_default();
    let controls = std::fs::read_to_string(dir.join("librepods-controls.json")).unwrap_or_default();
    let (left, right, case) = parse_battery(&battery, mac);
    let (listening_mode, allow_off, conversation) = parse_controls(&controls);
    let profile = system::run_blocking("bash", &args(&[&script(), "codec-status", mac]), None)
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    AirPods {
        mac: mac.to_string(),
        name: name.to_string(),
        daemon: dir.join("librepods.sock").exists(),
        left,
        right,
        case,
        listening_mode,
        allow_off,
        conversation,
        profile,
    }
}

/// The airpods.sh arguments for an action.
pub fn command(mac: &str, action: &Action) -> Vec<String> {
    let mut list = vec![script()];
    list.extend(match action {
        Action::Mode(mode) => args(&["mode", mode]),
        Action::Conversation(on) => args(&["conversation", if *on { "on" } else { "off" }]),
        Action::Codec(codec) => args(&["codec", mac, codec]),
        Action::ResetAudio => args(&["reset-audio", mac]),
    });
    list
}

fn bud_text(label: &str, bud: Option<Bud>) -> Option<String> {
    bud.map(|b| format!("{label} {}%{}", b.level, if b.charging { " 󱐋" } else { "" }))
}

/// The section's rows; `on_action` turns an action into the panel's message.
pub fn rows<'a, M: Clone + 'a>(a: &'a AirPods, idle: bool, on_action: impl Fn(Action) -> M) -> Vec<Element<'a, M>> {
    let battery: Vec<String> = [
        bud_text("Left", a.left),
        bud_text("Right", a.right),
        bud_text("Case", a.case),
    ]
    .into_iter()
    .flatten()
    .collect();
    // Shown under the AirPods' own row (bluetooth.rs), so the name is not
    // repeated.
    let mut rows = vec![ui::item(
        ico::BATTERY_MEDIUM,
        "Battery".into(),
        if battery.is_empty() {
            "Battery unknown".into()
        } else {
            battery.join(" · ")
        },
        vec![],
    )];
    if !a.daemon {
        rows.push(ui::note(
            "librepods is not running: noise control and conversation awareness need it",
        ));
    } else {
        let modes = MODES
            .iter()
            .filter(|(n, _, _)| *n != 1 || a.allow_off)
            .map(|(n, key, label)| {
                (
                    *label,
                    a.listening_mode == Some(*n),
                    idle.then(|| on_action(Action::Mode(key))),
                )
            })
            .collect();
        rows.push(ui::item(
            ico::EAR,
            "Noise control".into(),
            String::new(),
            vec![ui::choice(modes, Length::Fixed(220.0))],
        ));
        let on = a.conversation.unwrap_or(false);
        // A toggle only ever flips, so its message is known up front.
        let flip = on_action(Action::Conversation(!on));
        let toggle = ui::switch(on, idle.then_some(move |_| flip.clone()));
        rows.push(ui::item(
            ico::MESSAGE_CIRCLE,
            "Conversation awareness".into(),
            "Lowers the volume when you start talking".into(),
            vec![toggle],
        ));
    }
    let codecs = CODECS
        .iter()
        .map(|(key, profile, label)| {
            (
                *label,
                a.profile == *profile,
                idle.then(|| on_action(Action::Codec(key))),
            )
        })
        .collect();
    rows.push(ui::item(
        ico::AUDIO_WAVEFORM,
        "Codec".into(),
        String::new(),
        vec![ui::choice(codecs, Length::Fixed(220.0))],
    ));
    rows.push(ui::item(
        ico::ROTATE_CCW,
        "One bud silent?".into(),
        "Resets the audio connection".into(),
        vec![ui::action(
            "Fix audio",
            idle.then(|| on_action(Action::ResetAudio)),
            style::Action::Normal,
        )],
    ));
    rows
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_airpods_names() {
        assert!(is_airpods("Efe’s AirPods Pro - Find My"));
        assert!(is_airpods("airpods max"));
        assert!(!is_airpods("JBL TUNE510BT"));
    }

    #[test]
    fn reads_connected_parts_of_this_device() {
        let json = r#"{"components":{"case":{"charging":false,"connected":false,"level":0},
            "left":{"charging":true,"connected":true,"level":70},
            "right":{"charging":false,"connected":true,"level":84}},"mac":"CC:22:FE:32:52:E4"}"#;
        let (left, right, case) = parse_battery(json, "cc:22:fe:32:52:e4");
        assert_eq!(
            left,
            Some(Bud {
                level: 70,
                charging: true
            })
        );
        assert_eq!(
            right,
            Some(Bud {
                level: 84,
                charging: false
            })
        );
        assert_eq!(case, None);
        assert_eq!(parse_battery(json, "AA:BB"), (None, None, None));
        assert_eq!(parse_battery("", "AA"), (None, None, None));
    }

    #[test]
    fn reads_controls() {
        assert_eq!(
            parse_controls(r#"{"conversation_detect":false,"listening_mode":3}"#),
            (Some(3), false, Some(false))
        );
        assert_eq!(parse_controls(r#"{"allow_off":true}"#), (None, true, None));
        assert_eq!(parse_controls("garbage"), (None, false, None));
    }

    #[test]
    fn builds_script_commands() {
        let cmd = command("CC:22", &Action::Codec("aac"));
        assert!(cmd[0].ends_with(".config/scripts/airpods.sh"));
        assert_eq!(&cmd[1..], ["codec", "CC:22", "aac"]);
        assert_eq!(&command("CC:22", &Action::Mode("anc"))[1..], ["mode", "anc"]);
        assert_eq!(
            &command("CC:22", &Action::Conversation(true))[1..],
            ["conversation", "on"]
        );
    }
}
