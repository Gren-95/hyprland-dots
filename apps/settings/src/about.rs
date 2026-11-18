//! About panel: what the system is, and a button that copies it all as
//! text for bug reports.

use iced::widget::{Column, container, row, text};
use iced::{Alignment, Element, Length, Task};

use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

/// (label, value) pairs in display order.
pub type Facts = Vec<(&'static str, String)>;

#[derive(Default)]
pub struct State {
    facts: Option<Facts>,
    copied: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Facts),
    Copy,
    Copied(Result<(), String>),
}

fn read(path: &str) -> String {
    std::fs::read_to_string(path).unwrap_or_default().trim().to_string()
}

/// A value from `KEY=value` or `KEY="value"` lines (os-release).
pub fn os_release_value(text: &str, key: &str) -> String {
    text.lines()
        .find_map(|l| l.strip_prefix(&format!("{key}=")))
        .map(|v| v.trim_matches('"').to_string())
        .unwrap_or_default()
}

/// The first "model name" of /proc/cpuinfo.
pub fn cpu_model(cpuinfo: &str) -> String {
    cpuinfo
        .lines()
        .find_map(|l| {
            l.strip_prefix("model name")
                .and_then(|r| r.split_once(':'))
                .map(|(_, v)| v.trim().to_string())
        })
        .unwrap_or_default()
}

/// MemTotal of /proc/meminfo as "15.0 GiB".
pub fn memory(meminfo: &str) -> String {
    meminfo
        .lines()
        .find_map(|l| l.strip_prefix("MemTotal:"))
        .and_then(|v| v.split_whitespace().next()?.parse::<f64>().ok())
        .map(|kib| format!("{:.1} GiB", kib / 1024.0 / 1024.0))
        .unwrap_or_default()
}

