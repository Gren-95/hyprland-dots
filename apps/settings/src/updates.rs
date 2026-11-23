//! Updates panel: run `upi` (apps/upi) in a terminal, where it lists what
//! would update, asks for the sudo password and shows each step live; how
//! the last run went (~/.local/state/dots/last-update.json, written by upi),
//! with any step that failed and its log; and the Timeshift snapshots
//! (`timeshift --list` needs root, so it runs through pkexec, which asks for
//! the password).

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::store::home;
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// One step of the last run that did not work: name, status, first line.
#[derive(Debug, Clone, PartialEq)]
pub struct Problem {
    pub name: String,
    pub limited: bool,
    pub detail: String,
}

/// upi's record of its last run.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct LastRun {
    pub time: i64,
    /// "17 updated · reboot needed".
    pub headline: String,
    pub problems: Vec<Problem>,
    pub log: String,
}

pub fn parse_last(text: &str) -> Option<LastRun> {
    let j: serde_json::Value = serde_json::from_str(text).ok()?;
    let steps = j["steps"].as_array()?;
    let status = |s: &serde_json::Value| s["status"].as_str().unwrap_or_default().to_string();
    let updated: u64 = steps
        .iter()
        .filter(|s| status(s) == "updated")
        .filter_map(|s| s["count"].as_u64())
        .sum();
    let problems: Vec<Problem> = steps
        .iter()
        .filter(|s| matches!(status(s).as_str(), "failed" | "rate-limited"))
        .map(|s| Problem {
            name: s["name"].as_str().unwrap_or_default().to_string(),
            limited: status(s) == "rate-limited",
            detail: s["detail"]
                .as_str()
                .unwrap_or_default()
                .lines()
                .next()
                .unwrap_or_default()
                .to_string(),
        })
        .collect();
    let mut parts = vec![if steps.iter().any(|s| status(s) == "updated") {
        format!("{updated} updated")
    } else {
        "nothing to update".to_string()
    }];
    let failed = problems.iter().filter(|p| !p.limited).count();
    if failed > 0 {
        parts.push(format!("{failed} failed"));
    }
    if j["snapshot"] == "failed" {
        parts.push("snapshot failed".into());
    }
    if j["reboot"].as_bool() == Some(true) {
        parts.push("reboot needed".into());
    }
    Some(LastRun {
        time: j["time"].as_i64()?,
        headline: parts.join(" · "),
        problems,
        log: j["log"].as_str().unwrap_or_default().to_string(),
    })
}

/// A Timeshift snapshot: (name, tags, description).
#[derive(Debug, Clone, PartialEq)]
pub struct Snapshot {
    pub name: String,
    pub tags: String,
    pub description: String,
}

/// `timeshift --list`: rows like "0    >  2026-11-10_12-00-01  D  pre-update".
pub fn parse_snapshots(out: &str) -> Vec<Snapshot> {
    out.lines()
        .filter_map(|l| {
            let mut words = l.split_whitespace().peekable();
            words.next()?.parse::<u32>().ok()?;
            if words.peek() == Some(&">") {
                words.next();
            }
            let name = words.next()?.to_string();
            if !name.starts_with(|c: char| c.is_ascii_digit()) {
                return None;
            }
            let rest: Vec<&str> = words.collect();
            let (tags, description) = match rest.first() {
                Some(t) if t.chars().all(|c| "ODWMHB".contains(c)) => (t.to_string(), rest[1..].join(" ")),
                _ => (String::new(), rest.join(" ")),
            };
            Some(Snapshot {
                name,
                tags,
                description,
            })
        })
        .collect()
}

fn last_update_file() -> std::path::PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| home().join(".local/state"))
        .join("dots/last-update.json")
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub last: Option<LastRun>,
    /// "Fri 20 Nov 14:02" for the last run.
    pub last_when: String,
}

fn read() -> Reading {
    let last = std::fs::read_to_string(last_update_file())
        .ok()
        .and_then(|t| parse_last(&t));
    let last_when = last
        .as_ref()
        .and_then(|l| {
            system::run_blocking("date", &args(&["-d", &format!("@{}", l.time), "+%a %d %b %H:%M"]), None).ok()
        })
        .map(|s| s.trim().to_string())
        .unwrap_or_default();
    Reading { last, last_when }
}

