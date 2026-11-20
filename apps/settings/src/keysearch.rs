//! Key-combo search for the key binds page (ported from the old
//! Quickshell keybinds viewer, which this page replaced): a query made of
//! modifier words and at most one key ("super s", "Super+Shift+S",
//! "ctrl alt del") finds binds on that combo, exact matches first, then
//! binds with more modifiers. Anything else, or a combo nothing has, is a
//! text search.

/// Modifier words people type, with the name the viewer shows.
const MODIFIERS: &[(&str, &str)] = &[
    ("super", "Super"),
    ("win", "Super"),
    ("windows", "Super"),
    ("meta", "Super"),
    ("mod", "Super"),
    ("mainmod", "Super"),
    ("shift", "Shift"),
    ("ctrl", "Ctrl"),
    ("control", "Ctrl"),
    ("alt", "Alt"),
];

/// Other names people type for a key.
const KEY_ALIASES: &[(&str, &str)] = &[
    ("enter", "return"),
    ("esc", "escape"),
    ("del", "delete"),
    ("spacebar", "space"),
    ("printscreen", "prtsc"),
    ("print", "prtsc"),
];

fn norm_key(k: &str) -> String {
    let low = k.to_lowercase();
    KEY_ALIASES
        .iter()
        .find(|(a, _)| *a == low)
        .map_or(low, |(_, v)| v.to_string())
}

/// A key as the panel shows it.
pub fn pretty_key(key: &str) -> String {
    let mut k = key.strip_prefix("XF86").unwrap_or(key).to_string();
    for prefix in ["Audio", "Mon"] {
        if let Some(rest) = k.strip_prefix(prefix) {
            k = rest.to_string();
        }
    }
    if let Some(rest) = k.strip_prefix("Kbd") {
        k = format!("Kbd {rest}");
    }
    k = k.replacen("Raise", "+", 1).replacen("Lower", "-", 1);
    match k.as_str() {
        "Print" => "PrtSc".into(),
        "bracketleft" => "[".into(),
        "bracketright" => "]".into(),
        "grave" => "`".into(),
        "KP_Add" => "Num +".into(),
        "KP_Subtract" => "Num -".into(),
        _ => k,
    }
}

/// A combo query: the modifiers (as shown) and the key, possibly empty.
#[derive(Debug, PartialEq)]
pub struct Combo {
    pub mods: Vec<&'static str>,
    pub key: String,
}

/// The combo a query names, or None when it is a text query (no modifier
/// word, or more than one other word).
pub fn parse_combo_query(query: &str) -> Option<Combo> {
    let tokens: Vec<&str> = query
        .split(|c: char| c.is_whitespace() || c == '+')
        .filter(|t| !t.is_empty())
        .collect();
    let mut mods = Vec::new();
    let mut rest = Vec::new();
    for t in tokens {
        match MODIFIERS.iter().find(|(w, _)| *w == t.to_lowercase()) {
            Some((_, m)) => {
                if !mods.contains(m) {
                    mods.push(*m);
                }
            }
            None => rest.push(t),
        }
    }
    if mods.is_empty() || rest.len() > 1 {
        return None;
    }
    Some(Combo {
        mods,
        key: rest.first().map(|k| norm_key(k)).unwrap_or_default(),
    })
}

/// A bind as the search sees it: modifiers as shown, the key as shown and
/// Hyprland's keysym.
pub struct Entry<'a> {
    pub mods: Vec<&'a str>,
    pub key: String,
    pub raw_key: &'a str,
}

/// 0 = exactly these modifiers and key, 1 = these plus more modifiers,
/// None = no match.
pub fn combo_rank(entry: &Entry, combo: &Combo) -> Option<u8> {
    if combo.mods.iter().any(|m| !entry.mods.contains(m)) {
        return None;
    }
    if !combo.key.is_empty() && norm_key(&entry.key) != combo.key && norm_key(entry.raw_key) != combo.key {
        return None;
    }
    let extra = entry
        .mods
        .iter()
        .filter(|m| !combo.mods.contains(m) && **m != "Caps" && **m != "Mod2")
        .count();
    Some(if extra == 0 { 0 } else { 1 })
}