/// `df --output=source,target,size,avail`: the root and /home and /mnt
/// mounts, once per device.
pub fn disks(df: &str) -> String {
    let mut seen = std::collections::HashSet::new();
    df.lines()
        .skip(1)
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let (source, target, size, avail) = (*f.first()?, *f.get(1)?, *f.get(2)?, *f.get(3)?);
            let wanted = target == "/" || target.starts_with("/home") || target.starts_with("/mnt");
            (wanted && seen.insert(source.to_string())).then(|| format!("{target} {size} ({avail} free)"))
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn run(program: &str, list: &[&str]) -> String {
    system::run_blocking(program, &args(list), None)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

/// The dots repository: where ~/.config/hypr really lives, two levels up.
fn repo() -> Option<std::path::PathBuf> {
    let hypr = std::fs::canonicalize(crate::store::home().join(".config/hypr")).ok()?;
    Some(hypr.parent()?.parent()?.to_path_buf())
}

fn load() -> Facts {
    let os = read("/etc/os-release");
    let gpus: Vec<String> = run("lspci", &[])
        .lines()
        .filter(|l| l.contains("VGA") || l.contains("3D controller"))
        .filter_map(|l| l.split_once(": ").map(|(_, g)| g.to_string()))
        .collect();
    let disks = disks(&run(
        "df",
        &[
            "-h",
            "--output=source,target,size,avail",
            "-x",
            "tmpfs",
            "-x",
            "devtmpfs",
            "-x",
            "efivarfs",
        ],
    ));
    let hyprland = system::run_blocking("hyprctl", &args(&["version", "-j"]), None)
        .ok()
        .and_then(|j| serde_json::from_str::<serde_json::Value>(&j).ok())
        .and_then(|v| v["tag"].as_str().map(String::from))
        .unwrap_or_default();
    let quickshell = run("qs", &["--version"]);
    let quickshell = quickshell
        .split(" (")
        .next()
        .unwrap_or_default()
        .trim_start_matches("Quickshell ")
        .to_string();
    let dots = repo()
        .map(|r| {
            let dir = r.to_string_lossy().into_owned();
            let commit = run("git", &["-C", &dir, "log", "-1", "--format=%h %s"]);
            let dirty = if run("git", &["-C", &dir, "status", "--porcelain"]).is_empty() {
                ""
            } else {
                " (changed files)"
            };
            format!("{commit}{dirty}")
        })
        .unwrap_or_default();
    vec![
        (
            "Computer",
            format!(
                "{} {}",
                read("/sys/class/dmi/id/sys_vendor"),
                read("/sys/class/dmi/id/product_name")
            )
            .trim()
            .to_string(),
        ),
        ("Name", run("hostname", &[])),
        ("System", os_release_value(&os, "PRETTY_NAME")),
        ("Kernel", run("uname", &["-r"])),
        ("Hyprland", hyprland),
        ("Quickshell", quickshell),
        ("Processor", cpu_model(&read("/proc/cpuinfo"))),
        ("Graphics", gpus.join(", ")),
        ("Memory", memory(&read("/proc/meminfo"))),
        ("Disks", disks),
        ("Dots", dots),
        ("Settings app", env!("CARGO_PKG_VERSION").to_string()),
    ]
}

/// The facts as plain text, one per line.
pub fn as_text(facts: &Facts) -> String {
    facts
        .iter()
        .filter(|(_, v)| !v.is_empty())
        .map(|(k, v)| format!("{k}: {v}\n"))
        .collect()
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |f| Msg::Loaded(f.unwrap_or_default())),
            Msg::Loaded(f) => {
                self.facts = Some(f);
                self.copied = false;
            }
            Msg::Copy => {
                if let Some(f) = &self.facts {
                    return Task::perform(system::run("wl-copy", vec![], Some(as_text(f))), |r| {
                        Msg::Copied(r.map(|_| ()))
                    });
                }
            }
            Msg::Copied(r) => {
                self.copied = r.is_ok();
                self.error = r.err();
            }
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(facts) = &self.facts else {
            return ui::section(body, "This system", vec![ui::note("Loading…")]);
        };
        let mut rows: Vec<Element<'a, Msg>> = facts
            .iter()
            .filter(|(_, v)| !v.is_empty())
            .map(|(k, v)| {
                let line = row![
                    text(*k).size(13).color(style::FG_MUTED).width(130),
                    text(v.clone()).size(14).color(style::FG).width(Length::Fill),
                ]
                .spacing(12)
                .align_y(Alignment::Center);
                container(line).padding([8, 14]).into()
            })
            .collect();
        let label = if self.copied { "Copied" } else { "Copy as text" };
        rows.push(
            container(
                row![
                    text("For bug reports: everything above, as text")
                        .size(12)
                        .color(style::MUTED_DEEP)
                        .width(Length::Fill),
                    ui::action(label, Some(Msg::Copy), Action::Primary),
                ]
                .align_y(Alignment::Center),
            )
            .padding([8, 14])
            .into(),
        );
        ui::section(body, "This system", rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_system_files() {
        assert_eq!(
            os_release_value("NAME=\"Nobara\"\nPRETTY_NAME=\"Nobara Linux 44\"\n", "PRETTY_NAME"),
            "Nobara Linux 44"
        );
        assert_eq!(
            cpu_model("processor\t: 0\nmodel name\t: 13th Gen Intel(R) Core(TM) i5-1345U\n"),
            "13th Gen Intel(R) Core(TM) i5-1345U"
        );
        assert_eq!(memory("MemTotal:       15686628 kB\n"), "15.0 GiB");
        assert_eq!(memory("nothing"), "");
    }

    #[test]
    fn lists_each_disk_once() {
        let df = "Filesystem Mounted Size Avail\n/dev/nvme0n1p3 / 460G 145G\n/dev/nvme0n1p3 /home 460G 145G\n/dev/sda1 /mnt/DATA 1.4T 393G\n/dev/nvme0n1p1 /boot 1G 500M\n";
        assert_eq!(disks(df), "/ 460G (145G free), /mnt/DATA 1.4T (393G free)");
    }

    #[test]
    fn copies_known_facts_only() {
        let facts = vec![("Kernel", "6.1".to_string()), ("Graphics", String::new())];
        assert_eq!(as_text(&facts), "Kernel: 6.1\n");
    }
}
