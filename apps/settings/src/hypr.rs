//! Hyprland settings the app owns. They are kept in
//! ~/.config/hypr/settings.json, rendered to ~/.config/hypr/settings.lua
//! (loaded last by hyprland.lua, so it wins over the modules and HyprMod)
//! and applied to the running Hyprland with `hyprctl eval`. Both files are
//! gitignored: they are this machine's choices, not part of the dots.
//! Anything not saved yet is read from the running Hyprland, so the app
//! starts from what is in effect.
//!
//! Window rules are written to settings.lua too but only take effect on a
//! reload: windowrules.rs reloads Hyprland after saving them.

use std::collections::BTreeMap;
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
    // "css" is a list of numbers ("2 2 2 2"), as gaps report themselves.
    ["str", "int", "bool", "float", "css"]
        .iter()
        .find_map(|k| v.get(*k).cloned())
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
    /// Other options the user changed, by Hyprland name
    /// ("input:touchpad:tap_to_click"). Options not here keep the value of
    /// the tracked config.
    pub options: BTreeMap<String, Json>,
    /// Key binds moved to other keys, by their original combo
    /// ("SUPER + R").
    pub binds: BTreeMap<String, Rebind>,
    /// Window rules made in the app, one per window class.
    pub rules: Vec<WindowRule>,
}

/// A rule for every window of one class: float (at a size), see-through,
/// open on a workspace. Empty fields leave Hyprland's own behaviour.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct WindowRule {
    pub class: String,
    pub float: bool,
    /// "800 600"; only for floating windows.
    pub size: String,
    /// Percent, 10 to 100; None leaves it.
    pub opacity: Option<i64>,
    /// "1" to "10"; empty leaves it.
    pub workspace: String,
}

impl WindowRule {
    fn from_json(v: &Json) -> Option<WindowRule> {
        Some(WindowRule {
            class: v["class"].as_str()?.to_string(),
            float: v["float"].as_bool().unwrap_or(false),
            size: v["size"].as_str().unwrap_or_default().to_string(),
            opacity: v["opacity"].as_i64(),
            workspace: v["workspace"].as_str().unwrap_or_default().to_string(),
        })
    }

    fn to_json(&self) -> Json {
        json!({
            "class": self.class,
            "float": self.float,
            "size": self.size,
            "opacity": self.opacity,
            "workspace": self.workspace,
        })
    }
}

/// A window class a rule can name: letters, digits, dot, dash, underscore.
pub fn valid_class(class: &str) -> bool {
    !class.is_empty() && class.chars().all(|c| c.is_ascii_alphanumeric() || "._-".contains(c))
}

/// A floating size: two whole numbers of pixels, "800 600".
pub fn valid_size(size: &str) -> bool {
    let parts: Vec<&str> = size.split(' ').collect();
    parts.len() == 2
        && parts
            .iter()
            .all(|p| p.parse::<u32>().is_ok_and(|n| (50..=10000).contains(&n)))
}

/// `hl.window_rule` calls for the rules; checked first, since the values
/// end up in Lua source.
pub fn rules_lua(rules: &[WindowRule]) -> Result<String, String> {
    let mut out = String::new();
    for r in rules {
        if !valid_class(&r.class) {
            return Err(format!("not a window class: {}", r.class));
        }
        let mut lines = vec![format!(
            "    match = {{\n        class = \"^({})$\",\n    }},",
            r.class.replace('.', "\\\\.")
        )];
        if r.float {
            lines.push("    float = true,".into());
            if !r.size.is_empty() {
                if !valid_size(&r.size) {
                    return Err(format!("not a window size: {}", r.size));
                }
                lines.push(format!("    size = \"{}\",", r.size));
            }
        }
        if let Some(o) = r.opacity {
            if !(10..=100).contains(&o) {
                return Err(format!("opacity out of range: {o}"));
            }
            lines.push(format!("    opacity = \"{}\",", o as f64 / 100.0));
        }
        if !r.workspace.is_empty() {
            if !r.workspace.parse::<u32>().is_ok_and(|n| (1..=10).contains(&n)) {
                return Err(format!("not a workspace: {}", r.workspace));
            }
            lines.push(format!("    workspace = \"{}\",", r.workspace));
        }
        out.push_str(&format!("hl.window_rule({{\n{}\n}})\n", lines.join("\n")));
    }
    if !out.is_empty() {
        out = format!("\n-- Window rules (Windows panel, window rules)\n{out}");
    }
    Ok(out)
}

