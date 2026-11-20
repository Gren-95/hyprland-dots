//! Changed settings panel: every store setting not at its default, with
//! its panel, a way there and a reset; and the per-panel "Reset this panel"
//! row. Reads the window's loaded values, so it follows edits at once.

use std::collections::HashMap;

use crate::cli;
use crate::controls::is_default;
use crate::schema::{Control, PANELS, Panel, Setting};
use crate::store::Value;

/// A changed setting: (panel index, setting).
pub fn changed(values: &HashMap<&'static str, Value>) -> Vec<(usize, &'static Setting)> {
    PANELS
        .iter()
        .enumerate()
        .flat_map(|(i, p)| {
            p.sections
                .iter()
                .flat_map(move |s| s.settings.iter().map(move |st| (i, st)))
        })
        .filter(|(_, s)| !is_default(s, values))
        .collect()
}

/// Whether a panel has a setting away from its default.
pub fn panel_changed(panel: &Panel, values: &HashMap<&'static str, Value>) -> bool {
    panel
        .sections
        .iter()
        .flat_map(|s| s.settings.iter())
        .any(|s| !is_default(s, values))
}

/// A setting's value as people read it: On/Off, a choice's label, or the
/// value itself, shortened.
pub fn shown(s: &Setting, values: &HashMap<&'static str, Value>) -> String {
    let value = values.get(s.file).cloned().unwrap_or_else(|| s.default_value());
    let text = match (&s.control, &value) {
        (Control::Toggles(_), _) => "Some switched".to_string(),
        (_, Value::Bool(b)) => if *b { "On" } else { "Off" }.to_string(),
        (Control::Choice(options), Value::Text(t)) => options
            .iter()
            .find(|(v, _)| v == t)
            .map_or_else(|| t.clone(), |(_, l)| l.to_string()),
        (Control::NumberChoice(options), Value::Int(n)) => options
            .iter()
            .find(|(v, _)| v == n)
            .map_or_else(|| n.to_string(), |(_, l)| l.to_string()),
        _ => cli::show(&value),
    };
    if text.chars().count() > 48 {
        format!("{}…", text.chars().take(47).collect::<String>())
    } else {
        text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_only_changed_settings() {
        let mut values = HashMap::new();
        assert!(changed(&values).is_empty());
        values.insert("bar-height", Value::Int(40));
        values.insert("clock-24h", Value::Bool(true));
        let found: Vec<&str> = changed(&values).iter().map(|(_, s)| s.file).collect();
        assert_eq!(found, ["bar-height"]);
        let bar = PANELS.iter().find(|p| p.id == "bar").unwrap();
        assert!(panel_changed(bar, &values));
        let s = changed(&values)[0].1;
        assert_eq!(shown(s, &values), "40");
    }
}
