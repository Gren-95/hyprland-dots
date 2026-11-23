//! The smaller sources: VS Code extensions, the tldr page cache, and the
//! dots repo itself (only said, never pulled).

use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use crate::check::Item;
use crate::sys::{self, Log};

// ---- VS Code extensions ----

const MARKETPLACE: &str = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery";

/// `code --list-extensions --show-versions`: (id, version), ids lower case.
pub fn parse_extensions(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter_map(|l| l.trim().split_once('@'))
        .map(|(id, v)| (id.to_lowercase(), v.to_string()))
        .collect()
}

/// "1.147.0" as numbers.
fn version_numbers(v: &str) -> Vec<u64> {
    v.split(['.', '-'])
        .map_while(|p| p.trim_start_matches(['^', '>', '=', ' ']).parse().ok())
        .collect()
}

/// An engine range like "^1.95.0" (the only form extensions use) fits VS
/// Code `code`.
pub fn engine_fits(engine: &str, code: &str) -> bool {
    let need = version_numbers(engine);
    let have = version_numbers(code);
    need.is_empty() || have >= need
}

/// The marketplace answer: for each extension, the newest version that is not
/// a pre-release, is for every platform or Linux x64, and fits VS Code `code`.
pub fn latest_versions(json: &serde_json::Value, code: &str) -> Vec<(String, String)> {
    let exts = json["results"][0]["extensions"].as_array().cloned().unwrap_or_default();
    exts.iter()
        .filter_map(|e| {
            let id = format!(
                "{}.{}",
                e["publisher"]["publisherName"].as_str()?,
                e["extensionName"].as_str()?
            )
            .to_lowercase();
            let version = e["versions"].as_array()?.iter().find_map(|v| {
                let props = v["properties"].as_array().cloned().unwrap_or_default();
                let prop = |key: &str| {
                    props
                        .iter()
                        .find(|p| p["key"] == key)
                        .and_then(|p| p["value"].as_str().map(String::from))
                };
                let platform = v["targetPlatform"].as_str().unwrap_or("linux-x64");
                let ok = prop("Microsoft.VisualStudio.Code.PreRelease").as_deref() != Some("true")
                    && platform == "linux-x64"
                    && prop("Microsoft.VisualStudio.Code.Engine").is_none_or(|e| engine_fits(&e, code));
                ok.then(|| v["version"].as_str().map(String::from)).flatten()
            })?;
            Some((id, version))
        })
        .collect()
}

pub fn vscode() -> Result<Vec<Item>, String> {
    let log = Log::none();
    let code = sys::run(&log, "code", &["--version"])?
        .out
        .lines()
        .next()
        .unwrap_or_default()
        .to_string();
    let installed = parse_extensions(&sys::run(&log, "code", &["--list-extensions", "--show-versions"])?.out);
    if installed.is_empty() {
        return Ok(Vec::new());
    }
    let mut criteria: Vec<serde_json::Value> = installed
        .iter()
        .map(|(id, _)| serde_json::json!({"filterType": 7, "value": id}))
        .collect();
    criteria.push(serde_json::json!({"filterType": 8, "value": "Microsoft.VisualStudio.Code"}));
    // Flags: versions (0x1) with their properties (0x10).
    let body = serde_json::json!({"filters": [{"criteria": criteria, "pageSize": 200}], "flags": 0x11});
    let ran = sys::run(
        &log,
        "curl",
        &[
            "-fsS",
            "--max-time",
            "20",
            "-H",
            "Content-Type: application/json",
            "-H",
            "Accept: application/json;api-version=3.0-preview.1",
            "--data",
            &body.to_string(),
            MARKETPLACE,
        ],
    )?;
    if !ran.ok() {
        return Err(format!("marketplace: {}", ran.err.trim()));
    }
    let json: serde_json::Value = serde_json::from_str(&ran.out).map_err(|e| format!("marketplace: {e}"))?;
    let latest = latest_versions(&json, &code);
    Ok(installed
        .iter()
        .filter_map(|(id, current)| {
            let (_, new) = latest.iter().find(|(l, _)| l == id)?;
            (new != current).then(|| Item::new(id.as_str(), current.as_str(), new.as_str()))
        })
        .collect())
}

// ---- tldr ----

/// The tldr client's page cache (tldr.py: $XDG_CACHE_HOME/tldr).
fn tldr_cache() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| sys::home().join(".cache"))
        .join("tldr")
}

