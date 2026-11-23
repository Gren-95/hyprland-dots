//! The updates themselves, one source at a time (package managers hold
//! locks), with every command's output going to the run log. Nothing asks
//! questions: the plan was confirmed before the run, and sudo runs with -n on
//! the credentials asked for at the start.

use crate::check::Check;
use crate::fisher::{self, Applied};
use crate::github;
use crate::steps::Step;
use crate::sys::{self, Log, Ran};

/// How a step went.
#[derive(Debug, Clone, PartialEq)]
pub enum Outcome {
    /// Worked; the detail says what changed.
    Done(String),
    Failed(String),
    /// Stopped by the GitHub API quota; the next run picks it up.
    Limited(String),
}

/// "what exited with N: <last line>", then the last lines of its output.
fn failed(what: &str, ran: &Ran) -> Outcome {
    let tail = ran.tail(6);
    let last = tail.lines().last().unwrap_or_default();
    Outcome::Failed(if tail.is_empty() {
        format!("{what} exited with {}", ran.code)
    } else {
        format!("{what} exited with {}: {last}\n{tail}", ran.code)
    })
}

/// Run each command in turn; the first that fails ends the step.
fn commands(log: &Log, list: &[(&str, &[&str], &[i32])]) -> Result<(), Outcome> {
    for (program, args, ok_codes) in list {
        let ran = sys::run(log, program, args).map_err(Outcome::Failed)?;
        if !ok_codes.contains(&ran.code) {
            let what = format!(
                "{program} {}",
                args.iter().take(3).copied().collect::<Vec<_>>().join(" ")
            );
            return Err(failed(&what, &ran));
        }
    }
    Ok(())
}

fn counted(check: &Check, noun: &str) -> String {
    match check.count() {
        0 => "done".into(),
        n => format!("{n} {noun}"),
    }
}

pub fn run(log: &Log, check: &Check) -> Outcome {
    log.line(&format!("\n==> {}", check.step.name()));
    match check.step {
        Step::Dnf => dnf(log, check),
        Step::Firmware => firmware(log),
        Step::Flatpak => simple(
            log,
            check,
            "updated",
            &[
                ("flatpak", &["update", "-y", "--noninteractive"], &[0]),
                ("flatpak", &["uninstall", "--unused", "-y", "--noninteractive"], &[0]),
            ],
        ),
        Step::AppImages => appimages(log, check),
        Step::Npm => simple(log, check, "updated", &[("npm", &["update", "-g"], &[0])]),
        Step::Uv => simple(log, check, "updated", &[("uv", &["tool", "upgrade", "--all"], &[0])]),
        Step::Bun => bun(log, check),
        Step::Fisher => fisher_plugins(log, check),
    }
}

fn simple(log: &Log, check: &Check, noun: &str, list: &[(&str, &[&str], &[i32])]) -> Outcome {
    match commands(log, list) {
        Ok(()) => Outcome::Done(counted(check, noun)),
        Err(o) => o,
    }
}

fn dnf(log: &Log, check: &Check) -> Outcome {
    let mut list: Vec<(&str, &[&str], &[i32])> = vec![
        ("sudo", &["-n", "dnf", "makecache", "--refresh", "-q"], &[0]),
        ("sudo", &["-n", "dnf", "upgrade", "-y"], &[0]),
    ];
    if check.unneeded > 0 {
        list.push(("sudo", &["-n", "dnf", "autoremove", "-y"], &[0]));
    }
    let mut detail = counted(check, "updated");
    if check.unneeded > 0 {
        detail.push_str(&format!(", {} removed", check.unneeded));
    }
    match commands(log, &list) {
        Ok(()) => Outcome::Done(detail),
        Err(o) => o,
    }
}

/// fwupdmgr exits 2 when there is nothing to do. The update does not reboot
/// by itself; a firmware that needs one says so in the summary.
fn firmware(log: &Log) -> Outcome {
    let refresh = commands(log, &[("sudo", &["-n", "fwupdmgr", "refresh"], &[0, 2])]);
    if let Err(o) = refresh {
        return o;
    }
    match sys::run(
        log,
        "sudo",
        &["-n", "fwupdmgr", "update", "--assume-yes", "--no-reboot-check"],
    ) {
        Ok(r) if r.code == 2 => Outcome::Done("nothing to install".into()),
        Ok(r) if r.ok() => Outcome::Done("installed; may apply at the next reboot".into()),
        Ok(r) => failed("fwupdmgr update", &r),
        Err(e) => Outcome::Failed(e),
    }
}

