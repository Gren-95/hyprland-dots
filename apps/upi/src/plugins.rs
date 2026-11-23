//! Hyprland plugins built from source: each `~/.local/lib/hyprland/plugins/
//! <name>.so` whose source is a git checkout in `~/.local/src/<name>`. A
//! plugin only loads into the Hyprland it was built against, so it is rebuilt
//! when Hyprland changes (also when this run's dnf step brings a new one), and
//! when its source has new commits on the ref it follows. The new build loads
//! at the next login: Hyprland keeps a plugin it has loaded, and a plugin
//! built for a newly installed Hyprland does not fit the one still running.

use std::path::{Path, PathBuf};

use crate::check::Item;
use crate::sys::{self, Log, Ran};

#[derive(Debug, Clone, PartialEq)]
pub struct Plugin {
    pub name: String,
    pub src: PathBuf,
    pub so: PathBuf,
    /// The remote ref it follows ("origin/hyprland-git").
    pub follow: String,
    /// The commit the installed build is from.
    pub built: String,
    pub remote: String,
    /// The Hyprland version the installed build is for.
    pub built_for: String,
}

impl Plugin {
    pub fn new_commits(&self) -> bool {
        self.built != self.remote
    }
}

/// The record of a build: "commit\nhyprland version\nfollowed ref".
#[derive(Debug, PartialEq)]
pub struct Record {
    pub commit: String,
    pub hyprland: String,
    pub follow: String,
}

pub fn parse_record(text: &str) -> Option<Record> {
    let mut lines = text.lines().map(str::trim).filter(|l| !l.is_empty());
    Some(Record {
        commit: lines.next()?.to_string(),
        hyprland: lines.next()?.to_string(),
        follow: lines.next()?.to_string(),
    })
}

/// The Lua version Hyprland links ("liblua-5.4.so()(64bit)" in its rpm
/// requirements gives "5.4").
pub fn parse_lua_requirement(requires: &str) -> Option<String> {
    requires
        .lines()
        .find_map(|l| l.trim().strip_prefix("liblua-"))
        .and_then(|rest| rest.split(".so").next())
        .filter(|v| !v.is_empty())
        .map(String::from)
}

/// The pkg-config module of Hyprland's Lua, for a plugin build to use the
/// same one (a plugin runs inside Hyprland's Lua).
fn hyprland_lua() -> Option<(String, String)> {
    let requires = sys::run(&Log::none(), "rpm", &["-q", "--requires", "hyprland"])
        .ok()?
        .out;
    let version = parse_lua_requirement(&requires)?;
    let compact = version.replace('.', "");
    [
        "lua".to_string(),
        format!("lua{version}"),
        format!("lua-{version}"),
        format!("lua{compact}"),
    ]
    .into_iter()
    .find(|m| {
        sys::run(&Log::none(), "pkg-config", &["--modversion", m])
            .is_ok_and(|r| r.ok() && r.out.trim().starts_with(&format!("{version}.")))
    })
    .map(|m| (m, version))
}

fn plugins_dir() -> PathBuf {
    sys::home().join(".local/lib/hyprland/plugins")
}

fn record(name: &str) -> PathBuf {
    sys::state_dir().join("upi/plugins").join(name)
}

fn git(src: &Path, args: &[&str]) -> Result<Ran, String> {
    let dir = src.to_string_lossy().into_owned();
    let mut all = vec!["-C", dir.as_str()];
    all.extend_from_slice(args);
    sys::run(&Log::none(), "git", &all)
}

fn git_out(src: &Path, args: &[&str]) -> Result<String, String> {
    let ran = git(src, args)?;
    if !ran.ok() {
        return Err(format!("git {}: {}", args.join(" "), ran.tail(2)));
    }
    Ok(ran.out.trim().to_string())
}

/// The installed Hyprland's version ("0.57.2-1.fc44").
pub fn installed_hyprland() -> Result<String, String> {
    rpm_version("hyprland")
}

fn rpm_version(package: &str) -> Result<String, String> {
    let ran = sys::run(&Log::none(), "rpm", &["-q", "--qf", "%{VERSION}-%{RELEASE}", package])?;
    if !ran.ok() {
        return Err(format!("{package} is not installed from a package"));
    }
    Ok(ran.out.trim().to_string())
}

/// Names of the plugins Hyprland has loaded (`hyprctl plugin list`).
pub fn parse_loaded(out: &str) -> Vec<String> {
    out.lines()
        .filter_map(|l| l.strip_prefix("Plugin "))
        .filter_map(|l| l.split(" by ").next())
        .map(|n| n.trim().to_string())
        .collect()
}

