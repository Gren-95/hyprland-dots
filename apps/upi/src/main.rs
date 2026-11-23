//! upi: update everything on the dots machine. Checks every source at once
//! and lists what would change, asks once, takes a Timeshift snapshot (a hard
//! gate: no snapshot, no update), then updates each source with a live line
//! per step. Every command's output goes to a run log; the outcome is kept
//! for `upi --last` and the settings app.

mod args;
mod check;
mod extras;
mod fisher;
mod github;
mod plugins;
mod record;
mod steps;
mod sys;
mod ui;
mod update;

use std::process::ExitCode;
use std::time::Instant;

use args::{Command, Options};
use check::{Check, Found};
use record::{Run, StepRecord};
use sys::Log;
use ui::{Mark, Ui};
use update::Outcome;

/// Refuse to start with less free space than this on /.
const MIN_FREE_GIB: u64 = 10;

fn main() -> ExitCode {
    let ui = Ui::new();
    match args::parse(std::env::args().skip(1)) {
        Ok(Command::Help) => {
            print!("{}", args::usage());
            ExitCode::SUCCESS
        }
        Ok(Command::List) => {
            for s in steps::Step::ALL {
                println!("{:<10} {}", s.id(), s.name());
            }
            ExitCode::SUCCESS
        }
        Ok(Command::Last) => last(&ui),
        Ok(Command::Run(o)) => match update_all(&ui, &o) {
            Ok(code) => code,
            Err(e) => {
                ui.error(&e);
                ExitCode::FAILURE
            }
        },
        Err(e) => {
            eprintln!("upi: {e}");
            eprint!("{}", args::usage());
            ExitCode::from(2)
        }
    }
}

fn last(ui: &Ui) -> ExitCode {
    let run = match record::load() {
        Ok(r) => r,
        Err(e) => {
            ui.error(&e);
            return ExitCode::FAILURE;
        }
    };
    ui.heading(&format!(
        "{} · took {} · snapshot {}",
        sys::local_time(run.time, "%a %d %b %H:%M"),
        ui::duration(std::time::Duration::from_secs(run.seconds)),
        run.snapshot
    ));
    for s in &run.steps {
        let mark = match s.status.as_str() {
            "updated" => Mark::Done,
            "failed" => Mark::Failed,
            "rate-limited" => Mark::Limited,
            "absent" => Mark::Absent,
            _ => Mark::UpToDate,
        };
        let took = (s.status != "absent").then(|| std::time::Duration::from_secs(s.seconds));
        ui.line(mark, &s.name, took, s.detail.lines().next().unwrap_or_default());
        for c in &s.changes {
            ui.note(c);
        }
    }
    ui.dim(&format!("{}\nLog: {}", run.headline(), run.log));
    ExitCode::SUCCESS
}

/// The plan line of a checked step.
fn plan_line(ui: &Ui, c: &Check) {
    let (mark, text) = match &c.found {
        Found::UpToDate => (Mark::UpToDate, "up to date".to_string()),
        Found::Updates { items, notes } => {
            let names: Vec<String> = items.iter().map(|i| i.name.clone()).collect();
            (Mark::Pending, ui::summary(&names, notes))
        }
        Found::Absent(why) => (Mark::Absent, why.clone()),
        Found::Limited(why) => (Mark::Limited, format!("skipped: {why}")),
        Found::Notice(what) => (Mark::Pending, what.clone()),
        Found::Failed(why) => (
            Mark::Failed,
            format!(
                "could not check ({}); runs anyway",
                why.lines().next().unwrap_or_default()
            ),
        ),
    };
    ui.line(mark, c.step.name(), None, &text);
    for w in &c.warnings {
        ui.note(w);
    }
    // Everything that changes, from what to what.
    if let Found::Updates { items, .. } = &c.found {
        let rows: Vec<_> = items
            .iter()
            .map(|i| (i.name.clone(), i.from.clone(), i.to.clone()))
            .collect();
        ui.changes(&rows);
    }
}