/// Indexes of the entries matching the combo, exact matches first, the
/// input order kept within each rank.
pub fn filter_by_combo(entries: &[Entry], combo: &Combo) -> Vec<usize> {
    let ranked: Vec<(usize, u8)> = entries
        .iter()
        .enumerate()
        .filter_map(|(i, e)| combo_rank(e, combo).map(|r| (i, r)))
        .collect();
    let exact = ranked.iter().filter(|(_, r)| *r == 0).map(|(i, _)| *i);
    let wider = ranked.iter().filter(|(_, r)| *r == 1).map(|(i, _)| *i);
    exact.chain(wider).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The cases the old viewer's node tests checked.
    fn entries() -> Vec<(Entry<'static>, &'static str)> {
        let e = |mods: Vec<&'static str>, key: &str, raw: &'static str, name: &'static str| {
            (
                Entry {
                    mods,
                    key: key.into(),
                    raw_key: raw,
                },
                name,
            )
        };
        vec![
            e(vec!["Super"], "S", "S", "sound"),
            e(vec!["Shift", "Super"], "S", "S", "screenshot"),
            e(vec!["Ctrl", "Shift", "Super"], "S", "S", "ocr"),
            e(vec!["Super"], "R", "R", "launcher"),
            e(vec!["Ctrl", "Alt"], "Delete", "Delete", "powermenu"),
            e(vec!["Super"], "[", "bracketleft", "prev"),
            e(vec!["Super"], "Return", "Return", "terminal"),
        ]
    }

    fn names(query: &str) -> Vec<&'static str> {
        let list = entries();
        let (es, ns): (Vec<_>, Vec<_>) = list.into_iter().unzip();
        filter_by_combo(&es, &parse_combo_query(query).unwrap())
            .into_iter()
            .map(|i| ns[i])
            .collect()
    }

    #[test]
    fn modifier_words_plus_one_key_parse_as_a_combo() {
        assert_eq!(
            parse_combo_query("super s"),
            Some(Combo {
                mods: vec!["Super"],
                key: "s".into()
            })
        );
        assert_eq!(
            parse_combo_query("Super+Shift+S"),
            Some(Combo {
                mods: vec!["Super", "Shift"],
                key: "s".into()
            })
        );
        assert_eq!(
            parse_combo_query("win enter"),
            Some(Combo {
                mods: vec!["Super"],
                key: "return".into()
            })
        );
        assert_eq!(
            parse_combo_query("ctrl alt"),
            Some(Combo {
                mods: vec!["Ctrl", "Alt"],
                key: String::new()
            })
        );
    }

    #[test]
    fn text_queries_are_not_combos() {
        assert_eq!(parse_combo_query("volume"), None);
        assert_eq!(parse_combo_query("s"), None);
        assert_eq!(parse_combo_query("super open terminal"), None);
    }

    #[test]
    fn super_s_finds_super_s_first_then_wider_combos() {
        assert_eq!(names("super s"), ["sound", "screenshot", "ocr"]);
        assert_eq!(names("super shift s"), ["screenshot", "ocr"]);
    }

    #[test]
    fn key_names_match_the_shown_key_or_the_keysym() {
        assert_eq!(names("super ["), ["prev"]);
        assert_eq!(names("super bracketleft"), ["prev"]);
        assert_eq!(names("super enter"), ["terminal"]);
        assert_eq!(names("ctrl alt del"), ["powermenu"]);
    }

    #[test]
    fn modifiers_only_list_every_bind_using_them() {
        assert_eq!(names("ctrl"), ["ocr", "powermenu"]);
    }

    #[test]
    fn shows_keys_like_the_viewer() {
        assert_eq!(pretty_key("XF86AudioRaiseVolume"), "+Volume");
        assert_eq!(pretty_key("XF86MonBrightnessDown"), "BrightnessDown");
        assert_eq!(pretty_key("bracketleft"), "[");
        assert_eq!(pretty_key("Print"), "PrtSc");
    }
}
