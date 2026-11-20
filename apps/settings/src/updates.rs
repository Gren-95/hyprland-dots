//! Updates panel: run scripts/update-all.sh in a terminal (it asks for the
//! sudo password and shows every step live there), when it last finished
//! and how (~/.local/state/dots/last-update, written by the script), and
//! the Timeshift snapshots (`timeshift --list` needs root, so it runs
//! through pkexec, which asks for the password).

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::store::home;
use crate::style::Action;
use crate::system::{self, args};
use crate::ui;

/// update-all.sh's record: (unix time, "ok" or "failed: steps").
pub fn parse_last(text: &str) -> Option<(i64, String)> {
    let (time, result) = text.trim().split_once('\t')?;
    Some((time.parse().ok()?, result.to_string()))
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
        .join("dots/last-update")
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub last: Option<(i64, String)>,
    /// "Fri 20 Nov 14:02" for the last run.
    pub last_when: String,
}

fn read() -> Reading {
    let last = std::fs::read_to_string(last_update_file())
        .ok()
        .and_then(|t| parse_last(&t));
    let last_when = last
        .as_ref()
        .and_then(|(t, _)| system::run_blocking("date", &args(&["-d", &format!("@{t}"), "+%a %d %b %H:%M"]), None).ok())
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
    ListSnapshots,
    Snapshots(Result<String, String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(read), |r| Msg::Loaded(r.unwrap_or_default())),
            Msg::Loaded(r) => self.reading = Some(r),
            Msg::Run => {
                let script = home()
                    .join(".config/scripts/update-all.sh")
                    .to_string_lossy()
                    .into_owned();
                let list = vec![
                    "-f".into(),
                    "kitty".into(),
                    "--hold".into(),
                    "--title".into(),
                    "System update".into(),
                    "bash".into(),
                    script,
                ];
                return Task::perform(system::run("setsid", list, None), |r| Msg::Started(r.map(|_| ())));
            }
            Msg::Started(r) => {
                self.error = r
                    .err()
                    .map(|e| format!("Could not open the update terminal (kitty): {e}"));
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
        let last = match self
            .reading
            .as_ref()
            .and_then(|r| r.last.as_ref().map(|l| (l, &r.last_when)))
        {
            Some(((_, result), when)) if result == "ok" => format!("Last run {when}: every step worked"),
            Some(((_, result), when)) => format!("Last run {when}: {result}"),
            None => "Not run from here yet".into(),
        };
        rows.push(ui::item(
            ico::REFRESH_CW,
            "Update everything".into(),
            format!("{last} · opens a terminal, takes a snapshot first"),
            vec![ui::action("Run…", Some(Msg::Run), Action::Normal)],
        ));
        rows
    }

    pub fn snapshot_rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = vec![ui::item(
            ico::ARCHIVE,
            "Timeshift snapshots".into(),
            "Listing them asks for your password".into(),
            vec![ui::action(
                if self.snapshots.is_some() { "Refresh" } else { "Show" },
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
        assert_eq!(parse_last("1790000000\tok\n"), Some((1790000000, "ok".into())));
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
