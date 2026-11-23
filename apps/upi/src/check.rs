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
        items: Vec<Item>,
        notes: Vec<String>,
    },
    /// Not installed, or not set up.
    Absent(String),
    /// Would go over the GitHub API quota: skipped this run.
    Limited(String),
    /// The check itself failed; the step still runs and reports.
    Failed(String),
    /// Something to know, with nothing to run (the dots repo is behind).
    Notice(String),
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
    /// Hyprland plugins built from source.
    pub plugins: Vec<crate::plugins::Plugin>,
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
            plugins: Vec::new(),
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

/// One thing that changes: its version now and after ("" when not known).
#[derive(Debug, Clone, PartialEq)]
pub struct Item {
    pub name: String,
    pub from: String,
    pub to: String,
}

/// What a removal goes to.
pub const REMOVED: &str = "removed";

impl Item {
    pub fn new(name: impl Into<String>, from: impl Into<String>, to: impl Into<String>) -> Item {
        Item {
            name: name.into(),
            from: from.into(),
            to: to.into(),
        }
    }

    /// "firefox 158.0.1-2 → 160.0-1", "plugin → (new) abc1234".
    pub fn line(&self) -> String {
        match (self.from.is_empty(), self.to.is_empty()) {
            (true, true) => self.name.clone(),
            (true, false) => format!("{} (new) → {}", self.name, self.to),
            (false, true) => format!("{} {} → newer", self.name, self.from),
            (false, false) => format!("{} {} → {}", self.name, self.from, self.to),
        }
    }
}

fn updates(items: Vec<Item>, notes: Vec<String>) -> Found {
    if items.is_empty() && notes.is_empty() {
        Found::UpToDate
    } else {
        Found::Updates { items, notes }
    }
}

/// Every step, checked in parallel, in step order.
pub fn all(steps: &[Step]) -> Vec<Check> {
    let mut checks: Vec<Check> = thread::scope(|s| {
        let jobs: Vec<_> = steps.iter().map(|&step| s.spawn(move || one(step))).collect();
        jobs.into_iter()
            .zip(steps)
            .map(|(j, &step)| {
                j.join()
                    .unwrap_or_else(|_| Check::new(step, Found::Failed("the check stopped".into())))
            })
            .collect()
    });
    // A Hyprland that dnf brings in this run needs the plugins rebuilt for it.
    let new_hyprland = checks.iter().find_map(|c| match (&c.step, &c.found) {
        (Step::Dnf, Found::Updates { items, .. }) => items.iter().find(|i| i.name == "hyprland").map(|i| i.to.clone()),
        _ => None,
    });
    if let Some(target) = new_hyprland
        && let Some(c) = checks
            .iter_mut()
            .find(|c| c.step == Step::Plugins && !c.plugins.is_empty())
    {
        c.found = updates(crate::plugins::items(&c.plugins, &target), Vec::new());
    }
    checks
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
        Step::Plugins => return plugins_check(),
        Step::VsCode => crate::extras::vscode().map(|items| Check::new(step, updates(items, Vec::new()))),
        Step::Tldr => Ok(Check::new(step, updates(crate::extras::tldr(), Vec::new()))),
        Step::Dots => crate::extras::dots().map(|n| Check::new(step, n.map_or(Found::UpToDate, Found::Notice))),
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
/// (name.arch, new version) pairs.
pub fn parse_dnf(out: &str) -> Vec<(String, String)> {
    out.lines()
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let [nevra, version, _repo] = f.as_slice() else {
                return None;
            };
            nevra.rsplit_once('.')?;
            version
                .chars()
                .next()
                .is_some_and(|c| c.is_ascii_digit())
                .then(|| (nevra.to_string(), version.to_string()))
        })
        .collect()
}

/// "name.arch\tversion" lines (rpm -qa, the format below): versions by
/// name.arch, several when more than one is installed (kernels).
pub fn parse_installed(out: &str) -> std::collections::HashMap<String, Vec<String>> {
    let mut map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    for l in out.lines() {
        if let Some((key, version)) = l.split_once('\t') {
            map.entry(key.to_string()).or_default().push(version.to_string());
        }
    }
    for versions in map.values_mut() {
        versions.sort();
    }
    map
}

