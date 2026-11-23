//! Command line: `upi [step…] [--skip step,…] [--check] [--yes] [--no-snapshot]
//! [--last] [--list] [--help]`.

use crate::steps::Step;

#[derive(Debug, PartialEq)]
pub enum Command {
    Run(Options),
    List,
    Last,
    Help,
}

#[derive(Debug, PartialEq)]
pub struct Options {
    /// The steps to check and run, in run order.
    pub steps: Vec<Step>,
    /// Only list what would update.
    pub check_only: bool,
    /// Do not ask before updating.
    pub yes: bool,
    /// Take the Timeshift snapshot first.
    pub snapshot: bool,
}

pub fn usage() -> String {
    let steps: Vec<&str> = Step::ALL.iter().map(|s| s.id()).collect();
    format!(
        "Usage: upi [step…] [--skip step,…] [--check] [--yes] [--no-snapshot]\n\
         \x20      upi --last | --list | --help\n\n\
         Checks every source for updates, lists them and asks once, then takes a\n\
         Timeshift snapshot and updates each source in turn.\n\n\
         \x20 step…           only these steps\n\
         \x20 --skip a,b      every step except these\n\
         \x20 -c, --check     only list what would update\n\
         \x20 -y, --yes       do not ask before updating\n\
         \x20 --no-snapshot   skip the Timeshift snapshot\n\
         \x20 --last          show how the last run went\n\
         \x20 --list          list the steps\n\n\
         Steps: {}\n",
        steps.join(", ")
    )
}

/// Parse the arguments after the program name.
pub fn parse<I: IntoIterator<Item = String>>(args: I) -> Result<Command, String> {
    let mut only = Vec::new();
    let mut skip = Vec::new();
    let mut check_only = false;
    let mut yes = false;
    let mut snapshot = true;
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Command::Help),
            "--list" => return Ok(Command::List),
            "--last" => return Ok(Command::Last),
            "-c" | "--check" => check_only = true,
            "-y" | "--yes" => yes = true,
            "--no-snapshot" => snapshot = false,
            "--skip" => {
                let list = args.next().ok_or("--skip needs step names")?;
                skip.extend(steps_in(&list)?);
            }
            a if a.starts_with("--skip=") => skip.extend(steps_in(&a["--skip=".len()..])?),
            a if a.starts_with('-') => return Err(format!("unknown option: {a}")),
            a => only.extend(steps_in(a)?),
        }
    }
    let steps: Vec<Step> = Step::ALL
        .into_iter()
        .filter(|s| (only.is_empty() || only.contains(s)) && !skip.contains(s))
        .collect();
    if steps.is_empty() {
        return Err("no steps left to run".into());
    }
    Ok(Command::Run(Options {
        steps,
        check_only,
        yes,
        snapshot,
    }))
}

fn steps_in(list: &str) -> Result<Vec<Step>, String> {
    list.split(',')
        .filter(|s| !s.is_empty())
        .map(|s| Step::from_id(s).ok_or_else(|| format!("unknown step: {s} (see upi --list)")))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Result<Command, String> {
        parse(args.iter().map(|s| s.to_string()))
    }

    fn steps(args: &[&str]) -> Vec<Step> {
        match run(args) {
            Ok(Command::Run(o)) => o.steps,
            other => panic!("not a run: {other:?}"),
        }
    }

    #[test]
    fn picks_steps() {
        assert_eq!(steps(&[]), Step::ALL.to_vec());
        // Run order, not the order typed.
        assert_eq!(steps(&["flatpak", "dnf"]), [Step::Dnf, Step::Flatpak]);
        assert_eq!(steps(&["dnf,npm"]), [Step::Dnf, Step::Npm]);
        assert_eq!(
            steps(&[
                "--skip",
                "dnf,plugins,firmware,flatpak,appimages,npm,uv,immich-rs,vscode,tldr,dots"
            ]),
            [Step::Bun, Step::Fisher]
        );
        assert_eq!(steps(&["flatpak", "--skip=flatpak", "npm"]), [Step::Npm]);
    }

    #[test]
    fn reads_options() {
        let Ok(Command::Run(o)) = run(&["-c", "--yes", "--no-snapshot"]) else {
            panic!("not a run")
        };
        assert!(o.check_only && o.yes && !o.snapshot);
        assert_eq!(run(&["--last"]), Ok(Command::Last));
        assert_eq!(run(&["--list"]), Ok(Command::List));
    }

    #[test]
    fn rejects_bad_input() {
        assert!(run(&["apt"]).unwrap_err().contains("unknown step: apt"));
        assert!(run(&["--frob"]).unwrap_err().contains("unknown option"));
        assert!(run(&["--skip"]).is_err());
        assert!(run(&["dnf", "--skip", "dnf"]).unwrap_err().contains("no steps"));
    }
}