/// Refreshed when older than this.
const TLDR_MAX_AGE: Duration = Duration::from_secs(7 * 24 * 3600);

pub fn tldr() -> Vec<Item> {
    let age = std::fs::metadata(tldr_cache())
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| SystemTime::now().duration_since(t).ok());
    match age {
        None => vec![Item::new("pages", "none", "downloaded")],
        Some(a) if a > TLDR_MAX_AGE => vec![Item::new(
            "pages",
            format!("{} days old", a.as_secs() / 86400),
            "refreshed",
        )],
        Some(_) => Vec::new(),
    }
}

// ---- the dots repo ----

/// The repo `~/.config/scripts` links into.
pub fn dots_repo() -> Option<PathBuf> {
    let scripts = std::fs::canonicalize(sys::home().join(".config/scripts")).ok()?;
    let repo = scripts.parent()?.parent()?.to_path_buf();
    repo.join(".git").exists().then_some(repo)
}

/// `git rev-list --left-right --count HEAD...@{u}`: (ahead, behind).
pub fn parse_ahead_behind(out: &str) -> Option<(u64, u64)> {
    let mut n = out.split_whitespace().map(|x| x.parse::<u64>().ok());
    Some((n.next()??, n.next()??))
}

/// "1 commit", "3 commits".
fn commits(n: u64) -> String {
    if n == 1 {
        "1 commit".into()
    } else {
        format!("{n} commits")
    }
}

/// How the repo stands against its upstream, after a fetch; None when even.
pub fn dots() -> Result<Option<String>, String> {
    let repo = dots_repo().ok_or("~/.config/scripts does not link into a git repo")?;
    let dir = repo.to_string_lossy().into_owned();
    let log = Log::none();
    let fetched = sys::run(&log, "git", &["-C", &dir, "fetch", "-q"])?;
    if !fetched.ok() {
        return Err(format!("could not fetch: {}", fetched.tail(1)));
    }
    let ran = sys::run(
        &log,
        "git",
        &["-C", &dir, "rev-list", "--left-right", "--count", "HEAD...@{u}"],
    )?;
    let (ahead, behind) = parse_ahead_behind(&ran.out).ok_or("the repo follows no upstream branch")?;
    let home = sys::home().to_string_lossy().into_owned();
    let shown = dir.replacen(&home, "~", 1);
    Ok(match (ahead, behind) {
        (0, 0) => None,
        (0, b) => Some(format!("{} behind: git -C {shown} pull", commits(b))),
        (a, 0) => Some(format!("{} not pushed", commits(a))),
        (a, b) => Some(format!("{a} ahead and {b} behind its upstream")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_vscode() {
        assert_eq!(
            parse_extensions("Rust-Lang.rust-analyzer@0.3.2\nbad\n"),
            [("rust-lang.rust-analyzer".to_string(), "0.3.2".to_string())]
        );
        assert!(engine_fits("^1.95.0", "1.147.0"));
        assert!(!engine_fits("^1.150.0", "1.147.0"));
        assert!(engine_fits("*", "1.147.0"));
        let j = serde_json::json!({"results": [{"extensions": [{
        "publisher": {"publisherName": "rust-lang"}, "extensionName": "rust-analyzer",
        "versions": [
            {"version": "0.4.1", "targetPlatform": "linux-x64",
             "properties": [{"key": "Microsoft.VisualStudio.Code.PreRelease", "value": "true"}]},
            {"version": "0.3.9", "targetPlatform": "win32-x64", "properties": []},
            {"version": "0.3.8", "targetPlatform": "linux-x64",
             "properties": [{"key": "Microsoft.VisualStudio.Code.Engine", "value": "^1.200.0"}]},
            {"version": "0.3.7", "targetPlatform": "linux-x64",
             "properties": [{"key": "Microsoft.VisualStudio.Code.Engine", "value": "^1.90.0"}]}
        ]}]}]});
        assert_eq!(
            latest_versions(&j, "1.147.0"),
            [("rust-lang.rust-analyzer".to_string(), "0.3.7".to_string())]
        );
    }

    #[test]
    fn reads_the_repo_state() {
        assert_eq!(parse_ahead_behind("2\t5\n"), Some((2, 5)));
        assert_eq!(parse_ahead_behind(""), None);
    }
}