/// "firefox.x86_64" is shown as "firefox"; other arches keep theirs.
fn package_name(name_arch: &str) -> String {
    match name_arch.rsplit_once('.') {
        Some((name, "x86_64" | "noarch")) => name.to_string(),
        Some((name, arch)) => format!("{name} ({arch})"),
        None => name_arch.to_string(),
    }
}

/// rpm's version in dnf's format: the epoch only when set.
const RPM_FORMAT: &str = "%{NAME}.%{ARCH}\\t%|EPOCH?{%{EPOCH}:}:{}|%{VERSION}-%{RELEASE}\\n";

fn dnf() -> Result<Check, String> {
    let ran = run("dnf", &["check-update", "-q"])?;
    // 100: updates listed; 0: none.
    let packages = match ran.code {
        0 => Vec::new(),
        100 => parse_dnf(&ran.out),
        _ => return Err(ran.tail(2)),
    };
    let installed = parse_installed(&run("rpm", &["-qa", "--qf", RPM_FORMAT])?.out);
    let mut items: Vec<Item> = packages
        .iter()
        .map(|(key, to)| {
            // Kernels are installed side by side: the newest stands for them.
            let from = installed.get(key).and_then(|v| v.last()).cloned().unwrap_or_default();
            Item::new(package_name(key), from, to.clone())
        })
        .collect();
    let mut notes = Vec::new();
    if let Some((_, v)) = packages
        .iter()
        .find(|(n, _)| n.starts_with("kernel.") || n.starts_with("kernel-core."))
    {
        notes.push(format!("kernel {}", v.split('-').next().unwrap_or(v)));
    }
    // What autoremove takes away, after the upgrades.
    let unneeded: Vec<Item> = run(
        "dnf",
        &[
            "repoquery",
            "--unneeded",
            "-q",
            "--queryformat",
            "%{name}.%{arch}\t%{evr}\n",
        ],
    )
    .map(|r| parse_installed(&r.out))
    .unwrap_or_default()
    .into_iter()
    .map(|(key, v)| Item::new(package_name(&key), v.join(", "), REMOVED))
    .collect();
    if !unneeded.is_empty() {
        notes.push(format!("{} to remove", unneeded.len()));
    }
    let count = unneeded.len();
    let mut removals = unneeded;
    removals.sort_by(|a, b| a.name.cmp(&b.name));
    items.extend(removals);
    let mut check = Check::new(Step::Dnf, updates(items, notes));
    check.unneeded = count;
    Ok(check)
}

// ---- firmware ----

