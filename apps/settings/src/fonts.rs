//! Installed font families, for the Font setting's search picker.

use crate::system::{self, args};

/// Most matches listed at once.
const MAX_MATCHES: usize = 8;

/// `fc-list : family` lines ("Noto Sans,Noto Sans Regular"): the first name
/// of each family, once each, sorted.
pub fn parse_families(output: &str) -> Vec<String> {
    let mut families: Vec<String> = output
        .lines()
        .filter_map(|l| l.split(',').next())
        .map(str::trim)
        .filter(|f| !f.is_empty())
        .map(String::from)
        .collect();
    families.sort_by_key(|f| f.to_lowercase());
    families.dedup();
    families
}

/// The installed families. The names live for the whole run: iced fonts are
/// named by `&'static str`, and the picker draws each family in itself.
pub fn load() -> Vec<&'static str> {
    let output = system::run_blocking("fc-list", &args(&[":", "family"]), None).unwrap_or_default();
    parse_families(&output)
        .into_iter()
        .map(|f| &*Box::leak(f.into_boxed_str()))
        .collect()
}

/// Families containing every word of the query.
pub fn find<'f>(families: &[&'f str], query: &str) -> Vec<&'f str> {
    let words: Vec<String> = query.split_whitespace().map(str::to_lowercase).collect();
    if words.is_empty() {
        return Vec::new();
    }
    families
        .iter()
        .filter(|f| {
            let name = f.to_lowercase();
            words.iter().all(|w| name.contains(w))
        })
        .take(MAX_MATCHES)
        .copied()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_each_family_once() {
        let out = "Noto Sans,Noto Sans Regular\nIosevka Nerd Font\nnoto sans\nIosevka Nerd Font,Iosevka NF\n\n";
        assert_eq!(parse_families(out), ["Iosevka Nerd Font", "Noto Sans", "noto sans"]);
    }

    #[test]
    fn finds_by_words() {
        let fonts = ["Iosevka Nerd Font", "Iosevka Term", "Noto Sans"];
        assert_eq!(find(&fonts, "iosevka nerd"), ["Iosevka Nerd Font"]);
        assert_eq!(find(&fonts, "iosevka").len(), 2);
        assert!(find(&fonts, " ").is_empty());
    }
}
