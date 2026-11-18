//! A small on-disk cache for facts that are slow to gather and rarely change
//! (hardware, package counts): ~/.cache/dots-settings/<name>.json holds the
//! value with the key it was made for, and a different key makes it again.

use std::path::PathBuf;
use std::time::UNIX_EPOCH;

use serde_json::{Value as Json, json};

fn path(name: &str) -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| crate::store::home().join(".cache"));
    base.join("dots-settings").join(format!("{name}.json"))
}

/// The value cached under `name` when it was made for `key`; otherwise
/// `make()`, saved for next time.
pub fn cached(name: &str, key: &str, make: impl FnOnce() -> Json) -> Json {
    let file = path(name);
    let saved: Option<Json> = std::fs::read_to_string(&file)
        .ok()
        .and_then(|t| serde_json::from_str(&t).ok());
    if let Some(saved) = saved.filter(|s| s["key"] == key) {
        return saved["value"].clone();
    }
    let value = make();
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(&file, json!({"key": key, "value": value}).to_string());
    value
}

/// When each path last changed, as one key: nanoseconds, "-" for a path
/// that is not there.
pub fn mtimes_key(paths: &[PathBuf]) -> String {
    paths
        .iter()
        .map(|p| {
            std::fs::metadata(p)
                .and_then(|m| m.modified())
                .ok()
                .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
                .map_or("-".to_string(), |d| d.as_nanos().to_string())
        })
        .collect::<Vec<_>>()
        .join(",")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn makes_again_only_for_a_new_key() {
        let dir = std::env::temp_dir().join(format!("dots-settings-cache-{}", std::process::id()));
        // SAFETY: tests in this module are the only ones reading XDG_CACHE_HOME.
        unsafe { std::env::set_var("XDG_CACHE_HOME", &dir) };
        assert_eq!(cached("t", "a", || json!(1)), json!(1));
        assert_eq!(cached("t", "a", || json!(2)), json!(1));
        assert_eq!(cached("t", "b", || json!(3)), json!(3));
        let _ = std::fs::remove_dir_all(dir);
        assert_eq!(mtimes_key(&[PathBuf::from("/nonexistent/x")]), "-");
    }
}
