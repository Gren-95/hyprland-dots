//! About panel: what the system is, shown as a header with the distro logo,
//! hardware tiles, storage meters and software versions, plus a button that
//! copies it all as text for bug reports.

use std::path::{Path, PathBuf};

use iced::widget::{Column, Row, Space, column, container, image, progress_bar, row, svg, text};
use iced::{Alignment, Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

const LOGO: f32 = 84.0;
/// Height of a hardware tile: two lines of value, a meter and a detail.
const TILE: f32 = 124.0;

/// One mounted disk, as df shows it.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Disk {
    pub mount: String,
    pub size: String,
    pub avail: String,
    /// Share in use, 0..1.
    pub used: f32,
}

#[derive(Debug, Clone, Default)]
pub struct Info {
    pub logo: Option<PathBuf>,
    pub system: String,
    pub computer: String,
    pub host: String,
    pub uptime_secs: u64,
    pub cpu: String,
    pub threads: usize,
    pub gpus: Vec<String>,
    pub mem_total_kib: u64,
    pub mem_avail_kib: u64,
    pub disks: Vec<Disk>,
    pub kernel: String,
    pub hyprland: String,
    pub quickshell: String,
    pub dots: String,
    pub app: String,
}

#[derive(Default)]
pub struct State {
    info: Option<Info>,
    copied: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Box<Info>),
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

/// The first "model name" of /proc/cpuinfo and the number of threads.
pub fn cpu(cpuinfo: &str) -> (String, usize) {
    let model = cpuinfo
        .lines()
        .find_map(|l| {
            l.strip_prefix("model name")
                .and_then(|r| r.split_once(':'))
                .map(|(_, v)| cpu_name(v.trim()))
        })
        .unwrap_or_default();
    let threads = cpuinfo.lines().filter(|l| l.starts_with("processor")).count();
    (model, threads)
}

/// A /proc/meminfo field in KiB.
pub fn meminfo_kib(meminfo: &str, key: &str) -> u64 {
    meminfo
        .lines()
        .find_map(|l| l.strip_prefix(&format!("{key}:")))
        .and_then(|v| v.split_whitespace().next()?.parse().ok())
        .unwrap_or(0)
}

/// An lspci device name without the trailing "(rev 04)" and the vendor's
/// "Corporation".
pub fn gpu_name(name: &str) -> String {
    let name = name.rfind(" (rev ").map_or(name, |i| &name[..i]);
    name.replace(" Corporation", "")
}

/// A CPU model without the (R) and (TM) marks.
pub fn cpu_name(model: &str) -> String {
    model.replace("(R)", "").replace("(TM)", "")
}

fn gib(kib: u64) -> String {
    format!("{:.1} GiB", kib as f64 / 1024.0 / 1024.0)
}

/// Seconds as "3 days 4 h", "2 h 5 min" or "12 min".
pub fn duration(secs: u64) -> String {
    let (days, hours, mins) = (secs / 86400, secs / 3600 % 24, secs / 60 % 60);
    match (days, hours) {
        (0, 0) => format!("{mins} min"),
        (0, h) => format!("{h} h {mins} min"),
        (1, h) => format!("1 day {h} h"),
        (d, h) => format!("{d} days {h} h"),
    }
}

/// `df -h --output=source,target,size,avail,pcent`: the root and /home and
/// /mnt mounts, once per device.
pub fn disks(df: &str) -> Vec<Disk> {
    let mut seen = std::collections::HashSet::new();
    df.lines()
        .skip(1)
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let (source, mount) = (*f.first()?, *f.get(1)?);
            let wanted = mount == "/" || mount.starts_with("/home") || mount.starts_with("/mnt");
            (wanted && seen.insert(source.to_string())).then(|| Disk {
                mount: mount.to_string(),
                size: f.get(2).unwrap_or(&"").to_string(),
                avail: f.get(3).unwrap_or(&"").to_string(),
                used: f
                    .get(4)
                    .and_then(|p| p.trim_end_matches('%').parse::<f32>().ok())
                    .unwrap_or(0.0)
                    / 100.0,
            })
        })
        .collect()
}

