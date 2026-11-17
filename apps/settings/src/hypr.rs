//! Hyprland settings the app owns. They are kept in
//! ~/.config/hypr/settings.json, rendered to ~/.config/hypr/settings.lua
//! (loaded last by hyprland.lua, so it wins over the modules and HyprMod)
//! and applied to the running Hyprland with `hyprctl eval`. Both files are
//! gitignored: they are this machine's choices, not part of the dots.
//! Anything not saved yet is read from the running Hyprland, so the app
//! starts from what is in effect.

use std::fs;
use std::io;
use std::path::PathBuf;

use serde_json::{Value as Json, json};

use crate::system::{self, args};

#[derive(Debug, Clone, PartialEq)]
pub struct Keyboard {
    /// (layout, variant) pairs, first is the default.
    pub layouts: Vec<(String, String)>,
    /// XKB option that switches layouts, e.g. "grp:alt_shift_toggle"; empty
    /// for none.
    pub switch: String,
    /// XKB option for Caps Lock, e.g. "caps:escape"; empty for normal.
    pub caps: String,
    /// Other XKB options found in the config, kept as they are.
    pub other_options: Vec<String>,
    pub numlock: bool,
    /// Milliseconds before a held key repeats.
    pub repeat_delay: i64,
    /// Repeats per second.
    pub repeat_rate: i64,
}

fn dir() -> PathBuf {
    crate::store::home().join(".config/hypr")
}

/// A value of `hyprctl getoption <name> -j`.
fn getoption(name: &str) -> Option<Json> {
    let out = system::run_blocking("hyprctl", &args(&["getoption", name, "-j"]), None).ok()?;
    let v: Json = serde_json::from_str(&out).ok()?;
    ["str", "int", "bool", "float"].iter().find_map(|k| v.get(*k).cloned())
}

fn option_str(name: &str) -> String {
    getoption(name)
        .and_then(|v| v.as_str().map(String::from))
        .unwrap_or_default()
}

/// Split a comma list, keeping empty entries (a layout without a variant).
fn split_list(text: &str) -> Vec<String> {
    if text.is_empty() {
        Vec::new()
    } else {
        text.split(',').map(|s| s.trim().to_string()).collect()
    }
}

/// Sort XKB options into the switch option, the Caps Lock option and the rest.
pub fn sort_options(options: &str) -> (String, String, Vec<String>) {
    let (mut switch, mut caps, mut other) = (String::new(), String::new(), Vec::new());
    for o in options.split(',').map(str::trim).filter(|o| !o.is_empty()) {
        if o.starts_with("grp:") {
            switch = o.to_string();
        } else if o.starts_with("caps:") || o == "ctrl:nocaps" || o == "ctrl:swapcaps" {
            caps = o.to_string();
        } else {
            other.push(o.to_string());
        }
    }
    (switch, caps, other)
}

/// Pair layouts with variants (missing variants are empty).
pub fn pair_layouts(layouts: &str, variants: &str) -> Vec<(String, String)> {
    let variants = split_list(variants);
    split_list(layouts)
        .into_iter()
        .enumerate()
        .filter(|(_, l)| !l.is_empty())
        .map(|(i, l)| (l, variants.get(i).cloned().unwrap_or_default()))
        .collect()
}

impl Keyboard {
    /// What the running Hyprland uses.
    fn live() -> Keyboard {
        let (switch, caps, other_options) = sort_options(&option_str("input:kb_options"));
        Keyboard {
            layouts: pair_layouts(&option_str("input:kb_layout"), &option_str("input:kb_variant")),
            switch,
            caps,
            other_options,
            numlock: getoption("input:numlock_by_default")
                .and_then(|v| v.as_bool())
                .unwrap_or(false),
            repeat_delay: getoption("input:repeat_delay").and_then(|v| v.as_i64()).unwrap_or(600),
            repeat_rate: getoption("input:repeat_rate").and_then(|v| v.as_i64()).unwrap_or(25),
        }
    }

    fn from_json(v: &Json) -> Option<Keyboard> {
        Some(Keyboard {
            layouts: v["layouts"]
                .as_array()?
                .iter()
                .filter_map(|p| Some((p[0].as_str()?.to_string(), p[1].as_str()?.to_string())))
                .collect(),
            switch: v["switch"].as_str()?.to_string(),
            caps: v["caps"].as_str()?.to_string(),
            other_options: v["other_options"]
                .as_array()?
                .iter()
                .filter_map(|o| o.as_str().map(String::from))
                .collect(),
            numlock: v["numlock"].as_bool()?,
            repeat_delay: v["repeat_delay"].as_i64()?,
            repeat_rate: v["repeat_rate"].as_i64()?,
        })
    }

    fn to_json(&self) -> Json {
        json!({
            "layouts": self.layouts.iter().map(|(l, v)| json!([l, v])).collect::<Vec<_>>(),
            "switch": self.switch,
            "caps": self.caps,
            "other_options": self.other_options,
            "numlock": self.numlock,
            "repeat_delay": self.repeat_delay,
            "repeat_rate": self.repeat_rate,
        })
    }