/// Gear Lever spends one GitHub request per app checked, so only the apps
/// the check found with an update are updated, and a spent quota stops it.
fn appimages(log: &Log, check: &Check) -> Outcome {
    let mut done = 0;
    for path in &check.appimages {
        let ran = match sys::run(
            log,
            "flatpak",
            &["run", "it.mijorus.gearlever", "--update", path, "--yes"],
        ) {
            Ok(r) => r,
            Err(e) => return Outcome::Failed(e),
        };
        if github::hit_limit(&ran.out) || github::hit_limit(&ran.err) {
            return Outcome::Limited(format!(
                "GitHub API limit reached after {done} of {}",
                check.appimages.len()
            ));
        }
        if !ran.ok() {
            let name = path.rsplit('/').next().unwrap_or(path);
            return failed(&format!("Gear Lever on {name}"), &ran);
        }
        done += 1;
    }
    Outcome::Done(format!("{done} updated"))
}

/// `bun upgrade` asks the GitHub API for the latest release.
fn bun(log: &Log, check: &Check) -> Outcome {
    if let Err(e) = github::enough(1) {
        return Outcome::Limited(e);
    }
    match sys::run(log, "bun", &["upgrade"]) {
        Ok(r) if github::hit_limit(&r.out) || github::hit_limit(&r.err) => {
            Outcome::Limited("GitHub API limit reached".into())
        }
        Ok(r) if r.ok() => Outcome::Done(counted(check, "updated")),
        Ok(r) => failed("bun upgrade", &r),
        Err(e) => Outcome::Failed(e),
    }
}

fn fisher_plugins(log: &Log, check: &Check) -> Outcome {
    let mut done = 0;
    let mut errors = Vec::new();
    for action in &check.fisher {
        match fisher::apply(log, action) {
            Applied::Done => done += 1,
            Applied::Failed(e) => errors.push(e),
            Applied::Limited(e) => return Outcome::Limited(format!("{e} (after {done})")),
        }
    }
    if errors.is_empty() {
        Outcome::Done(format!("{done} changed"))
    } else {
        Outcome::Failed(errors.join("\n"))
    }
}

/// `dnf needs-restarting -r`: exit 1 when the kernel or a core library
/// changed. Read from the cache the upgrade just filled.
pub fn reboot_needed() -> bool {
    sys::run(&Log::none(), "dnf", &["needs-restarting", "-r", "-C"]).is_ok_and(|r| r.code == 1)
}

/// The Timeshift snapshot before anything changes; its tag on success.
pub fn snapshot(log: &Log) -> Result<String, String> {
    log.line("\n==> Timeshift snapshot");
    let ran = sys::run(
        log,
        "sudo",
        &["-n", "timeshift", "--create", "--scripted", "--comments", "pre-update"],
    )?;
    if !ran.ok() {
        return Err(ran.tail(8));
    }
    Ok(snapshot_tag(&ran.out))
}

/// "Tagged snapshot '2026-11-20_14-00-01': ondemand" gives the date part.
pub fn snapshot_tag(out: &str) -> String {
    out.lines()
        .find_map(|l| l.strip_prefix("Tagged snapshot '"))
        .and_then(|rest| rest.split('\'').next())
        .unwrap_or_default()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_snapshot_tag() {
        assert_eq!(
            snapshot_tag("Creating new snapshot...\nTagged snapshot '2026-11-20_14-00-01': ondemand\n"),
            "2026-11-20_14-00-01"
        );
        assert_eq!(snapshot_tag("nothing"), "");
    }

    #[test]
    fn stops_at_the_first_failing_command() {
        let log = Log::none();
        let ok: &[i32] = &[0];
        assert_eq!(commands(&log, &[("true", &[], ok), ("true", &[], ok)]), Ok(()));
        let Err(Outcome::Failed(why)) = commands(&log, &[("sh", &["-c", "echo boom; exit 4"], ok), ("true", &[], ok)])
        else {
            panic!("did not fail")
        };
        assert!(why.contains("exited with 4") && why.contains("boom"));
        assert_eq!(commands(&log, &[("sh", &["-c", "exit 2"], &[0, 2])]), Ok(()));
    }
}