/// A key bind on other keys: the new combo, its action (one `hl.dsp.*` call)
/// and the flags it had.
#[derive(Debug, Clone, PartialEq)]
pub struct Rebind {
    pub combo: String,
    pub action: String,
    pub locked: bool,
    pub repeating: bool,
}

/// A combo is modifiers and a key name joined by " + ", from the shortcut
/// panel's own lists; nothing that could end a Lua string.
pub fn valid_combo(combo: &str) -> bool {
    !combo.is_empty() && combo.chars().all(|c| c.is_ascii_alphanumeric() || " +_".contains(c))
}

/// An action as hypr-binds.sh reports it: one `hl.dsp.*(...)` call on one
/// line, taken from the user's own Lua config.
pub fn valid_action(action: &str) -> bool {
    action.starts_with("hl.dsp.") && action.ends_with(')') && !action.contains('\n')
}

fn bind_options(locked: bool, repeating: bool) -> String {
    let mut opts = Vec::new();
    if locked {
        opts.push("locked = true");
    }
    if repeating {
        opts.push("repeating = true");
    }
    if opts.is_empty() {
        String::new()
    } else {
        format!(", {{ {} }}", opts.join(", "))
    }
}

/// `hl.bind` for one bind on the given keys.
pub fn bind_lua(combo: &str, action: &str, locked: bool, repeating: bool) -> Result<String, String> {
    if !valid_combo(combo) || !valid_action(action) {
        return Err(format!("unexpected key bind: {combo} → {action}"));
    }
    Ok(format!(
        "hl.bind(\"{combo}\", {action}{})",
        bind_options(locked, repeating)
    ))
}

/// `hl.unbind` for a combo.
pub fn unbind_lua(combo: &str) -> Result<String, String> {
    if !valid_combo(combo) {
        return Err(format!("unexpected key combo: {combo}"));
    }
    Ok(format!("hl.unbind(\"{combo}\")"))
}

/// The moved binds: each original combo unbound, the action bound to its new
/// keys.
pub fn binds_lua(binds: &BTreeMap<String, Rebind>) -> Result<String, String> {
    let mut out = String::new();
    for (original, b) in binds {
        out.push_str(&format!(
            "{}\n{}\n",
            unbind_lua(original)?,
            bind_lua(&b.combo, &b.action, b.locked, b.repeating)?
        ));
    }
    Ok(if out.is_empty() {
        out
    } else {
        format!("\n-- Key binds moved to other keys.\n{out}")
    })
}

/// A Hyprland option's value now: the saved one, else the running one.
pub fn option_value(settings: &Settings, name: &str) -> Option<Json> {
    settings.options.get(name).cloned().or_else(|| live_option(name))
}

/// What the running Hyprland uses for an option. Empty strings come back
/// as "[[EMPTY]]", which means "".
pub fn live_option(name: &str) -> Option<Json> {
    getoption(name).map(|v| {
        if v == "[[EMPTY]]" {
            Json::String(String::new())
        } else {
            v
        }
    })
}

/// The saved settings.json as it is on disk (Null when there is none).
pub fn saved_json() -> Json {
    fs::read_to_string(dir().join("settings.json"))
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or(Json::Null)
}

/// Replace settings.json with `saved`, write settings.lua from it and
/// reload Hyprland (moved binds only take effect on a reload).
pub fn replace_saved(saved: &Json) -> Result<(), String> {
    write(
        &dir().join("settings.json"),
        &serde_json::to_string_pretty(saved).unwrap_or_default(),
    )
    .map_err(|e| format!("Could not save settings.json: {e}"))?;
    update_blocking(|_| {}, "")?;
    system::run_blocking("hyprctl", &["reload".to_string()], None)
        .map(|_| ())
        .map_err(|e| format!("saved, but Hyprland did not reload: {e}"))
}

