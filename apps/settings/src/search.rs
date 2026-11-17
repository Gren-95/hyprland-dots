//! Settings search: which panels and settings match the text typed in the
//! sidebar search field. Like GNOME Settings, the sidebar then lists the
//! matching panels, with the matching settings under each.

use crate::schema::{Control, PANELS, Panel, Section, Setting};

/// One panel in the results.
pub struct PanelMatches {
    pub panel: usize,
    /// The settings that match, in panel order; empty when the panel's own
    /// name matches, as the panel then stands for all of them.
    pub settings: Vec<&'static Setting>,
}

fn contains_all(haystack: &str, query: &str) -> bool {
    let haystack = haystack.to_lowercase();
    query
        .split_whitespace()
        .all(|word| haystack.contains(&word.to_lowercase()))
}

/// Every word of the query must appear (case-insensitive) in the setting's
/// label, help text, choice labels, section title or panel title.
pub fn matches(query: &str, panel: &Panel, section: &Section, setting: &Setting) -> bool {
    let mut haystack = format!("{} {} {} {}", setting.label, setting.help, section.title, panel.title);
    match setting.control {
        Control::Choice(options) => options.iter().for_each(|(_, label)| {
            haystack.push(' ');
            haystack.push_str(label);
        }),
        Control::Flags(flags) => flags.iter().for_each(|(_, label)| {
            haystack.push(' ');
            haystack.push_str(label);
        }),
        Control::Toggles(toggles) => toggles.iter().for_each(|t| {
            haystack.push(' ');
            haystack.push_str(t.label);
        }),
        Control::Pair { options, .. } => options.iter().for_each(|(_, label)| {
            haystack.push(' ');
            haystack.push_str(label);
        }),
        _ => {}
    }
    contains_all(&haystack, query)
}

/// Matching panels in sidebar order; panels without a match are left out.
/// An empty query matches nothing.
pub fn search(query: &str) -> Vec<PanelMatches> {
    if query.trim().is_empty() {
        return Vec::new();
    }
    PANELS
        .iter()
        .enumerate()
        .filter_map(|(i, panel)| {
            if contains_all(&format!("{} {} {}", panel.title, panel.id, panel.keywords), query) {
                return Some(PanelMatches {
                    panel: i,
                    settings: Vec::new(),
                });
            }
            let settings: Vec<_> = panel
                .sections
                .iter()
                .flat_map(|section| section.settings.iter().filter(|s| matches(query, panel, section, s)))
                .collect();
            (!settings.is_empty()).then_some(PanelMatches { panel: i, settings })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn files(query: &str) -> Vec<&'static str> {
        search(query)
            .iter()
            .flat_map(|m| m.settings.iter().map(|s| s.file))
            .collect()
    }

    #[test]
    fn empty_query_finds_nothing() {
        assert!(search("").is_empty());
        assert!(search("   ").is_empty());
    }

    #[test]
    fn finds_by_label_case_insensitive() {
        assert!(files("ACCENT").contains(&"accent-primary"));
        assert!(files("24-hour").contains(&"clock-24h"));
    }

    #[test]
    fn finds_by_help_section_and_choice_labels() {
        assert!(files("°F").contains(&"weather-fahrenheit"));
        assert!(files("auto-dismiss").contains(&"notif-auto-expire-delay"));
        assert!(files("top right").contains(&"toast-position"));
        assert!(files("vpn").contains(&"event-toasts.json"));
    }

    #[test]
    fn every_word_must_match() {
        let found = files("volume step");
        assert!(found.contains(&"volume-step"));
        assert!(!found.contains(&"osd-duration"));
        assert!(files("volume nonsenseword").is_empty());
    }

    #[test]
    fn a_matching_panel_name_lists_the_panel_alone() {
        let groups = search("notif");
        assert_eq!(groups.len(), 1);
        assert_eq!(PANELS[groups[0].panel].id, "notifications");
        assert!(groups[0].settings.is_empty());
        // Words from the panel name and a setting together find the setting.
        let found = files("bar height");
        assert_eq!(found, ["bar-height"]);
    }

    #[test]
    fn finds_panels_by_keyword() {
        let ids: Vec<_> = search("wifi").iter().map(|m| PANELS[m.panel].id).collect();
        assert_eq!(ids, ["network"]);
        let ids: Vec<_> = search("airpods").iter().map(|m| PANELS[m.panel].id).collect();
        assert_eq!(ids, ["bluetooth"]);
        let ids: Vec<_> = search("headphones").iter().map(|m| PANELS[m.panel].id).collect();
        assert_eq!(ids, ["sound", "bluetooth"]);
    }

    #[test]
    fn groups_by_panel_in_order() {
        let groups = search("width");
        let panels: Vec<_> = groups.iter().map(|m| PANELS[m.panel].id).collect();
        assert_eq!(panels, ["bar", "notifications"]);
    }
}
