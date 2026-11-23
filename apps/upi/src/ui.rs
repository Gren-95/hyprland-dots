//! Terminal output: a spinner with the elapsed time while something runs,
//! then one line per step. Plain lines when stdout is not a terminal.

use std::io::{IsTerminal, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

const FRAMES: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
pub const NAME_WIDTH: usize = 17;

/// How a line starts: its mark and colour.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mark {
    /// Updated, or worked.
    Done,
    /// Has updates waiting.
    Pending,
    UpToDate,
    Failed,
    /// Skipped for the GitHub rate limit.
    Limited,
    /// Not installed.
    Absent,
}

impl Mark {
    fn glyph(self) -> &'static str {
        match self {
            Mark::Done => "✔",
            Mark::Pending => "↑",
            Mark::UpToDate => "✔",
            Mark::Failed => "✖",
            Mark::Limited => "↷",
            Mark::Absent => "·",
        }
    }

    fn colour(self) -> &'static str {
        match self {
            Mark::Done => "\x1b[1;32m",
            Mark::Pending => "\x1b[1;33m",
            Mark::UpToDate => "\x1b[2;32m",
            Mark::Failed => "\x1b[1;31m",
            Mark::Limited => "\x1b[33m",
            Mark::Absent => "\x1b[2m",
        }
    }
}

pub struct Ui {
    tty: bool,
}

impl Ui {
    pub fn new() -> Ui {
        Ui {
            tty: std::io::stdout().is_terminal(),
        }
    }

    fn paint(&self, colour: &str, text: &str) -> String {
        if self.tty {
            format!("{colour}{text}\x1b[0m")
        } else {
            text.to_string()
        }
    }

    pub fn heading(&self, text: &str) {
        println!("{}", self.paint("\x1b[1;34m", text));
    }

    pub fn error(&self, text: &str) {
        eprintln!("{}", self.paint("\x1b[1;31m", &format!("!! {text}")));
    }

    pub fn dim(&self, text: &str) {
        println!("{}", self.paint("\x1b[2m", text));
    }

    /// `work` on this thread with a spinner beside `label` until it ends.
    pub fn spin<T>(&self, label: &str, work: impl FnOnce() -> T) -> (T, Duration) {
        let start = Instant::now();
        if !self.tty {
            return (work(), start.elapsed());
        }
        let done = AtomicBool::new(false);
        let result = thread::scope(|s| {
            s.spawn(|| {
                let mut i = 0;
                while !done.load(Ordering::Relaxed) {
                    print!(
                        "\r\x1b[2K\x1b[1;34m{}\x1b[0m {label} \x1b[2m{}\x1b[0m",
                        FRAMES[i % FRAMES.len()],
                        duration(start.elapsed())
                    );
                    let _ = std::io::stdout().flush();
                    i += 1;
                    thread::sleep(Duration::from_millis(100));
                }
                print!("\r\x1b[2K");
                let _ = std::io::stdout().flush();
            });
            let r = work();
            done.store(true, Ordering::Relaxed);
            r
        });
        (result, start.elapsed())
    }

    /// One result line: mark, name, time taken, what happened.
    pub fn line(&self, mark: Mark, name: &str, took: Option<Duration>, detail: &str) {
        let took = took.map(duration).unwrap_or_default();
        let name = format!("{name:<NAME_WIDTH$}");
        println!(
            "{} {} {} {detail}",
            self.paint(mark.colour(), mark.glyph()),
            name,
            self.paint("\x1b[2m", &format!("{took:>9}"))
        );
    }

    /// A line under a step, indented.
    pub fn note(&self, text: &str) {
        for l in text.lines() {
            println!("    {}", self.paint("\x1b[2m", l));
        }
    }

    /// Ask a yes/no question; Enter is yes.
    pub fn confirm(&self, question: &str) -> bool {
        print!("{} [Y/n] ", self.paint("\x1b[1m", question));
        let _ = std::io::stdout().flush();
        let mut answer = String::new();
        if std::io::stdin().read_line(&mut answer).is_err() {
            return false;
        }
        matches!(answer.trim().to_lowercase().as_str(), "" | "y" | "yes")
    }
}

impl Ui {
    /// Rows of (name, from, to), in aligned columns under a step.
    pub fn changes(&self, rows: &[(String, String, String)]) {
        let width = |pick: fn(&(String, String, String)) -> &String| {
            rows.iter().map(|r| pick(r).chars().count()).max().unwrap_or(0).min(40)
        };
        let (name_w, from_w) = (width(|r| &r.0), width(|r| &r.1));
        for (name, from, to) in rows {
            let to = if to.is_empty() { "newer" } else { to };
            println!(
                "    {name:<name_w$}  {} {}",
                self.paint("\x1b[2m", &format!("{from:<from_w$} →")),
                self.paint("\x1b[1m", to)
            );
        }
    }
}

/// "38 s", "2 m 10 s", "1 h 3 m".
pub fn duration(d: Duration) -> String {
    let s = d.as_secs();
    match s {
        0..60 => format!("{s} s"),
        60..3600 => format!("{} m {} s", s / 60, s % 60),
        _ => format!("{} h {} m", s / 3600, s % 3600 / 60),
    }
}

/// "12 · firefox, mesa, kernel +9", with notes after.
pub fn summary(items: &[String], notes: &[String]) -> String {
    let mut parts = Vec::new();
    if !items.is_empty() {
        let shown: Vec<&str> = items.iter().take(3).map(String::as_str).collect();
        let more = items.len().saturating_sub(3);
        let more = if more > 0 { format!(" +{more}") } else { String::new() };
        parts.push(format!("{} · {}{more}", items.len(), shown.join(", ")));
    }
    parts.extend(notes.iter().cloned());
    parts.join(" · ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats() {
        assert_eq!(duration(Duration::from_secs(38)), "38 s");
        assert_eq!(duration(Duration::from_secs(130)), "2 m 10 s");
        assert_eq!(duration(Duration::from_secs(3780)), "1 h 3 m");
        let items: Vec<String> = ["a", "b", "c", "d"].map(String::from).into();
        assert_eq!(summary(&items, &["kernel 6.12".into()]), "4 · a, b, c +1 · kernel 6.12");
        assert_eq!(summary(&items[..1], &[]), "1 · a");
        assert_eq!(summary(&[], &["2 to remove".into()]), "2 to remove");
    }
}
