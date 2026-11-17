//! `settings get [key]` and `settings set <key> <value>`: the settings store
//! from scripts. Keys are the store's file names (`bar-height`,
//! `accent-primary`); values are checked against the setting the same way
//! the window's controls limit them.

use crate::schema::{Control, Setting, all_settings};
use crate::store::{Kind, Store, Value};

/// Every key with its setting and type: one per file (a group of switches
/// has a key per switch).
fn keys() -> Vec<(&'static str, &'static Setting, Kind, Value)> {
    all_settings()
        .flat_map(|s| {
            s.files()
                .into_iter()
                .map(move |(file, kind, default)| (file, s, kind, default))
        })
        .collect()
}

/// A value as `get` prints it: true/false, numbers, text, compact JSON.
pub fn show(value: &Value) -> String {
    match value {
        Value::Bool(b) => b.to_string(),
        Value::Json(j) => j.to_string(),
        other => other.serialize(),
    }
}

/// `get`: "key value" lines for every setting, or one value.
pub fn get(store: &Store, key: Option<&str>) -> Result<String, String> {
    let all = keys();
    let read = |file: &str, kind: Kind, default: &Value| store.read(file, kind).unwrap_or_else(|| default.clone());
    match key {
        None => Ok(all
            .iter()
            .map(|(file, _, kind, default)| format!("{file} {}\n", show(&read(file, *kind, default))))
            .collect()),
        Some(key) => {
            let (file, _, kind, default) = all.iter().find(|(f, ..)| *f == key).ok_or_else(|| unknown(key))?;
            Ok(format!("{}\n", show(&read(file, *kind, default))))
        }
    }
}

fn unknown(key: &str) -> String {
    format!("unknown setting: {key} (see settings get)")
}

/// Parse and check a value typed for a setting.
pub fn parse_value(setting: &Setting, kind: Kind, input: &str) -> Result<Value, String> {
    let input = input.trim();
    let value = match kind {
        Kind::Bool => match input.to_lowercase().as_str() {
            "true" | "on" | "yes" | "1" => Value::Bool(true),
            "false" | "off" | "no" | "0" => Value::Bool(false),
            _ => return Err(format!("expected true or false, got {input}")),
        },
        Kind::Json => Value::parse(Kind::Json, input).ok_or_else(|| format!("expected JSON, got {input}"))?,
        _ => Value::parse(kind, input).ok_or_else(|| format!("expected a {}, got {input}", setting.control.name()))?,
    };
    match (&setting.control, &value) {
        (Control::Number { min, max, unit, .. }, Value::Int(n)) if n < min || n > max => {
            Err(format!("{n} is out of range {min}–{max} {unit}").trim_end().into())
        }
        (Control::Scale { min, max, .. }, Value::Real(n)) if *n < *min || *n > *max => {
            Err(format!("{n} is out of range {min}–{max}"))
        }
        (Control::Choice(options), Value::Text(t)) if !options.iter().any(|(v, _)| v == t) => Err(format!(
            "{t} is not one of: {}",
            options.iter().map(|(v, _)| *v).collect::<Vec<_>>().join(", ")
        )),
        (Control::NumberChoice(options), Value::Int(n)) if !options.iter().any(|(v, _)| v == n) => Err(format!(
            "{n} is not one of: {}",
            options
                .iter()
                .map(|(v, _)| v.to_string())
                .collect::<Vec<_>>()
                .join(", ")
        )),
        (Control::Pair { options, none, both }, Value::Text(t))
            if t != none && t != both && !options.iter().any(|(v, _)| v == t) =>
        {
            Err(format!(
                "{t} is not one of: {none}, {}, {}, {both}",
                options[0].0, options[1].0
            ))
        }
        _ => Ok(value),
    }
}

/// `set`: check the value, then write it like the window does.
pub fn set(store: &Store, key: &str, input: &str) -> Result<(), String> {
    let all = keys();
    let (file, setting, kind, _) = all.iter().find(|(f, ..)| *f == key).ok_or_else(|| unknown(key))?;
    let value = parse_value(setting, *kind, input)?;
    store
        .write(file, &value)
        .map_err(|e| format!("could not save {file}: {e}"))?;
    crate::system::after_write(file);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store(name: &str) -> Store {
        let dir = std::env::temp_dir().join(format!("settings-cli-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        Store::new(dir)
    }

    #[test]
    fn sets_and_gets_values() {
        let store = temp_store("roundtrip");
        assert_eq!(get(&store, Some("bar-height")).unwrap(), "36\n");
        set(&store, "bar-height", "40").unwrap();
        assert_eq!(get(&store, Some("bar-height")).unwrap(), "40\n");
        set(&store, "clock-24h", "off").unwrap();
        assert_eq!(get(&store, Some("clock-24h")).unwrap(), "false\n");
        set(&store, "sysmon-show-ram", "no").unwrap();
        assert_eq!(get(&store, Some("sysmon-show-ram")).unwrap(), "false\n");
        assert!(get(&store, None).unwrap().contains("bar-height 40\n"));
    }

    #[test]
    fn refuses_bad_input_without_writing() {
        let store = temp_store("bad");
        assert!(set(&store, "nope", "1").unwrap_err().contains("unknown setting"));
        assert!(set(&store, "bar-height", "999").unwrap_err().contains("out of range"));
        assert!(set(&store, "bar-height", "tall").unwrap_err().contains("expected"));
        assert!(
            set(&store, "accent-primary", "chartreuse")
                .unwrap_err()
                .contains("not one of")
        );
        assert!(set(&store, "clock-24h", "maybe").unwrap_err().contains("true or false"));
        assert!(set(&store, "record-audio", "loud").unwrap_err().contains("not one of"));
        set(&store, "record-audio", "both").unwrap();
        assert_eq!(get(&store, Some("bar-height")).unwrap(), "36\n");
    }
}