    fn options(&self) -> String {
        [&self.switch, &self.caps]
            .into_iter()
            .chain(self.other_options.iter())
            .filter(|o| !o.is_empty())
            .cloned()
            .collect::<Vec<_>>()
            .join(",")
    }

    /// The Lua that sets these values.
    pub fn lua(&self) -> Result<String, String> {
        let layouts: Vec<&str> = self.layouts.iter().map(|(l, _)| l.as_str()).collect();
        let variants: Vec<&str> = self.layouts.iter().map(|(_, v)| v.as_str()).collect();
        let (layouts, variants, options) = (layouts.join(","), variants.join(","), self.options());
        for text in [&layouts, &variants, &options] {
            // XKB names only; nothing that could end the Lua string.
            if !text.chars().all(|c| c.is_ascii_alphanumeric() || "_-:,()".contains(c)) {
                return Err(format!("unexpected characters in keyboard setting: {text}"));
            }
        }
        Ok(format!(
            "hl.config({{\n    input = {{\n        kb_layout = \"{layouts}\",\n        kb_variant = \"{variants}\",\n        kb_options = \"{options}\",\n        numlock_by_default = {},\n        repeat_delay = {},\n        repeat_rate = {},\n    }},\n}})\n",
            self.numlock, self.repeat_delay, self.repeat_rate
        ))
    }
}

/// Everything the app sets in Hyprland.
#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    pub keyboard: Keyboard,
}

impl Settings {
    /// The saved settings, with what is not saved yet read from Hyprland.
    pub fn load() -> Settings {
        let saved: Json = fs::read_to_string(dir().join("settings.json"))
            .ok()
            .and_then(|t| serde_json::from_str(&t).ok())
            .unwrap_or(Json::Null);
        Settings {
            keyboard: Keyboard::from_json(&saved["keyboard"]).unwrap_or_else(Keyboard::live),
        }
    }

    fn lua(&self) -> Result<String, String> {
        Ok(format!(
            "-- Written by the settings app (apps/settings): its Hyprland choices on this\n-- machine. Loaded last by hyprland.lua. Gitignored; edit it in the app.\n\n{}",
            self.keyboard.lua()?
        ))
    }

    /// Save both files, then apply the Lua to the running Hyprland.
    pub async fn apply(self) -> Result<(), String> {
        let lua = self.lua()?;
        write(
            &dir().join("settings.json"),
            &serde_json::to_string_pretty(&json!({"keyboard": self.keyboard.to_json()})).unwrap_or_default(),
        )
        .map_err(|e| format!("Could not save settings.json: {e}"))?;
        write(&dir().join("settings.lua"), &lua).map_err(|e| format!("Could not save settings.lua: {e}"))?;
        system::run("hyprctl", vec!["eval".into(), lua], None).await.map(|_| ())
    }
}

fn write(path: &PathBuf, text: &str) -> io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, text)?;
    fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Keyboard {
        Keyboard {
            layouts: vec![("ee".into(), "nodeadkeys".into()), ("us".into(), String::new())],
            switch: "grp:alt_shift_toggle".into(),
            caps: "caps:escape".into(),
            other_options: vec!["compose:ralt".into()],
            numlock: true,
            repeat_delay: 300,
            repeat_rate: 25,
        }
    }

    #[test]
    fn sorts_xkb_options() {
        let (switch, caps, other) = sort_options("grp:win_space_toggle, caps:escape,compose:ralt");
        assert_eq!(switch, "grp:win_space_toggle");
        assert_eq!(caps, "caps:escape");
        assert_eq!(other, ["compose:ralt"]);
        assert_eq!(sort_options(""), (String::new(), String::new(), vec![]));
        assert_eq!(sort_options("ctrl:nocaps").1, "ctrl:nocaps");
    }

    #[test]
    fn pairs_layouts_with_variants() {
        assert_eq!(
            pair_layouts("ee", "nodeadkeys"),
            [("ee".to_string(), "nodeadkeys".to_string())]
        );
        assert_eq!(
            pair_layouts("ee,us", "nodeadkeys"),
            [("ee".into(), "nodeadkeys".into()), ("us".into(), String::new())]
        );
        assert!(pair_layouts("", "").is_empty());
    }

    #[test]
    fn renders_lua() {
        let lua = sample().lua().unwrap();
        assert!(lua.contains("kb_layout = \"ee,us\""));
        assert!(lua.contains("kb_variant = \"nodeadkeys,\""));
        assert!(lua.contains("kb_options = \"grp:alt_shift_toggle,caps:escape,compose:ralt\""));
        assert!(lua.contains("numlock_by_default = true"));
        assert!(lua.contains("repeat_delay = 300"));
    }

    #[test]
    fn refuses_text_that_could_break_the_lua() {
        let mut k = sample();
        k.layouts[0].0 = "ee\"}) os.execute(\"x".into();
        assert!(k.lua().is_err());
    }

    #[test]
    fn round_trips_json() {
        let k = sample();
        assert_eq!(Keyboard::from_json(&k.to_json()), Some(k));
        assert_eq!(Keyboard::from_json(&Json::Null), None);
    }
}
