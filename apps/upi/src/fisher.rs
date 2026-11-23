//! fish plugins in sync with fish_plugins. `fisher update` downloads and
//! reinstalls every plugin each time and keeps no record of the installed
//! commit, so the upstream commit of each plugin is remembered here, and only
//! plugins that are new, gone from fish_plugins, or whose upstream moved are
//! touched. A plugin with no recorded commit counts as moved.

use std::path::PathBuf;
use std::thread;

use crate::github;
use crate::sys::{self, Log};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Kind {
    Install,
    Update,
    Remove,
}

impl Kind {
    fn word(self) -> &'static str {
        match self {
            Kind::Install => "install",
            Kind::Update => "update",
            Kind::Remove => "remove",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Action {
    pub kind: Kind,
    pub plugin: String,
    /// The upstream commit(s) to remember after an install or update.
    pub remote: String,
    /// The commit(s) recorded at the last install or update.
    pub recorded: String,
}

/// What to do, and what could not be checked.
#[derive(Debug, Default)]
pub struct Plan {
    pub actions: Vec<Action>,
    pub warnings: Vec<String>,
}

/// Where the commits are kept (the path the old update-all.sh used, so the
/// record carries over).
fn state_dir() -> PathBuf {
    sys::home().join(".local/state/update-all/fisher")
}

/// The record file of a plugin: lower case, "/" as "%".
pub fn state_key(plugin: &str) -> String {
    plugin.to_lowercase().replace('/', "%")
}

/// `owner/repo[@ref]` as (repository URL, ref); None for other sources.
pub fn github_spec(plugin: &str) -> Option<(String, String)> {
    let (repo, reference) = plugin.split_once('@').unwrap_or((plugin, "HEAD"));
    let (owner, name) = repo.split_once('/')?;
    let ok = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "_.-".contains(c));
    (ok(owner) && ok(name) && !reference.is_empty())
        .then(|| (format!("https://github.com/{owner}/{name}"), reference.to_string()))
}

/// `git ls-remote` output: the commits, comma separated.
pub fn commits(ls_remote: &str) -> String {
    ls_remote
        .lines()
        .filter_map(|l| l.split_whitespace().next())
        .collect::<Vec<_>>()
        .join(",")
}

fn remote_commit(plugin: &str) -> Result<Option<String>, String> {
    let Some((url, reference)) = github_spec(plugin) else {
        return Ok(None);
    };
    let ran = sys::run(&Log::none(), "git", &["ls-remote", &url, &reference])?;
    let found = commits(&ran.out);
    if !ran.ok() || found.is_empty() {
        return Err(format!("could not check {plugin} upstream"));
    }
    Ok(Some(found))
}

pub fn plan() -> Result<Plan, String> {
    let wanted_text = std::fs::read_to_string(sys::home().join(".config/fish/fish_plugins"))
        .map_err(|e| format!("could not read fish_plugins: {e}"))?;
    let wanted: Vec<&str> = wanted_text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.contains(char::is_whitespace))
        .collect();
    let listed = sys::run(&Log::none(), "fish", &["-c", "fisher list"])?;
    if !listed.ok() {
        return Err(format!("fisher list failed: {}", listed.tail(2)));
    }
    let installed: Vec<&str> = listed.out.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    let has = |list: &[&str], p: &str| list.iter().any(|w| w.eq_ignore_ascii_case(p));

    let mut plan = Plan::default();
    for p in &installed {
        if !has(&wanted, p) {
            plan.actions.push(Action {
                kind: Kind::Remove,
                plugin: p.to_string(),
                remote: String::new(),
                recorded: String::new(),
            });
        }
    }
    // One ls-remote per plugin, all at once.
    let remotes: Vec<Result<Option<String>, String>> = thread::scope(|s| {
        let jobs: Vec<_> = wanted.iter().map(|p| s.spawn(move || remote_commit(p))).collect();
        jobs.into_iter()
            .map(|j| j.join().unwrap_or_else(|_| Err("check stopped".into())))
            .collect()
    });
    for (p, remote) in wanted.iter().zip(remotes) {
        let remote = match remote {
            Ok(Some(r)) => r,
            Ok(None) => {
                plan.warnings.push(format!("{p} is not a GitHub plugin, left as it is"));
                continue;
            }
            Err(e) => {
                plan.warnings.push(e);
                continue;
            }
        };
        let recorded = std::fs::read_to_string(state_dir().join(state_key(p))).unwrap_or_default();
        let kind = if !has(&installed, p) {
            Kind::Install
        } else if recorded.trim() != remote {
            Kind::Update
        } else {
            continue;
        };
        plan.actions.push(Action {
            kind,
            plugin: p.to_string(),
            remote,
            recorded: recorded.trim().to_string(),
        });
    }
    Ok(plan)
}

/// How one action went.
pub enum Applied {
    Done,
    Failed(String),
    Limited(String),
}

/// Run one action. Fisher reads plugin names from a non-terminal stdin (it is
/// closed here) and reports fetch errors on stderr while exiting 0, so any
/// stderr output counts as a failure.
pub fn apply(log: &Log, action: &Action) -> Applied {
    if action.kind != Kind::Remove
        && let Err(e) = github::enough(1)
    {
        return Applied::Limited(e);
    }
    let ran = match sys::run(log, "fish", &["-c", "fisher $argv", action.kind.word(), &action.plugin]) {
        Ok(r) => r,
        Err(e) => return Applied::Failed(e),
    };
    if github::hit_limit(&ran.err) {
        return Applied::Limited("GitHub API limit reached".into());
    }
    if !ran.ok() || !ran.err.trim().is_empty() {
        return Applied::Failed(format!("{} {}: {}", action.kind.word(), action.plugin, ran.tail(3)));
    }
    let record = state_dir().join(state_key(&action.plugin));
    let saved = match action.kind {
        Kind::Remove => std::fs::remove_file(&record).or_else(|e| match e.kind() {
            std::io::ErrorKind::NotFound => Ok(()),
            _ => Err(e),
        }),
        _ => std::fs::create_dir_all(state_dir()).and_then(|()| std::fs::write(&record, &action.remote)),
    };
    match saved {
        Ok(()) => Applied::Done,
        Err(e) => Applied::Failed(format!("{}: could not record the commit: {e}", action.plugin)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_plugin_specs() {
        assert_eq!(
            github_spec("jorgebucaran/fisher"),
            Some(("https://github.com/jorgebucaran/fisher".into(), "HEAD".into()))
        );
        assert_eq!(
            github_spec("PatrickF1/fzf.fish@v10"),
            Some(("https://github.com/PatrickF1/fzf.fish".into(), "v10".into()))
        );
        assert_eq!(github_spec("~/code/my-plugin"), None);
        assert_eq!(github_spec("a/b;rm"), None);
        assert_eq!(state_key("PatrickF1/fzf.fish"), "patrickf1%fzf.fish");
        assert_eq!(commits("abc\tHEAD\ndef\trefs/tags/v1\n"), "abc,def");
        assert_eq!(commits(""), "");
    }
}