/// The distro logo named by os-release LOGO: the largest hicolor icon, or
/// one in pixmaps.
fn logo(name: &str) -> Option<PathBuf> {
    if name.is_empty() {
        return None;
    }
    let hicolor = Path::new("/usr/share/icons/hicolor");
    let sizes = ["scalable", "512x512", "256x256", "128x128", "96x96", "64x64", "48x48"];
    let candidates = sizes
        .iter()
        .flat_map(|s| ["svg", "png"].map(|ext| hicolor.join(s).join("apps").join(format!("{name}.{ext}"))))
        .chain(["svg", "png"].map(|ext| Path::new("/usr/share/pixmaps").join(format!("{name}.{ext}"))));
    candidates.into_iter().find(|p| p.is_file())
}

fn run(program: &str, list: &[&str]) -> String {
    system::run_blocking(program, &args(list), None)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

/// The dots repository: where ~/.config/hypr really lives, two levels up.
fn repo() -> Option<PathBuf> {
    let hypr = std::fs::canonicalize(crate::store::home().join(".config/hypr")).ok()?;
    Some(hypr.parent()?.parent()?.to_path_buf())
}

fn dots() -> String {
    let Some(dir) = repo() else { return String::new() };
    let dir = dir.to_string_lossy().into_owned();
    let commit = run("git", &["-C", &dir, "log", "-1", "--format=%h %s"]);
    let changed = !run("git", &["-C", &dir, "status", "--porcelain"]).is_empty();
    format!("{commit}{}", if changed { " (changed files)" } else { "" })
}

fn load() -> Info {
    let os = read("/etc/os-release");
    let meminfo = read("/proc/meminfo");
    let (cpu, threads) = cpu(&read("/proc/cpuinfo"));
    let df = run(
        "df",
        &[
            "-h",
            "--output=source,target,size,avail,pcent",
            "-x",
            "tmpfs",
            "-x",
            "devtmpfs",
            "-x",
            "efivarfs",
        ],
    );
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
    Info {
        logo: logo(&os_release_value(&os, "LOGO")),
        system: os_release_value(&os, "PRETTY_NAME"),
        computer: format!(
            "{} {}",
            read("/sys/class/dmi/id/sys_vendor"),
            read("/sys/class/dmi/id/product_name")
        )
        .trim()
        .to_string(),
        host: run("hostname", &[]),
        uptime_secs: read("/proc/uptime")
            .split('.')
            .next()
            .and_then(|s| s.parse().ok())
            .unwrap_or(0),
        cpu,
        threads,
        gpus: run("lspci", &[])
            .lines()
            .filter(|l| l.contains("VGA") || l.contains("3D controller"))
            .filter_map(|l| l.split_once(": ").map(|(_, g)| gpu_name(g)))
            .collect(),
        mem_total_kib: meminfo_kib(&meminfo, "MemTotal"),
        mem_avail_kib: meminfo_kib(&meminfo, "MemAvailable"),
        disks: disks(&df),
        kernel: run("uname", &["-r"]),
        hyprland,
        quickshell,
        dots: dots(),
        app: env!("CARGO_PKG_VERSION").to_string(),
    }
}

/// Everything as plain text, one fact per line, empty ones left out.
pub fn as_text(i: &Info) -> String {
    let disks: Vec<String> = i
        .disks
        .iter()
        .map(|d| format!("{} {} ({} free)", d.mount, d.size, d.avail))
        .collect();
    let facts = [
        ("Computer", i.computer.clone()),
        ("Name", i.host.clone()),
        ("System", i.system.clone()),
        ("Kernel", i.kernel.clone()),
        ("Hyprland", i.hyprland.clone()),
        ("Quickshell", i.quickshell.clone()),
        (
            "Processor",
            if i.cpu.is_empty() {
                String::new()
            } else {
                format!("{} ({} threads)", i.cpu, i.threads)
            },
        ),
        ("Graphics", i.gpus.join(", ")),
        (
            "Memory",
            if i.mem_total_kib == 0 {
                String::new()
            } else {
                gib(i.mem_total_kib)
            },
        ),
        ("Disks", disks.join(", ")),
        ("Dots", i.dots.clone()),
        ("Settings app", i.app.clone()),
    ];
    facts
        .iter()
        .filter(|(_, v)| !v.is_empty())
        .map(|(k, v)| format!("{k}: {v}\n"))
        .collect()
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => return Task::perform(system::spawn(load), |i| Msg::Loaded(Box::new(i.unwrap_or_default()))),
            Msg::Loaded(i) => {
                self.info = Some(*i);
                self.copied = false;
            }
            Msg::Copy => {
                if let Some(i) = &self.info {
                    return Task::perform(system::run("wl-copy", vec![], Some(as_text(i))), |r| {
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
        let Some(i) = &self.info else {
            return ui::section(body, "This system", vec![ui::note("Loading…")]);
        };
        body = body.push(hero(i));
        body = body.push(heading("Hardware")).push(hardware(i));
        if !i.disks.is_empty() {
            body = ui::section(body, "Storage", i.disks.iter().map(disk).collect());
        }
        let software = [
            (ico::BOX, "Kernel", i.kernel.as_str()),
            (ico::LAYOUT_GRID, "Hyprland", i.hyprland.as_str()),
            (ico::PANELS_TOP_LEFT, "Quickshell", i.quickshell.as_str()),
            (ico::GIT_COMMIT_HORIZONTAL, "Dots", i.dots.as_str()),
            (ico::SETTINGS, "Settings app", i.app.as_str()),
        ];
        let rows = software
            .into_iter()
            .filter(|(_, _, v)| !v.is_empty())
            .map(|(g, k, v)| fact(g, k, v))
            .collect();
        body = ui::section(body, "Software", rows);
        let label = if self.copied {
            "Copied to the clipboard"
        } else {
            "Copy as text"
        };
        body.push(
            row![
                text("For bug reports: all of the above, as text")
                    .size(12)
                    .color(style::MUTED_DEEP)
                    .width(Length::Fill),
                ui::action(label, Some(Msg::Copy), Action::Primary),
            ]
            .align_y(Alignment::Center)
            .padding([4, 6]),
        )
    }
}

fn heading<'a>(title: &str) -> Element<'a, Msg> {
    column![
        Space::new().height(8),
        text(title.to_uppercase())
            .font(style::FONT_BOLD)
            .size(11)
            .color(style::MUTED_DEEP)
    ]
    .into()
}

/// Logo, system name, computer, and chips for the host name and uptime.
fn hero(i: &Info) -> Element<'_, Msg> {
    let logo: Element<'_, Msg> = match &i.logo {
        Some(p) if p.extension().is_some_and(|e| e == "svg") => {
            svg(svg::Handle::from_path(p)).width(LOGO).height(LOGO).into()
        }
        Some(p) => image(image::Handle::from_path(p)).width(LOGO).height(LOGO).into(),
        None => ui::icon(ico::MONITOR, LOGO * 0.6),
    };
    let mut chips = Row::new().spacing(8);
    if !i.host.is_empty() {
        chips = chips.push(chip(ico::AT_SIGN, i.host.clone()));
    }
    if i.uptime_secs > 0 {
        chips = chips.push(chip(ico::CLOCK, format!("Up {}", duration(i.uptime_secs))));
    }
    let info = column![
        text(i.system.clone()).font(style::FONT_BOLD).size(26).color(style::FG),
        text(i.computer.clone()).size(14).color(style::FG_MUTED),
        Space::new().height(6),
        chips,
    ]
    .spacing(2);
    container(
        row![container(logo).center_x(LOGO + 8.0).center_y(LOGO + 8.0), info]
            .spacing(20)
            .align_y(Alignment::Center),
    )
    .padding([22, 24])
    .width(Length::Fill)
    .style(style::hero)
    .into()
}

fn chip<'a>(glyph: ui::Icon, label: String) -> Element<'a, Msg> {
    container(
        row![ui::icon(glyph, 13.0), text(label).size(12).color(style::FG_MUTED)]
            .spacing(6)
            .align_y(Alignment::Center),
    )
    .padding([4, 10])
    .style(style::pill)
    .into()
}

/// Processor, memory and graphics side by side.
fn hardware(i: &Info) -> Element<'_, Msg> {
    let used = i.mem_total_kib.saturating_sub(i.mem_avail_kib);
    let memory_share = if i.mem_total_kib == 0 {
        0.0
    } else {
        used as f32 / i.mem_total_kib as f32
    };
    let tiles = [
        tile(
            ico::CPU,
            "Processor",
            i.cpu.clone(),
            format!("{} threads", i.threads),
            None,
        ),
        tile(
            ico::MEMORY_STICK,
            "Memory",
            gib(i.mem_total_kib),
            format!("{} in use", gib(used)),
            Some(memory_share),
        ),
        tile(ico::MONITOR, "Graphics", i.gpus.join("\n"), String::new(), None),
    ];
    Row::with_children(tiles).spacing(10).height(TILE).into()
}

fn tile<'a>(glyph: ui::Icon, label: &'a str, value: String, detail: String, share: Option<f32>) -> Element<'a, Msg> {
    let mut col = column![
        row![
            ui::icon(glyph, 16.0),
            text(label.to_uppercase())
                .font(style::FONT_BOLD)
                .size(10)
                .color(style::MUTED_DEEP)
        ]
        .spacing(8)
        .align_y(Alignment::Center),
        text(value).size(14).color(style::FG),
    ]
    .spacing(8);
    if let Some(s) = share {
        col = col.push(meter(s));
    }
    if !detail.is_empty() {
        col = col.push(text(detail).size(12).color(style::MUTED_DEEP));
    }
    container(col)
        .padding([14, 16])
        .width(Length::Fill)
        .height(Length::Fill)
        .style(style::card)
        .into()
}