/// The remote ref a checkout follows: its branch's upstream, or for a
/// detached checkout the remote branch it was last checked out from (the
/// reflog's "checkout: moving from A to origin/x"; the branch may have moved
/// on since, so it no longer points at HEAD).
pub fn follow_ref(upstream: &str, reflog: &str) -> Option<String> {
    if !upstream.is_empty() {
        return Some(upstream.to_string());
    }
    reflog
        .lines()
        .find_map(|l| l.strip_prefix("checkout: moving from "))
        .and_then(|l| l.rsplit_once(" to "))
        .map(|(_, to)| to.trim())
        .filter(|to| to.starts_with("origin/"))
        .map(String::from)
}

/// The plugins with a source checkout, fetched and read. Not a check that
/// fails as a whole: a plugin that cannot be read is an error of its own.
pub fn discover() -> Result<Vec<Result<Plugin, String>>, String> {
    let Ok(entries) = std::fs::read_dir(plugins_dir()) else {
        return Ok(Vec::new());
    };
    let hyprland = installed_hyprland()?;
    let loaded = parse_loaded(
        &sys::run(&Log::none(), "hyprctl", &["plugin", "list"])
            .map(|r| r.out)
            .unwrap_or_default(),
    );
    let mut paths: Vec<PathBuf> = entries.flatten().map(|e| e.path()).collect();
    paths.sort();
    let mut found = Vec::new();
    for so in paths {
        let Some(name) = so
            .file_stem()
            .filter(|_| so.extension().is_some_and(|x| x == "so"))
            .map(|n| n.to_string_lossy().into_owned())
        else {
            continue;
        };
        let src = sys::home().join(".local/src").join(&name);
        if !src.join(".git").exists() {
            continue;
        }
        found.push(read_plugin(name, src, so, &hyprland, &loaded));
    }
    Ok(found)
}