#[derive(Default)]
pub struct State {
    reading: Option<Reading>,
    snapshots: Option<Vec<Snapshot>>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Reading),
    Run,
    Started(Result<(), String>),
    OpenLog(String),
    ListSnapshots,
    Snapshots(Result<String, String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => self.reading = Some(r),
            Msg::Run => {
                let upi = home().join(".local/bin/upi").to_string_lossy().into_owned();
                let list = args(&["-f", "kitty", "--hold", "--title", "System update"])
                    .into_iter()
                    .chain([upi])
                    .collect();
                return Task::perform(system::run("setsid", list, None), |r| Msg::Started(r.map(|_| ())));
            }
            Msg::OpenLog(path) => {
                return Task::perform(system::run("xdg-open", vec![path], None), |r| {
                    Msg::Started(r.map(|_| ()))
                });
            }
            Msg::Started(r) => {
                self.error = r.err().map(|e| format!("Could not open it: {e}"));
            }
            Msg::ListSnapshots => {
                self.busy = true;
                return Task::perform(
                    system::run("pkexec", args(&["timeshift", "--list"]), None),
                    Msg::Snapshots,
                );
            }
            Msg::Snapshots(r) => {
                self.busy = false;
                match r {
                    Ok(out) => {
                        self.snapshots = Some(parse_snapshots(&out));
                        self.error = None;
                    }
                    Err(e) => self.error = Some(system::polkit_error(&e).replace("Not changed", "Not listed")),
                }
            }
        }
        Task::none()
    }

    pub fn update_rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        let last = self
            .reading
            .as_ref()
            .and_then(|r| r.last.as_ref().map(|l| (l, &r.last_when)));
        let detail = match last {
            Some((l, when)) => format!("Last run {when}: {}", l.headline),
            None => "Not run yet".into(),
        };
        let mut controls = Vec::new();
        if let Some((l, _)) = last.filter(|(l, _)| !l.log.is_empty()) {
            controls.push(ui::icon_action(
                ico::FILE_TEXT,
                "Open the log",
                Some(Msg::OpenLog(l.log.clone())),
                Action::Normal,
            ));
        }
        controls.push(ui::icon_action(ico::PLAY, "Run upi", Some(Msg::Run), Action::Normal));
        rows.push(ui::item(ico::REFRESH_CW, "Update everything".into(), detail, controls));
        // What did not work last time, under the row.
        if let Some((l, _)) = last {
            let count = l.problems.len();
            for (i, p) in l.problems.iter().enumerate() {
                let glyph = if p.limited { ico::CLOCK } else { ico::CIRCLE_X };
                let detail = if p.limited {
                    format!("Skipped: {}", p.detail)
                } else {
                    p.detail.clone()
                };
                rows.push(ui::branch(
                    ui::item(glyph, p.name.clone(), detail, vec![]),
                    i + 1 == count,
                ));
            }
        }
        rows
    }

    pub fn snapshot_rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = vec![ui::item(
            ico::ARCHIVE,
            "Timeshift snapshots".into(),
            "Needs password".into(),
            vec![ui::icon_action(
                if self.snapshots.is_some() {
                    ico::REFRESH_CW
                } else {
                    ico::LIST
                },
                if self.snapshots.is_some() {
                    "Refresh"
                } else {
                    "Show them"
                },
                (!self.busy).then_some(Msg::ListSnapshots),
                Action::Normal,
            )],
        )];
        match &self.snapshots {
            Some(list) if list.is_empty() => rows.push(ui::note("No snapshots")),
            Some(list) => {
                // Newest first.
                for s in list.iter().rev() {
                    let detail = match (s.description.is_empty(), s.tags.is_empty()) {
                        (true, true) => String::new(),
                        (true, false) => format!("Tags {}", s.tags),
                        (false, true) => s.description.clone(),
                        (false, false) => format!("{} · tags {}", s.description, s.tags),
                    };
                    rows.push(ui::item(ico::HARD_DRIVE, s.name.replace('_', " "), detail, vec![]));
                }
            }
            None => {}
        }
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_last_update_and_snapshots() {
        let json = r#"{"time": 1790000000, "seconds": 250, "snapshot": "2026-11-20_14-00-01",
            "steps": [
              {"id": "dnf", "name": "System packages", "status": "updated", "count": 12, "seconds": 130, "detail": "12 updated"},
              {"id": "npm", "name": "npm globals", "status": "failed", "count": 0, "seconds": 4, "detail": "npm update exited with 1:\nE404"},
              {"id": "bun", "name": "bun", "status": "rate-limited", "count": 0, "seconds": 0, "detail": "GitHub API limit"}
            ], "reboot": true, "log": "/tmp/x.log"}"#;
        let last = parse_last(json).unwrap();
        assert_eq!(last.headline, "12 updated · 1 failed · reboot needed");
        assert_eq!(last.problems.len(), 2);
        assert_eq!(last.problems[0].detail, "npm update exited with 1:");
        assert!(last.problems[1].limited);
        assert_eq!(last.log, "/tmp/x.log");
        assert_eq!(parse_last("x"), None);
        let out = "Device : /dev/nvme0n1p3\n\nNum     Name                 Tags  Description\n------------------------------------------------------------------------------\n0    >  2026-11-10_12-00-01  D     \n1    >  2026-11-19_20-00-02  O     pre-update run\n";
        assert_eq!(
            parse_snapshots(out),
            [
                Snapshot {
                    name: "2026-11-10_12-00-01".into(),
                    tags: "D".into(),
                    description: String::new()
                },
                Snapshot {
                    name: "2026-11-19_20-00-02".into(),
                    tags: "O".into(),
                    description: "pre-update run".into()
                }
            ]
        );
    }
}
