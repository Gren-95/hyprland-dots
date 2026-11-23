//! What the last run did, for `upi --last` and the settings app's Updates
//! panel (~/.local/state/dots/last-update.json), and the run logs
//! (~/.local/state/dots/updates/<time>.log, the newest KEEP_LOGS kept).

use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::sys;

const KEEP_LOGS: usize = 20;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StepRecord {
    pub id: String,
    pub name: String,
    /// "updated", "up-to-date", "failed", "rate-limited", "absent".
    pub status: String,
    pub count: usize,
    pub seconds: u64,
    pub detail: String,
    /// "firefox 158.0.1-2.fc44 → 160.0-1.fc44" for each planned change.
    pub changes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Run {
    /// Unix time the run finished.
    pub time: i64,
    pub seconds: u64,
    /// The snapshot tag, "skipped", or "failed".
    pub snapshot: String,
    pub steps: Vec<StepRecord>,
    pub reboot: bool,
    /// The full output of the run.
    pub log: String,
}

impl Run {
    pub fn failed(&self) -> Vec<&str> {
        self.steps
            .iter()
            .filter(|s| s.status == "failed")
            .map(|s| s.name.as_str())
            .collect()
    }

    pub fn updated(&self) -> usize {
        self.steps
            .iter()
            .filter(|s| s.status == "updated")
            .map(|s| s.count)
            .sum()
    }

    /// One line: "17 updated · npm globals failed · reboot needed".
    pub fn headline(&self) -> String {
        let mut parts = vec![match self.updated() {
            0 if self.steps.iter().all(|s| s.status != "updated") => "nothing to update".to_string(),
            n => format!("{n} updated"),
        }];
        let failed = self.failed();
        if !failed.is_empty() {
            parts.push(format!("{} failed", failed.join(", ")));
        }
        if self.steps.iter().any(|s| s.status == "rate-limited") {
            parts.push("some skipped for the GitHub limit".into());
        }
        if self.reboot {
            parts.push("reboot needed".into());
        }
        parts.join(" · ")
    }
}

fn record_path() -> PathBuf {
    sys::state_dir().join("last-update.json")
}

pub fn logs_dir() -> PathBuf {
    sys::state_dir().join("updates")
}

pub fn save(run: &Run) -> Result<(), String> {
    let path = record_path();
    let tmp = path.with_extension("json.tmp");
    let text = serde_json::to_string_pretty(run).map_err(|e| e.to_string())?;
    std::fs::create_dir_all(sys::state_dir())
        .and_then(|()| std::fs::write(&tmp, text))
        .and_then(|()| std::fs::rename(&tmp, &path))
        .map_err(|e| format!("could not save {}: {e}", path.display()))
}

pub fn load() -> Result<Run, String> {
    let path = record_path();
    let text = std::fs::read_to_string(&path).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => "No run recorded yet".to_string(),
        _ => format!("could not read {}: {e}", path.display()),
    })?;
    serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))
}

/// Keep the newest logs; their names sort by time.
pub fn prune_logs() {
    let Ok(entries) = std::fs::read_dir(logs_dir()) else {
        return;
    };
    let mut logs: Vec<PathBuf> = entries
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|x| x == "log"))
        .collect();
    logs.sort();
    let old = logs.len().saturating_sub(KEEP_LOGS);
    for p in &logs[..old] {
        let _ = std::fs::remove_file(p);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn step(id: &str, status: &str, count: usize) -> StepRecord {
        StepRecord {
            id: id.into(),
            name: id.into(),
            status: status.into(),
            count,
            seconds: 1,
            detail: String::new(),
            changes: Vec::new(),
        }
    }

    #[test]
    fn sums_up_a_run() {
        let mut run = Run {
            time: 1,
            seconds: 9,
            snapshot: "skipped".into(),
            steps: vec![
                step("dnf", "updated", 12),
                step("npm", "failed", 0),
                step("bun", "up-to-date", 0),
            ],
            reboot: true,
            log: "/tmp/x.log".into(),
        };
        assert_eq!(run.headline(), "12 updated · npm failed · reboot needed");
        let back: Run = serde_json::from_str(&serde_json::to_string(&run).unwrap()).unwrap();
        assert_eq!(back, run);
        run.steps = vec![step("dnf", "up-to-date", 0)];
        run.reboot = false;
        assert_eq!(run.headline(), "nothing to update");
    }
}
