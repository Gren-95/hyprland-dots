//! Before anything changes: what each source would update, all sources
//! checked at once. Nothing here needs sudo.

use std::thread;

use crate::fisher;
use crate::github;
use crate::steps::Step;
use crate::sys::{self, Log};

const GEAR_LEVER: &str = "it.mijorus.gearlever";

#[derive(Debug, Clone, PartialEq)]
pub enum Found {
    UpToDate,
    /// Something to update: the items, and notes such as "kernel 6.12".
    Updates {
        items: Vec<String>,
        notes: Vec<String>,
    },
    /// Not installed, or not set up.
    Absent(String),
    /// Would go over the GitHub API quota: skipped this run.
    Limited(String),
    /// The check itself failed; the step still runs and reports.
    Failed(String),
}

/// One source's check, with what its update needs from it.
#[derive(Debug, Clone)]
pub struct Check {
    pub step: Step,
    pub found: Found,
    /// Printed under the step (an AppImage without an update channel).
    pub warnings: Vec<String>,
    /// AppImages with an update, by path.
    pub appimages: Vec<String>,
    /// Plugin installs, updates and removals.
    pub fisher: Vec<fisher::Action>,
    /// dnf has unneeded packages to remove.
    pub unneeded: usize,
}

impl Check {
    fn new(step: Step, found: Found) -> Check {
        Check {
            step,
            found,
            warnings: Vec::new(),
            appimages: Vec::new(),
            fisher: Vec::new(),
            unneeded: 0,
        }
    }

    /// The step has work: updates, or a check that could not tell.
    pub fn has_work(&self) -> bool {
        matches!(self.found, Found::Updates { .. } | Found::Failed(_))
    }

    /// How many things it would update (0 when unknown).
    pub fn count(&self) -> usize {
        match &self.found {
            Found::Updates { items, .. } => items.len(),
            _ => 0,
        }
    }
}

fn updates(items: Vec<String>, notes: Vec<String>) -> Found {
    if items.is_empty() && notes.is_empty() {
        Found::UpToDate
    } else {
        Found::Updates { items, notes }
    }
}

/// Every step, checked in parallel, in step order.
pub fn all(steps: &[Step]) -> Vec<Check> {
    thread::scope(|s| {
        let jobs: Vec<_> = steps.iter().map(|&step| s.spawn(move || one(step))).collect();
        jobs.into_iter()
            .zip(steps)
            .map(|(j, &step)| {
                j.join()
                    .unwrap_or_else(|_| Check::new(step, Found::Failed("the check stopped".into())))
            })
            .collect()
    })
}

fn one(step: Step) -> Check {
    if !sys::on_path(step.tool()) {
        return Check::new(step, Found::Absent(format!("{} is not installed", step.tool())));
    }
    let result = match step {
        Step::Dnf => dnf(),
        Step::Firmware => firmware(),
        Step::Flatpak => flatpak(),
        Step::AppImages => return appimages(),
        Step::Npm => npm(),
        Step::Uv => uv(),
        Step::Bun => bun(),
        Step::Fisher => return fisher_check(),
    };
    match result {
        Ok(check) => check,
        Err(e) => Check::new(step, Found::Failed(e)),
    }
}

fn run(program: &str, args: &[&str]) -> Result<sys::Ran, String> {
    sys::run(&Log::none(), program, args)
}

// ---- dnf ----

/// `dnf check-update` lines: "name.arch  version  repo". Returns
/// (name, version) pairs.
pub fn parse_dnf(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let [nevra, version, _repo] = f.as_slice() else {
                return None;
            };
            let (name, _arch) = nevra.rsplit_once('.')?;
            version
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_digit())
                .then(|| (name.to_string(), version.to_string()))
        })
        .collect()
}

