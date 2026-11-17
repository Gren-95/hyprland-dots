//! The Quickshell settings store: one small file per setting under
//! ~/.config/quickshell/settings/, the format `Settings.qml` reads and writes.
//! Quickshell watches the files, so a write here updates the shell live.
//!
//! Formats, matching `Settings.qml` `_parse` / `_serialize`:
//! - bool: "1" is true, anything else false
//! - int / real: the number as text
//! - text: the raw text, one trailing newline dropped
//! - json: JSON (pretty-printed on write)

use std::fs;
use std::io;
#[cfg(test)]
use std::path::Path;
use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Bool(bool),
    Int(i64),
    Real(f64),
    Text(String),
    Json(serde_json::Value),
}

/// The type a setting's file holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Bool,
    Int,
    Real,
    Text,
    Json,
}

impl Value {
    #[cfg(test)]
    pub fn kind(&self) -> Kind {
        match self {
            Value::Bool(_) => Kind::Bool,
            Value::Int(_) => Kind::Int,
            Value::Real(_) => Kind::Real,
            Value::Text(_) => Kind::Text,
            Value::Json(_) => Kind::Json,
        }
    }

    /// Parse file text as `kind`; None when it is not a valid value.
    pub fn parse(kind: Kind, text: &str) -> Option<Value> {
        match kind {
            Kind::Bool => Some(Value::Bool(text.trim() == "1")),
            Kind::Int => text.trim().parse().ok().map(Value::Int),
            Kind::Real => text
                .trim()
                .parse::<f64>()
                .ok()
                .filter(|n| n.is_finite())
                .map(Value::Real),
            Kind::Text => Some(Value::Text(text.strip_suffix('\n').unwrap_or(text).to_string())),
            Kind::Json => serde_json::from_str(text).ok().map(Value::Json),
        }
    }

    pub fn serialize(&self) -> String {
        match self {
            Value::Bool(b) => if *b { "1" } else { "0" }.to_string(),
            Value::Int(n) => n.to_string(),
            Value::Real(n) => format_real(*n),
            Value::Text(s) => s.clone(),
            Value::Json(v) => serde_json::to_string_pretty(v).unwrap_or_default(),
        }
    }
}

/// Shortest text that reads back as the same number ("1" not "1.0", and no
/// float noise like "0.30000000000000004" from slider steps).
fn format_real(n: f64) -> String {
    let rounded = (n * 1000.0).round() / 1000.0;
    let text = format!("{rounded:.3}");
    text.trim_end_matches('0').trim_end_matches('.').to_string()
}

pub struct Store {
    dir: PathBuf,
}

impl Store {
    pub fn new(dir: PathBuf) -> Self {
        Store { dir }
    }

    /// ~/.config/quickshell/settings (honours XDG_CONFIG_HOME).
    pub fn default_dir() -> PathBuf {
        let config = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home().join(".config"));
        config.join("quickshell").join("settings")
    }

    /// The stored value, or None when the file is missing or invalid (the
    /// shell then uses its default).
    pub fn read(&self, file: &str, kind: Kind) -> Option<Value> {
        let text = fs::read_to_string(self.dir.join(file)).ok()?;
        Value::parse(kind, &text)
    }

    /// Write atomically: a temporary file in the same directory, then rename,
    /// so the shell never reads a half-written value.
    pub fn write(&self, file: &str, value: &Value) -> io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let tmp = self.dir.join(format!(".{file}.tmp"));
        fs::write(&tmp, value.serialize())?;
        fs::rename(&tmp, self.dir.join(file))
    }

    #[cfg(test)]
    pub fn dir(&self) -> &Path {
        &self.dir
    }
}

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store(name: &str) -> Store {
        let dir = std::env::temp_dir().join(format!("settings-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        Store::new(dir)
    }

    #[test]
    fn parses_values_like_settings_qml() {
        assert_eq!(Value::parse(Kind::Bool, "1\n"), Some(Value::Bool(true)));
        assert_eq!(Value::parse(Kind::Bool, "0"), Some(Value::Bool(false)));
        assert_eq!(Value::parse(Kind::Bool, "yes"), Some(Value::Bool(false)));
        assert_eq!(Value::parse(Kind::Int, " 42\n"), Some(Value::Int(42)));
        assert_eq!(Value::parse(Kind::Int, "x"), None);
        assert_eq!(Value::parse(Kind::Real, "1.25"), Some(Value::Real(1.25)));
        assert_eq!(Value::parse(Kind::Real, "inf"), None);
        assert_eq!(Value::parse(Kind::Text, "a b\n"), Some(Value::Text("a b".into())));
        assert_eq!(Value::parse(Kind::Text, "a\n\n"), Some(Value::Text("a\n".into())));
        assert_eq!(
            Value::parse(Kind::Json, "{\"a\": true}"),
            Some(Value::Json(serde_json::json!({"a": true})))
        );
        assert_eq!(Value::parse(Kind::Json, "{"), None);
    }

    #[test]
    fn serializes_values_like_settings_qml() {
        assert_eq!(Value::Bool(true).serialize(), "1");
        assert_eq!(Value::Bool(false).serialize(), "0");
        assert_eq!(Value::Int(-3).serialize(), "-3");
        assert_eq!(Value::Real(1.0).serialize(), "1");
        assert_eq!(Value::Real(0.1 + 0.2).serialize(), "0.3");
        assert_eq!(Value::Real(1.25).serialize(), "1.25");
        assert_eq!(Value::Text("Iosevka".into()).serialize(), "Iosevka");
    }

    #[test]
    fn round_trips_through_files() {
        let store = temp_store("roundtrip");
        assert_eq!(store.read("bar-height", Kind::Int), None);
        store.write("bar-height", &Value::Int(40)).unwrap();
        assert_eq!(store.read("bar-height", Kind::Int), Some(Value::Int(40)));
        let flags = Value::Json(serde_json::json!({"charger": true, "vpn": false}));
        store.write("event-toasts.json", &flags).unwrap();
        assert_eq!(store.read("event-toasts.json", Kind::Json), Some(flags));
        assert!(!store.dir().join(".bar-height.tmp").exists());
        fs::remove_dir_all(store.dir()).unwrap();
    }
}