impl Settings {
    /// The saved settings, with what is not saved yet read from Hyprland.
    pub fn load() -> Settings {
        let saved = saved_json();
        Settings {
            keyboard: Keyboard::from_json(&saved["keyboard"]).unwrap_or_else(Keyboard::live),
            binds: saved["binds"]
                .as_object()
                .map(|o| {
                    o.iter()
                        .filter_map(|(k, v)| {
                            Some((
                                k.clone(),
                                Rebind {
                                    combo: v["combo"].as_str()?.to_string(),
                                    action: v["action"].as_str()?.to_string(),
                                    locked: v["locked"].as_bool().unwrap_or(false),
                                    repeating: v["repeating"].as_bool().unwrap_or(false),
                                },
                            ))
                        })
                        .collect()
                })
                .unwrap_or_default(),
            options: saved["options"]
                .as_object()
                .map(|o| o.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
                .unwrap_or_default(),
            rules: saved["rules"]
                .as_array()
                .map(|a| a.iter().filter_map(WindowRule::from_json).collect())
                .unwrap_or_default(),
        }
    }

    fn lua(&self) -> Result<String, String> {
        Ok(format!(
            "-- Written by the settings app (apps/settings): its Hyprland choices on this\n-- machine. Loaded last by hyprland.lua. Gitignored; edit it in the app.\n\n{}{}",
            self.keyboard.lua()?,
            options_lua(&self.options)?
        ))
        .and_then(|head| Ok(head + &binds_lua(&self.binds)? + &rules_lua(&self.rules)?))
    }

    fn json(&self) -> Json {
        let binds: serde_json::Map<String, Json> = self
            .binds
            .iter()
            .map(|(k, b)| {
                (
                    k.clone(),
                    json!({"combo": b.combo, "action": b.action, "locked": b.locked, "repeating": b.repeating}),
                )
            })
            .collect();
        let rules: Vec<Json> = self.rules.iter().map(WindowRule::to_json).collect();
        json!({ "keyboard": self.keyboard.to_json(), "options": self.options, "binds": binds, "rules": rules })
    }

    /// The part re-applied on every save. Binds are left out: binding the
    /// same keys again would run the action twice; they change one at a time
    /// through `update`'s extra Lua.
    fn live_lua(&self) -> Result<String, String> {
        Ok(format!("{}{}", self.keyboard.lua()?, options_lua(&self.options)?))
    }
}

/// Change the saved settings and apply them. Each panel changes only its
/// part, on top of what is on disk now, so panels do not undo each other.
pub async fn update(change: impl FnOnce(&mut Settings) + Send + 'static) -> Result<(), String> {
    update_with(change, String::new()).await
}

/// `update`, plus `extra` Lua run on the live Hyprland after it (a key bind
/// moving: the old keys unbound, the new ones bound).
pub async fn update_with(change: impl FnOnce(&mut Settings) + Send + 'static, extra: String) -> Result<(), String> {
    system::spawn(move || update_blocking(change, &extra))
        .await
        .unwrap_or_else(|| Err("saving stopped unexpectedly".into()))
}

/// `update_with` on the calling thread.
pub fn update_blocking(change: impl FnOnce(&mut Settings), extra: &str) -> Result<(), String> {
    let mut settings = Settings::load();
    change(&mut settings);
    write(
        &dir().join("settings.json"),
        &serde_json::to_string_pretty(&settings.json()).unwrap_or_default(),
    )
    .map_err(|e| format!("Could not save settings.json: {e}"))?;
    write(&dir().join("settings.lua"), &settings.lua()?).map_err(|e| format!("Could not save settings.lua: {e}"))?;
    let lua = settings.live_lua()? + extra;
    system::run_blocking("hyprctl", &["eval".to_string(), lua], None).map(|_| ())
}

/// One Lua value: numbers, booleans and plain strings only.
fn lua_value(v: &Json) -> Result<String, String> {
    match v {
        Json::Bool(b) => Ok(b.to_string()),
        Json::Number(n) => Ok(n.to_string()),
        Json::String(s) if s.chars().all(|c| c.is_ascii_alphanumeric() || " _-:,.()".contains(c)) => {
            Ok(format!("\"{s}\""))
        }
        _ => Err(format!("unexpected Hyprland option value: {v}")),
    }
}

/// `hl.config` for options named "a:b:c": nested tables a = { b = { c = … } }.
pub fn options_lua(options: &BTreeMap<String, Json>) -> Result<String, String> {
    if options.is_empty() {
        return Ok(String::new());
    }
    let mut tree = serde_json::Map::new();
    for (name, value) in options {
        let parts: Vec<&str> = name.split(':').collect();
        if parts
            .iter()
            .any(|p| p.is_empty() || !p.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.'))
        {
            return Err(format!("unexpected Hyprland option name: {name}"));
        }
        let mut node = &mut tree;
        for part in &parts[..parts.len() - 1] {
            node = node
                .entry(part.to_string())
                .or_insert_with(|| Json::Object(Default::default()))
                .as_object_mut()
                .ok_or_else(|| format!("{name} clashes with another option"))?;
        }
        node.insert(parts[parts.len() - 1].to_string(), value.clone());
    }
    fn table(map: &serde_json::Map<String, Json>, depth: usize) -> Result<String, String> {
        let pad = "    ".repeat(depth + 1);
        let mut out = String::from("{\n");
        for (key, value) in map {
            let inner = match value {
                Json::Object(m) => table(m, depth + 1)?,
                v => lua_value(v)?,
            };
            out.push_str(&format!("{pad}{key} = {inner},\n"));
        }
        out.push_str(&"    ".repeat(depth));
        out.push('}');
        Ok(out)
    }
    Ok(format!("\nhl.config({})\n", table(&tree, 0)?))
}

fn write(path: &PathBuf, text: &str) -> io::Result<()> {
    // settings.json and settings.lua each get their own temporary file.
    let tmp = path.with_extension(format!(
        "{}.tmp",
        path.extension().and_then(|e| e.to_str()).unwrap_or_default()
    ));
    fs::write(&tmp, text)?;
    fs::rename(&tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn writes_window_rules() {
        let rule = WindowRule {
            class: "org.gnome.Calculator".into(),
            float: true,
            size: "400 600".into(),
            opacity: Some(90),
            workspace: "3".into(),
        };
        let lua = rules_lua(std::slice::from_ref(&rule)).unwrap();
        assert!(lua.contains("class = \"^(org\\\\.gnome\\\\.Calculator)$\","));
        assert!(lua.contains("float = true,\n    size = \"400 600\",\n    opacity = \"0.9\",\n    workspace = \"3\","));
        assert_eq!(rules_lua(&[]).unwrap(), "");
        let bad = |r: WindowRule| rules_lua(&[r]).is_err();
        assert!(bad(WindowRule {
            class: "a\"b".into(),
            ..rule.clone()
        }));
        assert!(bad(WindowRule {
            size: "400".into(),
            ..rule.clone()
        }));
        assert!(bad(WindowRule {
            workspace: "11".into(),
            ..rule.clone()
        }));
        assert!(bad(WindowRule {
            opacity: Some(5),
            ..rule.clone()
        }));
        // Size counts only for a floating window.
        assert!(
            !rules_lua(&[WindowRule {
                float: false,
                size: "x".into(),
                ..rule.clone()
            }])
            .unwrap()
            .contains("size")
        );
        assert_eq!(WindowRule::from_json(&rule.to_json()), Some(rule));
    }

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
        assert_eq!(sort_options("caps:none").1, "caps:none");
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
    fn renders_nested_options() {
        let mut o = BTreeMap::new();
        o.insert("input:sensitivity".to_string(), json!(0.25));
        o.insert("input:touchpad:tap_to_click".to_string(), json!(false));
        o.insert("input:accel_profile".to_string(), json!("flat"));
        let lua = options_lua(&o).unwrap();
        assert!(lua.contains("hl.config({"));
        assert!(lua.contains("    input = {"));
        assert!(lua.contains("        sensitivity = 0.25,"));
        assert!(lua.contains("        accel_profile = \"flat\","));
        assert!(lua.contains("            tap_to_click = false,"));
        assert_eq!(options_lua(&BTreeMap::new()).unwrap(), "");
    }

    #[test]
    fn refuses_bad_option_names_and_values() {
        let mut o = BTreeMap::new();
        o.insert("input:x\") os.execute(\"".to_string(), json!(1));
        assert!(options_lua(&o).is_err());
        let mut o = BTreeMap::new();
        o.insert("input:accel_profile".to_string(), json!("a\"b"));
        assert!(options_lua(&o).is_err());
    }

    #[test]
    fn renders_moved_binds() {
        let mut binds = BTreeMap::new();
        binds.insert(
            "SUPER + R".to_string(),
            Rebind {
                combo: "SUPER + D".into(),
                action: "hl.dsp.global(\"quickshell:spotlight\")".into(),
                locked: false,
                repeating: false,
            },
        );
        let lua = binds_lua(&binds).unwrap();
        assert!(
            lua.contains("hl.unbind(\"SUPER + R\")\nhl.bind(\"SUPER + D\", hl.dsp.global(\"quickshell:spotlight\"))\n")
        );
        assert_eq!(
            bind_lua("XF86AudioMute", "hl.dsp.exec_cmd(\"x\")", true, true).unwrap(),
            "hl.bind(\"XF86AudioMute\", hl.dsp.exec_cmd(\"x\"), { locked = true, repeating = true })"
        );
        assert!(bind_lua("SUPER + \")", "hl.dsp.x()", false, false).is_err());
        assert!(bind_lua("SUPER + R", "os.execute(\"x\")", false, false).is_err());
        assert_eq!(binds_lua(&BTreeMap::new()).unwrap(), "");
    }

    #[test]
    fn round_trips_json() {
        let k = sample();
        assert_eq!(Keyboard::from_json(&k.to_json()), Some(k));
        assert_eq!(Keyboard::from_json(&Json::Null), None);
    }
}