fn meter<'a>(share: f32) -> Element<'a, Msg> {
    progress_bar(0.0..=1.0, share)
        .girth(6)
        .style(style::meter(share))
        .into()
}

fn disk(d: &Disk) -> Element<'_, Msg> {
    let line = row![
        container(ui::icon(ico::HARD_DRIVE, 18.0)).width(26).center_x(26),
        column![
            row![
                text(d.mount.clone()).size(14).color(style::FG).width(Length::Fill),
                text(format!("{} free of {}", d.avail, d.size))
                    .size(12)
                    .color(style::MUTED_DEEP),
            ],
            meter(d.used),
        ]
        .spacing(8),
    ]
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}

fn fact<'a>(glyph: ui::Icon, label: &'a str, value: &'a str) -> Element<'a, Msg> {
    let line = row![
        container(ui::icon(glyph, 18.0)).width(26).center_x(26),
        text(label).size(14).color(style::FG).width(130),
        text(value).size(14).color(style::FG_MUTED).width(Length::Fill),
    ]
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
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
        let info = "processor\t: 0\nmodel name\t: Intel i5\nprocessor\t: 1\nmodel name\t: Intel i5\n";
        assert_eq!(cpu(info), ("Intel i5".to_string(), 2));
        assert_eq!(meminfo_kib("MemTotal:       15686628 kB\n", "MemTotal"), 15686628);
        assert_eq!(gib(15686628), "15.0 GiB");
        assert_eq!(meminfo_kib("nothing", "MemTotal"), 0);
        assert_eq!(
            gpu_name("Intel Raptor Lake-P [Iris Xe Graphics] (rev 04)"),
            "Intel Raptor Lake-P [Iris Xe Graphics]"
        );
        assert_eq!(gpu_name("Intel Corporation Arc"), "Intel Arc");
        assert_eq!(
            cpu_name("13th Gen Intel(R) Core(TM) i5-1345U"),
            "13th Gen Intel Core i5-1345U"
        );
        assert_eq!(gpu_name("NVIDIA AD107M"), "NVIDIA AD107M");
    }

    #[test]
    fn formats_uptime() {
        assert_eq!(duration(720), "12 min");
        assert_eq!(duration(7500), "2 h 5 min");
        assert_eq!(duration(86400 + 3 * 3600), "1 day 3 h");
        assert_eq!(duration(3 * 86400), "3 days 0 h");
    }

    #[test]
    fn lists_each_disk_once() {
        let df = "Filesystem Mounted Size Avail Use%\n/dev/nvme0n1p3 / 460G 145G 68%\n/dev/nvme0n1p3 /home 460G 145G 68%\n/dev/sda1 /mnt/DATA 1.4T 393G 70%\n/dev/nvme0n1p1 /boot 1G 500M 50%\n";
        let list = disks(df);
        assert_eq!(list.len(), 2);
        assert_eq!(list[1].mount, "/mnt/DATA");
        assert!((list[0].used - 0.68).abs() < 1e-6);
    }

    #[test]
    fn copies_known_facts_only() {
        let info = Info {
            kernel: "6.1".into(),
            ..Info::default()
        };
        assert_eq!(as_text(&info), "Kernel: 6.1\n");
    }
}