/// `fwupdmgr get-updates --json`: each device with a release waiting, from
/// its version to the release's.
pub fn parse_fwupd(json: &serde_json::Value) -> Vec<Item> {
    json["Devices"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|d| {
            let release = d["Releases"].as_array()?.first()?;
            Some(Item::new(
                d["Name"].as_str()?,
                d["Version"].as_str().unwrap_or_default(),
                release["Version"].as_str().unwrap_or_default(),
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

/// Tab-separated "application\tversion\tbranch" lines (`flatpak list` and
/// `flatpak remote-ls --updates` with those columns), keyed by
/// application and branch, with the version (often empty for runtimes).
pub fn parse_flatpak(out: &str) -> Vec<(String, String, String)> {
    out.lines()
        .filter_map(|l| {
            let mut f = l.split('\t');
            let app = f.next()?.trim();
            let version = f.next().unwrap_or_default().trim();
            let branch = f.next().unwrap_or_default().trim();
            (!app.is_empty()).then(|| (app.to_string(), version.to_string(), branch.to_string()))
        })
        .collect()
}

fn flatpak() -> Result<Check, String> {
    let columns = "--columns=application,version,branch";
    let ran = run("flatpak", &["remote-ls", "--updates", columns])?;
    if !ran.ok() {
        return Err(ran.tail(2));
    }
    let installed = parse_flatpak(&run("flatpak", &["list", columns])?.out);
    let items = parse_flatpak(&ran.out)
        .into_iter()
        .map(|(app, to, branch)| {
            let from = installed
                .iter()
                .find(|(a, _, b)| *a == app && *b == branch)
                .map(|(_, v, _)| v.clone())
                .unwrap_or_default();
            // Runtimes carry no version: a new build of the same branch.
            let (from, to) = if from.is_empty() && to.is_empty() {
                (branch.clone(), format!("{branch} (new build)"))
            } else {
                (from, to)
            };
            Item::new(app, from, to)
        })
        .collect();
    Ok(Check::new(Step::Flatpak, updates(items, Vec::new())))
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
    // Gear Lever's list has no versions: "→ newer".
    let names = paths
        .iter()
        .map(|p| Item::new(p.rsplit('/').next().unwrap_or(p), "installed", ""))
        .collect();
    let mut check = with_warnings(updates(names, Vec::new()));
    check.appimages = paths;
    check
}

// ---- npm, uv, bun ----

/// `npm outdated -g --json`: each package from current to latest.
pub fn parse_npm(json: &serde_json::Value) -> Vec<Item> {
    json.as_object()
        .into_iter()
        .flatten()
        .map(|(name, v)| {
            Item::new(
                name.as_str(),
                v["current"].as_str().unwrap_or_default(),
                v["latest"].as_str().unwrap_or_default(),
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

/// Where a uv tool comes from: PyPI, or a git repository at a ref.
#[derive(Debug, Clone, PartialEq)]
pub enum UvSource {
    PyPi,
    Git {
        url: String,
        reference: String,
    },
    /// A local path or a direct URL: nothing to compare against.
    Other,
}

/// A quoted value after `key = ` in one line of TOML.
fn toml_value<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = &line[line.find(&format!("{key} = \""))? + key.len() + 4..];
    rest.split('"').next()
}

/// The tool's own requirement in its `uv-receipt.toml`.
pub fn parse_uv_receipt(receipt: &str, name: &str) -> UvSource {
    let Some(line) = receipt
        .lines()
        .find(|l| l.contains("requirements") && toml_value(l, "name") == Some(name))
    else {
        return UvSource::PyPi;
    };
    if let Some(url) = toml_value(line, "git") {
        let reference = ["rev", "tag", "branch"]
            .iter()
            .find_map(|k| toml_value(line, k))
            .unwrap_or("HEAD");
        return UvSource::Git {
            url: url.to_string(),
            reference: reference.to_string(),
        };
    }
    if toml_value(line, "path").is_some()
        || toml_value(line, "url").is_some()
        || toml_value(line, "directory").is_some()
    {
        return UvSource::Other;
    }
    UvSource::PyPi
}

/// The commit a git-installed tool was built from: its dist-info's
/// direct_url.json (PEP 610).
fn uv_installed_commit(tool_dir: &std::path::Path) -> Option<String> {
    let lib = std::fs::read_dir(tool_dir.join("lib")).ok()?;
    for py in lib.flatten() {
        let Ok(site) = std::fs::read_dir(py.path().join("site-packages")) else {
            continue;
        };
        for info in site.flatten() {
            let Ok(text) = std::fs::read_to_string(info.path().join("direct_url.json")) else {
                continue;
            };
            if let Ok(j) = serde_json::from_str::<serde_json::Value>(&text)
                && let Some(c) = j["vcs_info"]["commit_id"].as_str()
            {
                return Some(c.to_string());
            }
        }
    }
    None
}

/// What one tool would change to: Ok(None) when current.
fn uv_tool(name: &str, current: &str, tools_dir: &std::path::Path) -> Result<Option<Item>, String> {
    let receipt = std::fs::read_to_string(tools_dir.join(name).join("uv-receipt.toml")).unwrap_or_default();
    match parse_uv_receipt(&receipt, name) {
        UvSource::PyPi => {
            let latest = sys::get_json(&format!("https://pypi.org/pypi/{name}/json"))?["info"]["version"]
                .as_str()
                .map(String::from)
                .ok_or("PyPI gave no version")?;
            Ok((latest != current).then(|| Item::new(name, current, latest)))
        }
        UvSource::Git { url, reference } => {
            let installed = uv_installed_commit(&tools_dir.join(name)).ok_or("no installed commit recorded")?;
            let ran = run("git", &["ls-remote", &url, &reference])?;
            let remote = crate::fisher::commits(&ran.out);
            let remote = remote
                .split(',')
                .next()
                .filter(|c| !c.is_empty())
                .ok_or("could not read the repository")?;
            let short = |c: &str| c[..c.len().min(7)].to_string();
            Ok((remote != installed).then(|| {
                Item::new(
                    name,
                    format!("{current} · {}", short(&installed)),
                    format!("{} (git)", short(remote)),
                )
            }))
        }
        UvSource::Other => Err("installed from a path or URL".into()),
    }
}

fn uv() -> Result<Check, String> {
    let ran = run("uv", &["tool", "list"])?;
    if !ran.ok() {
        return Err(ran.tail(2));
    }
    let dir = run("uv", &["tool", "dir"])?;
    let tools_dir = std::path::PathBuf::from(dir.out.trim());
    let tools = parse_uv(&ran.out);
    // Each tool against PyPI, or its git repository, all at once.
    let results: Vec<Result<Option<Item>, String>> = thread::scope(|s| {
        let jobs: Vec<_> = tools
            .iter()
            .map(|(name, current)| {
                let dir = &tools_dir;
                s.spawn(move || uv_tool(name, current, dir))
            })
            .collect();
        jobs.into_iter()
            .map(|j| j.join().unwrap_or_else(|_| Err("stopped".into())))
            .collect()
    });
    let mut items = Vec::new();
    let mut check_warnings = Vec::new();
    for ((name, _), result) in tools.iter().zip(results) {
        match result {
            Ok(Some(item)) => items.push(item),
            Ok(None) => {}
            Err(e) => check_warnings.push(format!("{name}: not checked ({e})")),
        }
    }
    let mut check = Check::new(Step::Uv, updates(items, Vec::new()));
    check.warnings = check_warnings;
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
        vec![Item::new("bun", current, latest)]
    } else {
        Vec::new()
    };
    Ok(Check::new(Step::Bun, updates(items, Vec::new())))
}

// ---- Hyprland plugins ----

fn plugins_check() -> Check {
    let found = match crate::plugins::discover() {
        Ok(f) => f,
        Err(e) => return Check::new(Step::Plugins, Found::Failed(e)),
    };
    if found.is_empty() {
        return Check::new(Step::Plugins, Found::Absent("no plugin built from ~/.local/src".into()));
    }
    let (plugins, errors): (Vec<_>, Vec<_>) = found.into_iter().partition(|r| r.is_ok());
    let plugins: Vec<crate::plugins::Plugin> = plugins.into_iter().flatten().collect();
    let target = match crate::plugins::installed_hyprland() {
        Ok(t) => t,
        Err(e) => return Check::new(Step::Plugins, Found::Failed(e)),
    };
    let mut check = Check::new(
        Step::Plugins,
        updates(crate::plugins::items(&plugins, &target), Vec::new()),
    );
    check.warnings = errors.into_iter().filter_map(Result::err).collect();
    check.plugins = plugins;
    check
}

// ---- fisher ----

fn fisher_check() -> Check {
    match fisher::plan() {
        Ok(plan) => {
            let items = plan
                .actions
                .iter()
                .map(|a| {
                    let short = |c: &str| c.split(',').map(|x| &x[..x.len().min(7)]).collect::<Vec<_>>().join(",");
                    match a.kind {
                        fisher::Kind::Remove => Item::new(a.plugin.as_str(), "installed", REMOVED),
                        fisher::Kind::Install => Item::new(a.plugin.as_str(), "", short(&a.remote)),
                        fisher::Kind::Update => Item::new(a.plugin.as_str(), short(&a.recorded), short(&a.remote)),
                    }
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
        let out = "\nfirefox.x86_64   160.0-1.fc44   updates\nSDL3.i686   3.4.20-1.fc44   updates\nObsoleting packages\nbad line\n";
        assert_eq!(
            parse_dnf(out),
            [
                ("firefox.x86_64".to_string(), "160.0-1.fc44".to_string()),
                ("SDL3.i686".to_string(), "3.4.20-1.fc44".to_string())
            ]
        );
        assert!(parse_dnf("").is_empty());
        let installed =
            parse_installed("firefox.x86_64\t158.0.1-2.fc44\nkernel.x86_64\t7.3.4-202\nkernel.x86_64\t7.3.4-201\n");
        assert_eq!(installed["firefox.x86_64"], ["158.0.1-2.fc44"]);
        assert_eq!(installed["kernel.x86_64"], ["7.3.4-201", "7.3.4-202"]);
        assert_eq!(package_name("firefox.x86_64"), "firefox");
        assert_eq!(package_name("SDL3.i686"), "SDL3 (i686)");
    }

    #[test]
    fn reads_firmware_and_flatpak() {
        let j = serde_json::json!({"Devices": [
            {"Name": "System Firmware", "Version": "1.31.0", "Releases": [{"Version": "1.32.0"}]},
            {"Name": "Touchpad", "Version": "2", "Releases": []}
        ]});
        assert_eq!(parse_fwupd(&j), [Item::new("System Firmware", "1.31.0", "1.32.0")]);
        assert!(parse_fwupd(&serde_json::json!({"Devices": []})).is_empty());
        assert_eq!(
            parse_flatpak("org.mozilla.firefox\t133.0\tstable\norg.gnome.Platform\t\t48\n\n"),
            [
                (
                    "org.mozilla.firefox".to_string(),
                    "133.0".to_string(),
                    "stable".to_string()
                ),
                ("org.gnome.Platform".to_string(), String::new(), "48".to_string())
            ]
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
        assert_eq!(parse_npm(&j), [Item::new("typescript", "5.6.2", "5.7.1")]);
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
    fn reads_uv_receipts() {
        let git = r#"[tool]
requirements = [{ name = "hyprmod", git = "https://github.com/BlueManCZ/hyprmod.git" }]
"#;
        assert_eq!(
            parse_uv_receipt(git, "hyprmod"),
            UvSource::Git {
                url: "https://github.com/BlueManCZ/hyprmod.git".into(),
                reference: "HEAD".into()
            }
        );
        let tagged = r#"requirements = [{ name = "x", git = "https://g/x.git", tag = "v2" }]"#;
        assert_eq!(
            parse_uv_receipt(tagged, "x"),
            UvSource::Git {
                url: "https://g/x.git".into(),
                reference: "v2".into()
            }
        );
        assert_eq!(
            parse_uv_receipt(r#"requirements = [{ name = "ruff" }]"#, "ruff"),
            UvSource::PyPi
        );
        assert_eq!(
            parse_uv_receipt(r#"requirements = [{ name = "mine", path = "/src/mine" }]"#, "mine"),
            UvSource::Other
        );
        assert_eq!(parse_uv_receipt("", "ruff"), UvSource::PyPi);
    }

    #[test]
    fn describes_items() {
        assert_eq!(Item::new("firefox", "158", "160").line(), "firefox 158 → 160");
        assert_eq!(Item::new("fzf.fish", "", "abc1234").line(), "fzf.fish (new) → abc1234");
        assert_eq!(
            Item::new("cura.appimage", "installed", "").line(),
            "cura.appimage installed → newer"
        );
        assert_eq!(Item::new("old-lib", "1.0", REMOVED).line(), "old-lib 1.0 → removed");
    }

    #[test]
    fn counts_work() {
        let c = Check::new(Step::Npm, updates(vec![Item::new("a", "1", "2")], Vec::new()));
        assert!(c.has_work());
        assert_eq!(c.count(), 1);
        assert_eq!(updates(Vec::new(), Vec::new()), Found::UpToDate);
        assert!(!Check::new(Step::Npm, Found::Absent("x".into())).has_work());
        assert!(Check::new(Step::Npm, Found::Failed("x".into())).has_work());
    }
}