fn dnf() -> Result<Check, String> {
    let ran = run("dnf", &["check-update", "-q"])?;
    // 100: updates listed; 0: none.
    let packages = match ran.code {
        0 => Vec::new(),
        100 => parse_dnf(&ran.out),
        _ => return Err(ran.tail(2)),
    };
    let unneeded = run("dnf", &["repoquery", "--unneeded", "-q"])
        .map(|r| r.out.lines().filter(|l| !l.trim().is_empty()).count())
        .unwrap_or(0);
    let mut notes = Vec::new();
    if let Some((_, v)) = packages.iter().find(|(n, _)| n == "kernel" || n == "kernel-core") {
        notes.push(format!("kernel {}", v.split('-').next().unwrap_or(v)));
    }
    if unneeded > 0 {
        notes.push(format!("{unneeded} to remove"));
    }
    let items = packages.into_iter().map(|(n, _)| n).collect();
    let mut check = Check::new(Step::Dnf, updates(items, notes));
    check.unneeded = unneeded;
    Ok(check)
}

// ---- firmware ----

/// `fwupdmgr get-updates --json`: "device version" for each device with a
/// release waiting.
pub fn parse_fwupd(json: &serde_json::Value) -> Vec<String> {
    json["Devices"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|d| {
            let release = d["Releases"].as_array()?.first()?;
            Some(format!(
                "{} {}",
                d["Name"].as_str()?,
                release["Version"].as_str().unwrap_or_default()
            ))
        })
        .collect()
}

fn firmware() -> Result<Check, String> {
    // Read from the metadata already downloaded; the update refreshes it.
    let ran = run("fwupdmgr", &["get-updates", "--json"])?;
    let items = match ran.code {
        0 => parse_fwupd(&serde_json::from_str(&ran.out).map_err(|e| format!("fwupdmgr: {e}"))?),
        2 => Vec::new(),
        _ => return Err(ran.tail(2)),
    };
    Ok(Check::new(Step::Firmware, updates(items, Vec::new())))
}

// ---- Flatpak ----

/// `flatpak remote-ls --updates --columns=application`: the last part of
/// each id ("org.mozilla.firefox" is "firefox").
pub fn parse_flatpak(out: &str) -> Vec<String> {
    out.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(|l| l.rsplit('.').next().unwrap_or(l).to_string())
        .collect()
}

fn flatpak() -> Result<Check, String> {
    let ran = run("flatpak", &["remote-ls", "--updates", "--columns=application"])?;
    if !ran.ok() {
        return Err(ran.tail(2));
    }
    Ok(Check::new(Step::Flatpak, updates(parse_flatpak(&ran.out), Vec::new())))
}

// ---- AppImages (Gear Lever) ----

/// `gearlever --list-installed`: apps without an update channel, and how
/// many check GitHub (one API request each).
pub fn parse_gearlever_installed(out: &str) -> (Vec<String>, u64) {
    let no_channel = out
        .lines()
        .filter(|l| l.contains("[UpdatesNotAvailable]"))
        .filter_map(|l| l.split_whitespace().find(|w| w.to_lowercase().ends_with(".appimage")))
        .map(|p| p.rsplit('/').next().unwrap_or(p).to_string())
        .collect();
    (no_channel, out.matches("GithubUpdater").count() as u64)
}

/// `gearlever --list-updates --json`: the paths with an update.
pub fn parse_gearlever_updates(json: &serde_json::Value) -> Vec<String> {
    json["updates"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|u| u["path"].as_str().map(String::from))
        .collect()
}