fn update_all(ui: &Ui, o: &Options) -> Result<ExitCode, String> {
    let started = Instant::now();
    let _lock = sys::lock()?;
    let free = sys::free_gib()?;
    if free < MIN_FREE_GIB {
        return Err(format!("Only {free} GiB free on /, need at least {MIN_FREE_GIB} GiB"));
    }
    if !sys::online() {
        return Err("No network: neither google.com nor amazon.com answered".into());
    }

    let (checks, took) = ui.spin(&format!("Checking {} sources", o.steps.len()), || check::all(&o.steps));
    ui.heading(&format!("Checked in {}", ui::duration(took)));
    for c in &checks {
        plan_line(ui, c);
    }
    if o.check_only {
        return Ok(ExitCode::SUCCESS);
    }

    let todo: Vec<&Check> = checks.iter().filter(|c| c.has_work()).collect();
    if todo.is_empty() {
        println!();
        ui.heading("Everything is up to date.");
        return Ok(ExitCode::SUCCESS);
    }
    let count: usize = todo.iter().map(|c| c.count()).sum();
    let question = match count {
        0 => format!("Update {} sources?", todo.len()),
        n => format!("Update {n} items in {} sources?", todo.len()),
    };
    if !o.yes && !ui.confirm(&format!("\n{question}")) {
        ui.dim("Nothing changed.");
        return Ok(ExitCode::SUCCESS);
    }

    // The password once, before the live lines start.
    let _sudo = if o.snapshot || todo.iter().any(|c| c.step.needs_sudo()) {
        Some(sys::Sudo::ask()?)
    } else {
        None
    };
    let _awake = match sys::Awake::hold() {
        Ok(a) => Some(a),
        Err(e) => {
            ui.error(&format!("{e}; the machine may sleep during the update"));
            None
        }
    };
    let stamp = sys::local_time(sys::now(), "%Y-%m-%d_%H-%M-%S");
    let log_path = record::logs_dir().join(format!("{stamp}.log"));
    let log = Log::create(&log_path)?;
    record::prune_logs();
    log.line("Plan");
    for c in &todo {
        log.line(&format!("\n{}", c.step.name()));
        for i in items_of(c) {
            log.line(&format!("  {}", i.line()));
        }
    }
    println!();

    let snapshot = if o.snapshot {
        let (result, took) = ui.spin("Timeshift snapshot", || update::snapshot(&log));
        match result {
            Ok(tag) => {
                ui.line(Mark::Done, "Snapshot", Some(took), &tag);
                tag
            }
            Err(e) => {
                ui.line(Mark::Failed, "Snapshot", Some(took), "failed: nothing was updated");
                ui.note(&e);
                save(started, "failed".into(), &checks, &[], false, &log_path);
                return Ok(ExitCode::FAILURE);
            }
        }
    } else {
        "skipped".to_string()
    };

    let mut results: Vec<(steps::Step, Outcome, u64)> = Vec::new();
    for c in &todo {
        let (outcome, took) = ui.spin(c.step.name(), || update::run(&log, c));
        let (mark, detail) = match &outcome {
            Outcome::Done(d) => (Mark::Done, d.clone()),
            Outcome::Failed(e) => (Mark::Failed, e.lines().next().unwrap_or_default().to_string()),
            Outcome::Limited(e) => (Mark::Limited, format!("skipped: {e}")),
        };
        ui.line(mark, c.step.name(), Some(took), &detail);
        if let Outcome::Failed(e) = &outcome {
            ui.note(e.lines().skip(1).collect::<Vec<_>>().join("\n").as_str());
        }
        results.push((c.step, outcome, took.as_secs()));
    }

    let reboot = todo.iter().any(|c| c.step == steps::Step::Dnf) && update::reboot_needed();
    let run = save(started, snapshot, &checks, &results, reboot, &log_path);
    println!();
    ui.heading(&format!(
        "Done in {}: {}",
        ui::duration(started.elapsed()),
        run.headline()
    ));
    ui.dim(&format!("Log: {}", log_path.display()));
    notify(&run);
    Ok(if run.failed().is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    })
}

/// Record the run: each checked step with how its update went.
fn save(
    started: Instant,
    snapshot: String,
    checks: &[Check],
    results: &[(steps::Step, Outcome, u64)],
    reboot: bool,
    log: &std::path::Path,
) -> Run {
    let steps = checks
        .iter()
        .map(|c| {
            let result = results.iter().find(|(s, ..)| *s == c.step);
            let (status, detail, seconds) = match (result, &c.found) {
                (Some((_, Outcome::Done(d), t)), _) => ("updated", d.clone(), *t),
                (Some((_, Outcome::Failed(e), t)), _) => ("failed", e.clone(), *t),
                (Some((_, Outcome::Limited(e), t)), _) => ("rate-limited", e.clone(), *t),
                (None, Found::Absent(why)) => ("absent", why.clone(), 0),
                (None, Found::Limited(why)) => ("rate-limited", why.clone(), 0),
                (None, Found::Notice(what)) => ("notice", what.clone(), 0),
                (None, _) => ("up-to-date", String::new(), 0),
            };
            StepRecord {
                id: c.step.id().into(),
                name: c.step.name().into(),
                status: status.into(),
                count: if status == "updated" { c.count() } else { 0 },
                seconds,
                detail,
                // What it set out to change, for steps that ran.
                changes: if result.is_some() {
                    items_of(c).iter().map(|i| i.line()).collect()
                } else {
                    Vec::new()
                },
            }
        })
        .collect();
    let run = Run {
        time: sys::now(),
        seconds: started.elapsed().as_secs(),
        snapshot,
        steps,
        reboot,
        log: log.display().to_string(),
    };
    if let Err(e) = record::save(&run) {
        eprintln!("upi: {e}");
    }
    run
}

fn items_of(c: &Check) -> &[check::Item] {
    match &c.found {
        Found::Updates { items, .. } => items,
        _ => &[],
    }
}

/// A desktop notification with the outcome, for when the terminal is behind
/// other windows.
fn notify(run: &Run) {
    let title = if run.failed().is_empty() {
        "Updates done"
    } else {
        "Updates done, with failures"
    };
    let _ = sys::run(
        &Log::none(),
        "notify-send",
        &["-a", "upi", "-i", "system-software-update", title, &run.headline()],
    );
}