fn read_plugin(name: String, src: PathBuf, so: PathBuf, hyprland: &str, loaded: &[String]) -> Result<Plugin, String> {
    let fetched = git(&src, &["fetch", "-q", "origin"])?;
    if !fetched.ok() {
        return Err(format!("{name}: could not fetch: {}", fetched.tail(1)));
    }
    let recorded = std::fs::read_to_string(record(&name))
        .ok()
        .and_then(|t| parse_record(&t));
    // The ref to follow: the one recorded at the last build, else what the
    // checkout says (a branch's upstream, or the remote branch last checked
    // out).
    let follow = match &recorded {
        Some(r) => r.follow.clone(),
        None => {
            let upstream = git(&src, &["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
                .map(|r| {
                    if r.ok() {
                        r.out.trim().to_string()
                    } else {
                        String::new()
                    }
                })
                .unwrap_or_default();
            let reflog = git_out(&src, &["reflog", "-n", "200", "--format=%gs"]).unwrap_or_default();
            follow_ref(&upstream, &reflog).ok_or_else(|| format!("{name}: its checkout follows no remote branch"))?
        }
    };
    let remote = git_out(&src, &["rev-parse", &follow])?;
    // Without a record (never built by upi), the installed build is taken to
    // be from the checkout as it is, and, when Hyprland has it loaded, for the
    // Hyprland installed now (it would not load otherwise).
    let (built, built_for) = match recorded {
        Some(r) => (r.commit, r.hyprland),
        None => (
            git_out(&src, &["rev-parse", "HEAD"])?,
            if loaded.contains(&name) {
                hyprland.to_string()
            } else {
                "unknown".into()
            },
        ),
    };
    Ok(Plugin {
        name,
        src,
        so,
        follow,
        built,
        remote,
        built_for,
    })
}

/// What rebuilding each plugin changes, for Hyprland `target`. Only the
/// plugins that need it.
pub fn items(plugins: &[Plugin], target: &str) -> Vec<Item> {
    plugins
        .iter()
        .filter(|p| p.new_commits() || p.built_for != target)
        .map(|p| {
            Item::new(
                p.name.as_str(),
                format!("{} · Hyprland {}", short(&p.built), p.built_for),
                format!("{} · Hyprland {target}", short(&p.remote)),
            )
        })
        .collect()
}

fn short(commit: &str) -> &str {
    &commit[..commit.len().min(7)]
}

/// Build one plugin from its followed ref and install it in place; record
/// the Hyprland it is built for.
pub fn rebuild(log: &Log, p: &Plugin) -> Result<(), String> {
    let src = p.src.to_string_lossy().into_owned();
    let step = |program: &str, args: &[&str]| -> Result<(), String> {
        let ran = sys::run(log, program, args)?;
        if ran.ok() {
            Ok(())
        } else {
            Err(format!(
                "{program} {}: {}",
                args.first().copied().unwrap_or_default(),
                ran.tail(4)
            ))
        }
    };
    step("git", &["-C", &src, "checkout", "-q", "--detach", &p.remote])?;
    // -B: a new Hyprland changes nothing make sees, but the build must redo.
    let mut make = vec!["-B".to_string(), "-C".to_string(), src.clone()];
    // Build against Hyprland's own Lua. A plugin that guards for another
    // Lua version (hyprexpo asks for the 5.5 of upstream Hyprland 0.57 in its
    // check-lua target) is told the one this Hyprland really links.
    if let Some((module, version)) = hyprland_lua() {
        make.push(format!("LUA_PKG_CONFIG={module}"));
        if version != "5.5" {
            make.extend(["-o".to_string(), "check-lua".to_string()]);
        }
    }
    make.push("all".into());
    let make: Vec<&str> = make.iter().map(String::as_str).collect();
    step("make", &make)?;
    let built = p.src.join(format!("{}.so", p.name));
    let tmp = p.so.with_extension("so.new");
    std::fs::copy(&built, &tmp).map_err(|e| format!("could not copy {}: {e}", built.display()))?;
    step("strip", &["-S", &tmp.to_string_lossy()])?;
    // A rename: Hyprland keeps the file it has loaded open as it was.
    std::fs::rename(&tmp, &p.so).map_err(|e| format!("could not install {}: {e}", p.so.display()))?;
    let hyprland = installed_hyprland()?;
    let path = record(&p.name);
    std::fs::create_dir_all(path.parent().unwrap_or(Path::new(".")))
        .and_then(|()| std::fs::write(&path, format!("{}\n{hyprland}\n{}\n", p.remote, p.follow)))
        .map_err(|e| format!("built, but could not record it: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn plugin(built: &str, remote: &str, built_for: &str) -> Plugin {
        Plugin {
            name: "hyprexpo".into(),
            src: PathBuf::new(),
            so: PathBuf::new(),
            follow: "origin/hyprland-git".into(),
            built: built.into(),
            remote: remote.into(),
            built_for: built_for.into(),
        }
    }

    #[test]
    fn reads_plugins() {
        let list = "Plugin hyprexpo by sandwich:\n\tHandle: 55858db6dab0\n\tVersion: v0.56.2\nPlugin other by me:\n";
        assert_eq!(parse_loaded(list), ["hyprexpo", "other"]);
        assert_eq!(follow_ref("origin/main", ""), Some("origin/main".into()));
        let reflog =
            "commit: local\ncheckout: moving from master to origin/hyprland-git\ncheckout: moving from a to master\n";
        assert_eq!(follow_ref("", reflog), Some("origin/hyprland-git".into()));
        assert_eq!(follow_ref("", "checkout: moving from a to 1db341b\n"), None);
        assert_eq!(follow_ref("", ""), None);
    }

    #[test]
    fn reads_records_and_lua() {
        assert_eq!(
            parse_record("fe63507abc\n0.57.2-1.fc44\norigin/hyprland-git\n"),
            Some(Record {
                commit: "fe63507abc".into(),
                hyprland: "0.57.2-1.fc44".into(),
                follow: "origin/hyprland-git".into()
            })
        );
        assert_eq!(parse_record("fe63507abc\n0.57.2-1.fc44\n"), None);
        assert_eq!(
            parse_lua_requirement("libc.so.6()(64bit)\nliblua-5.4.so()(64bit)\n"),
            Some("5.4".into())
        );
        assert_eq!(parse_lua_requirement("libc.so.6"), None);
    }

    #[test]
    fn rebuilds_for_a_new_hyprland_or_new_commits() {
        let same = plugin("1db341bcafe", "1db341bcafe", "0.57.2-1.fc44");
        assert!(items(std::slice::from_ref(&same), "0.57.2-1.fc44").is_empty());
        assert_eq!(
            items(&[same], "0.57.3-1.fc44"),
            [Item::new(
                "hyprexpo",
                "1db341b · Hyprland 0.57.2-1.fc44",
                "1db341b · Hyprland 0.57.3-1.fc44"
            )]
        );
        let moved = plugin("1db341bcafe", "2ab0000beef", "0.57.2-1.fc44");
        assert_eq!(items(&[moved], "0.57.2-1.fc44").len(), 1);
    }
}