fn appimages() -> Check {
    let absent = |why: &str| Check::new(Step::AppImages, Found::Absent(why.into()));
    if !run("flatpak", &["info", GEAR_LEVER]).is_ok_and(|r| r.ok()) {
        return absent("Gear Lever is not installed");
    }
    let gl = |args: &[&str]| {
        let mut all = vec!["run", GEAR_LEVER];
        all.extend_from_slice(args);
        run("flatpak", &all)
    };
    let installed = match gl(&["--list-installed"]) {
        Ok(r) => r.out,
        Err(e) => return Check::new(Step::AppImages, Found::Failed(e)),
    };
    let (no_channel, github_apps) = parse_gearlever_installed(&installed);
    let warnings: Vec<String> = no_channel
        .iter()
        .map(|a| format!("{a} has no update channel: update it by hand"))
        .collect();
    let with_warnings = |found: Found| {
        let mut c = Check::new(Step::AppImages, found);
        c.warnings = warnings.clone();
        c
    };
    if let Err(e) = github::enough(github_apps) {
        return with_warnings(Found::Limited(e));
    }
    let listed = match gl(&["--list-updates", "--json"]) {
        Ok(r) => r,
        Err(e) => return with_warnings(Found::Failed(e)),
    };
    if github::hit_limit(&listed.err) {
        return with_warnings(Found::Limited("GitHub API limit reached".into()));
    }
    let paths = match serde_json::from_str(&listed.out) {
        Ok(j) => parse_gearlever_updates(&j),
        Err(e) => return with_warnings(Found::Failed(format!("Gear Lever: {e}"))),
    };
    let names = paths
        .iter()
        .map(|p| p.rsplit('/').next().unwrap_or(p).to_string())
        .collect();
    let mut check = with_warnings(updates(names, Vec::new()));
    check.appimages = paths;
    check
}

// ---- npm, uv, bun ----

/// `npm outdated -g --json`: "name current → latest".
pub fn parse_npm(json: &serde_json::Value) -> Vec<String> {
    json.as_object()
        .into_iter()
        .flatten()
        .map(|(name, v)| {
            format!(
                "{name} {} → {}",
                v["current"].as_str().unwrap_or("?"),
                v["latest"].as_str().unwrap_or("?")
            )
        })
        .collect()
}

fn npm() -> Result<Check, String> {
    // Exits 1 when something is outdated; the JSON says what.
    let ran = run("npm", &["outdated", "-g", "--json"])?;
    let json: serde_json::Value = if ran.out.trim().is_empty() {
        serde_json::json!({})
    } else {
        serde_json::from_str(&ran.out).map_err(|e| format!("npm: {e}"))?
    };
    Ok(Check::new(Step::Npm, updates(parse_npm(&json), Vec::new())))
}

/// `uv tool list`: (tool, version) from lines like "ruff v0.6.9".
pub fn parse_uv(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter(|l| !l.starts_with('-') && !l.starts_with(' '))
        .filter_map(|l| {
            let mut words = l.split_whitespace();
            let name = words.next()?;
            let version = words.next()?.strip_prefix('v')?;
            Some((name.to_string(), version.to_string()))
        })
        .collect()
}

fn uv() -> Result<Check, String> {
    let ran = run("uv", &["tool", "list"])?;
    if !ran.ok() {
        return Err(ran.tail(2));
    }
    let tools = parse_uv(&ran.out);
    // PyPI's latest version of each tool, all at once.
    let latest: Vec<Result<String, String>> = thread::scope(|s| {
        let jobs: Vec<_> = tools
            .iter()
            .map(|(name, _)| {
                s.spawn(move || {
                    sys::get_json(&format!("https://pypi.org/pypi/{name}/json")).and_then(|j| {
                        j["info"]["version"]
                            .as_str()
                            .map(String::from)
                            .ok_or("no version".into())
                    })
                })
            })
            .collect();
        jobs.into_iter()
            .map(|j| j.join().unwrap_or_else(|_| Err("stopped".into())))
            .collect()
    });
    let mut items = Vec::new();
    let mut unknown = Vec::new();
    for ((name, current), latest) in tools.iter().zip(latest) {
        match latest {
            Ok(l) if l != *current => items.push(format!("{name} {current} → {l}")),
            Ok(_) => {}
            Err(_) => unknown.push(name.clone()),
        }
    }
    let mut check = Check::new(Step::Uv, updates(items, Vec::new()));
    if !unknown.is_empty() {
        // Tools from git or a local path: `uv tool upgrade` still updates them.
        check
            .warnings
            .push(format!("not on PyPI, not checked: {}", unknown.join(", ")));
    }
    Ok(check)
}

fn bun() -> Result<Check, String> {
    let ran = run("bun", &["--version"])?;
    let current = ran.out.trim().to_string();
    // The npm registry knows bun's latest version without spending GitHub's
    // quota (bun upgrade itself asks GitHub).
    let latest = sys::get_json("https://registry.npmjs.org/bun/latest")?["version"]
        .as_str()
        .map(String::from)
        .ok_or("the npm registry gave no bun version")?;
    let items = if latest != current {
        vec![format!("bun {current} → {latest}")]
    } else {
        Vec::new()
    };
    Ok(Check::new(Step::Bun, updates(items, Vec::new())))
}

// ---- fisher ----

fn fisher_check() -> Check {
    match fisher::plan() {
        Ok(plan) => {
            let items = plan
                .actions
                .iter()
                .map(|a| match a.kind {
                    fisher::Kind::Remove => format!("remove {}", a.plugin),
                    fisher::Kind::Install => format!("install {}", a.plugin),
                    fisher::Kind::Update => a.plugin.clone(),
                })
                .collect();
            let mut check = Check::new(Step::Fisher, updates(items, Vec::new()));
            check.warnings = plan.warnings;
            check.fisher = plan.actions;
            check
        }
        Err(e) => Check::new(Step::Fisher, Found::Failed(e)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_dnf() {
        let out = "\nfirefox.x86_64   133.0-1.fc44   updates\nkernel.x86_64   6.12.4-200.fc44   updates\nObsoleting packages\nbad line\n";
        assert_eq!(
            parse_dnf(out),
            [
                ("firefox".to_string(), "133.0-1.fc44".to_string()),
                ("kernel".to_string(), "6.12.4-200.fc44".to_string())
            ]
        );
        assert!(parse_dnf("").is_empty());
    }

    #[test]
    fn reads_firmware_and_flatpak() {
        let j = serde_json::json!({"Devices": [
            {"Name": "System Firmware", "Releases": [{"Version": "1.32.0"}]},
            {"Name": "Touchpad", "Releases": []}
        ]});
        assert_eq!(parse_fwupd(&j), ["System Firmware 1.32.0"]);
        assert!(parse_fwupd(&serde_json::json!({"Devices": []})).is_empty());
        assert_eq!(
            parse_flatpak("org.mozilla.firefox\n\norg.gnome.Platform\n"),
            ["firefox", "Platform"]
        );
    }

    #[test]
    fn reads_gear_lever() {
        let installed = "Cura   /opt/AppImages/cura.appimage   [GithubUpdater]\n\
                         Tool   /opt/AppImages/tool.AppImage   [UpdatesNotAvailable]\n";
        assert_eq!(
            parse_gearlever_installed(installed),
            (vec!["tool.AppImage".to_string()], 1)
        );
        let j = serde_json::json!({"updates": [{"path": "/opt/AppImages/cura.appimage"}]});
        assert_eq!(parse_gearlever_updates(&j), ["/opt/AppImages/cura.appimage"]);
    }

    #[test]
    fn reads_npm_and_uv() {
        let j = serde_json::json!({"typescript": {"current": "5.6.2", "wanted": "5.6.2", "latest": "5.7.1"}});
        assert_eq!(parse_npm(&j), ["typescript 5.6.2 → 5.7.1"]);
        assert!(parse_npm(&serde_json::json!({})).is_empty());
        assert_eq!(
            parse_uv("ruff v0.6.9\n- ruff\nposting v2.3.0\n- posting\n"),
            [
                ("ruff".to_string(), "0.6.9".to_string()),
                ("posting".to_string(), "2.3.0".to_string())
            ]
        );
    }

    #[test]
    fn counts_work() {
        let c = Check::new(Step::Npm, updates(vec!["a".into()], Vec::new()));
        assert!(c.has_work());
        assert_eq!(c.count(), 1);
        assert_eq!(updates(Vec::new(), Vec::new()), Found::UpToDate);
        assert!(!Check::new(Step::Npm, Found::Absent("x".into())).has_work());
        assert!(Check::new(Step::Npm, Found::Failed("x".into())).has_work());
    }
}
