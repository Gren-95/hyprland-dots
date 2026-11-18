//! What the system is, for the About panel: read from /proc, /sys, os-release
//! and a few commands (lspci, df, ip, nmcli, git, rpm, flatpak). Parsing is
//! kept apart from reading so it can be tested.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use crate::system::{self, args};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Disk {
    pub mount: String,
    pub size: String,
    pub avail: String,
    /// Share in use, 0..1.
    pub used: f32,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Gpu {
    /// "Intel Iris Xe Graphics".
    pub name: String,
    /// The chip, "Raptor Lake-P".
    pub chip: String,
    /// Kernel driver in use, "i915".
    pub driver: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Battery {
    /// "Charging", "Discharging", "Not charging", "Full".
    pub status: String,
    pub percent: u32,
    pub full_wh: f64,
    pub design_wh: f64,
    pub cycles: Option<u32>,
    pub temp_c: Option<f64>,
    /// Power going in or out, in watts.
    pub power_w: Option<f64>,
    /// Charging starts below / stops at, in percent.
    pub limit: (Option<u32>, Option<u32>),
    pub model: String,
    pub technology: String,
    /// "2023-01".
    pub made: String,
}

impl Battery {
    /// Full capacity now against the design capacity, 0..1.
    pub fn health(&self) -> f32 {
        if self.design_wh > 0.0 {
            (self.full_wh / self.design_wh) as f32
        } else {
            0.0
        }
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Network {
    pub device: String,
    /// "Wi-Fi" or "Wired".
    pub kind: String,
    /// The NetworkManager connection, e.g. the Wi-Fi name.
    pub connection: String,
    pub addresses: Vec<String>,
    pub gateway: String,
    pub dns: Vec<String>,
    /// MAC address.
    pub hardware: String,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Repo {
    /// "Gren-95/hyprland-dots".
    pub slug: String,
    /// Web page of the repository, when it is on GitHub.
    pub url: Option<String>,
    pub branch: String,
    /// "50f457d Style: A richer About panel".
    pub commit: String,
    /// "2 hours ago".
    pub when: String,
    /// Commits on local branches that no remote has.
    pub unpushed: usize,
    pub changed: usize,
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
    pub gpus: Vec<Gpu>,
    pub mem_total_kib: u64,
    pub mem_avail_kib: u64,
    pub disks: Vec<Disk>,
    pub battery: Option<Battery>,
    pub network: Option<Network>,
    pub kernel: String,
    pub hyprland: String,
    pub quickshell: String,
    /// ("RPM", 3066), ("Flatpak", 10).
    pub packages: Vec<(&'static str, usize)>,
    pub repo: Option<Repo>,
    pub app: String,
}

fn read(path: impl AsRef<Path>) -> String {
    std::fs::read_to_string(path).unwrap_or_default().trim().to_string()
}

fn run(program: &str, list: &[&str]) -> String {
    system::run_blocking(program, &args(list), None)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

/// A value from `KEY=value` or `KEY="value"` lines (os-release).
pub fn os_release_value(text: &str, key: &str) -> String {
    text.lines()
        .find_map(|l| l.strip_prefix(&format!("{key}=")))
        .map(|v| v.trim_matches('"').to_string())
        .unwrap_or_default()
}

/// A CPU model without the (R) and (TM) marks.
pub fn cpu_name(model: &str) -> String {
    model.replace("(R)", "").replace("(TM)", "")
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

pub fn gib(kib: u64) -> String {
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

/// A vendor as people say it: "Intel", "NVIDIA", "AMD".
fn short_vendor(vendor: &str) -> String {
    if let Some((_, inner)) = vendor.split_once('[') {
        return inner
            .trim_end_matches(']')
            .split('/')
            .next()
            .unwrap_or_default()
            .to_string();
    }
    vendor
        .replace(" Corporation", "")
        .replace(", Inc.", "")
        .trim()
        .to_string()
}

/// A display controller line of `lspci -mm`:
/// `00:02.0 "VGA compatible controller" "Intel Corporation" "Raptor Lake-P [Iris Xe Graphics]" -r04 …`
/// as (slot, GPU without the driver).
pub fn parse_gpu(line: &str) -> Option<(String, Gpu)> {
    let slot = line.split_whitespace().next()?.to_string();
    let quoted: Vec<&str> = line.split('"').skip(1).step_by(2).collect();
    let (class, vendor, device) = (*quoted.first()?, *quoted.get(1)?, *quoted.get(2)?);
    if !(class.contains("VGA") || class.contains("3D") || class.contains("Display")) {
        return None;
    }
    let vendor = short_vendor(vendor);
    let (chip, model) = match device.split_once('[') {
        Some((chip, model)) => (chip.trim().to_string(), model.trim_end_matches(']').trim().to_string()),
        None => (String::new(), device.to_string()),
    };
    let name = if model.starts_with(&vendor) {
        model
    } else {
        format!("{vendor} {model}")
    };
    Some((
        slot,
        Gpu {
            name,
            chip,
            driver: String::new(),
        },
    ))
}

/// `df -h --output=source,target,size,avail,pcent`: the root and /home and
/// /mnt mounts, once per device.
pub fn disks(df: &str) -> Vec<Disk> {
    let mut seen = HashSet::new();
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

/// A battery from its power_supply attributes (`get("capacity")`). Sizes
/// come as energy (µWh) or as charge (µAh, turned into Wh with the design
/// voltage).
pub fn parse_battery(get: impl Fn(&str) -> Option<String>) -> Option<Battery> {
    let num = |k: &str| get(k).and_then(|v| v.trim().parse::<f64>().ok());
    let percent = num("capacity")? as u32;
    let volts = num("voltage_min_design").or_else(|| num("voltage_now")).unwrap_or(0.0) / 1e6;
    let wh = |energy: &str, charge: &str| {
        num(energy)
            .map(|e| e / 1e6)
            .or_else(|| num(charge).map(|c| c / 1e6 * volts))
    };
    let power = num("power_now").map(|p| p / 1e6).or_else(|| {
        let (amps, now_volts) = (num("current_now")? / 1e6, num("voltage_now")? / 1e6);
        Some(amps * now_volts)
    });
    let made = match (num("manufacture_year"), num("manufacture_month")) {
        (Some(y), Some(m)) => format!("{y:.0}-{m:02.0}"),
        (Some(y), None) => format!("{y:.0}"),
        _ => String::new(),
    };
    let model = [get("manufacturer"), get("model_name")]
        .into_iter()
        .flatten()
        .map(|s| s.trim().to_string())
        .collect::<Vec<_>>();
    Some(Battery {
        status: get("status").unwrap_or_default().trim().to_string(),
        percent,
        full_wh: wh("energy_full", "charge_full").unwrap_or(0.0),
        design_wh: wh("energy_full_design", "charge_full_design").unwrap_or(0.0),
        cycles: num("cycle_count").filter(|c| *c > 0.0).map(|c| c as u32),
        temp_c: num("temp").map(|t| t / 10.0),
        power_w: power.filter(|p| *p > 0.05),
        limit: (
            num("charge_control_start_threshold").map(|v| v as u32),
            num("charge_control_end_threshold").map(|v| v as u32),
        ),
        model: model.join(" "),
        technology: get("technology").unwrap_or_default().trim().to_string(),
        made,
    })
}

pub fn battery() -> Option<Battery> {
    let dir = std::fs::read_dir("/sys/class/power_supply")
        .ok()?
        .flatten()
        .map(|e| e.path())
        .find(|p| read(p.join("type")) == "Battery" && read(p.join("scope")) != "Device")?;
    parse_battery(|k| std::fs::read_to_string(dir.join(k)).ok())
}

/// A git remote as "owner/name" and, on GitHub, its web page.
pub fn parse_remote(url: &str) -> (String, Option<String>) {
    let url = url.trim().trim_end_matches(".git");
    let path = url
        .strip_prefix("git@github.com:")
        .or_else(|| url.strip_prefix("https://github.com/"))
        .or_else(|| url.strip_prefix("ssh://git@github.com/"));
    match path {
        Some(p) => (p.to_string(), Some(format!("https://github.com/{p}"))),
        None => (
            url.rsplit(['/', ':'])
                .take(2)
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect::<Vec<_>>()
                .join("/"),
            None,
        ),
    }
}

/// The dots repository: where ~/.config/hypr really lives, two levels up.
fn repo() -> Option<Repo> {
    let hypr = std::fs::canonicalize(crate::store::home().join(".config/hypr")).ok()?;
    let dir = hypr.parent()?.parent()?.to_string_lossy().into_owned();
    let git = |list: &[&str]| run("git", &[&["-C", dir.as_str()], list].concat());
    let (slug, url) = parse_remote(&git(&["remote", "get-url", "origin"]));
    Some(Repo {
        slug,
        url,
        branch: git(&["rev-parse", "--abbrev-ref", "HEAD"]),
        commit: git(&["log", "-1", "--format=%h %s"]),
        when: git(&["log", "-1", "--format=%cr"]),
        unpushed: git(&["rev-list", "--count", "--branches", "--not", "--remotes"])
            .parse()
            .unwrap_or(0),
        changed: git(&["status", "--porcelain"]).lines().count(),
    })
}

/// The interface the default route uses, with its addresses, gateway and DNS.
pub fn network() -> Option<Network> {
    let route: serde_json::Value = serde_json::from_str(&run("ip", &["-j", "route", "get", "1.1.1.1"])).ok()?;
    device_network(route[0]["dev"].as_str()?)
}

/// One network device: its connection, addresses, gateway, DNS and
/// hardware address.
pub fn device_network(device: &str) -> Option<Network> {
    let addrs: serde_json::Value = serde_json::from_str(&run("ip", &["-j", "addr", "show", "dev", device])).ok()?;
    let addresses = addrs[0]["addr_info"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|a| a["scope"] == "global")
        .filter_map(|a| Some(format!("{}/{}", a["local"].as_str()?, a["prefixlen"])))
        .collect();
    let show = run(
        "nmcli",
        &[
            "-t",
            "-f",
            "GENERAL.CONNECTION,GENERAL.HWADDR,IP4.GATEWAY,IP6.GATEWAY,IP4.DNS,IP6.DNS",
            "dev",
            "show",
            device,
        ],
    );
    let field = |prefix: &str| -> Vec<String> {
        show.lines()
            .filter_map(|l| l.split_once(':'))
            .filter(|(k, v)| k.starts_with(prefix) && !v.is_empty())
            .map(|(_, v)| v.replace("\\:", ":"))
            .collect()
    };
    let wireless = Path::new("/sys/class/net").join(device).join("wireless").exists();
    Some(Network {
        kind: if wireless { "Wi-Fi" } else { "Wired" }.into(),
        connection: field("GENERAL.CONNECTION").join(""),
        addresses,
        gateway: [field("IP4.GATEWAY"), field("IP6.GATEWAY")].concat().join("\n"),
        dns: [field("IP4.DNS"), field("IP6.DNS")].concat(),
        hardware: field("GENERAL.HWADDR").join(""),
        device: device.to_string(),
    })
}

fn packages() -> Vec<(&'static str, usize)> {
    let count = |program: &str, list: &[&str]| {
        system::run_blocking(program, &args(list), None)
            .ok()
            .map(|o| o.lines().filter(|l| !l.is_empty()).count())
    };
    [
        ("RPM", count("rpm", &["-qa"])),
        ("Flatpak", count("flatpak", &["list", "--app", "--columns=application"])),
    ]
    .into_iter()
    .filter_map(|(k, n)| n.filter(|n| *n > 0).map(|n| (k, n)))
    .collect()
}

fn gpus() -> Vec<Gpu> {
    run("lspci", &["-mm"])
        .lines()
        .filter_map(parse_gpu)
        .map(|(slot, mut gpu)| {
            gpu.driver = run("lspci", &["-k", "-s", &slot])
                .lines()
                .find_map(|l| {
                    l.trim()
                        .strip_prefix("Kernel driver in use:")
                        .map(|d| d.trim().to_string())
                })
                .unwrap_or_default();
            gpu
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

pub fn load() -> Info {
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
    let hyprland = serde_json::from_str::<serde_json::Value>(&run("hyprctl", &["version", "-j"]))
        .ok()
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
        gpus: gpus(),
        mem_total_kib: meminfo_kib(&meminfo, "MemTotal"),
        mem_avail_kib: meminfo_kib(&meminfo, "MemAvailable"),
        disks: disks(&df),
        battery: battery(),
        network: network(),
        kernel: run("uname", &["-r"]),
        hyprland,
        quickshell,
        packages: packages(),
        repo: repo(),
        app: env!("CARGO_PKG_VERSION").to_string(),
    }
}

/// "3066 RPM · 10 Flatpak".
pub fn packages_text(packages: &[(&str, usize)]) -> String {
    packages
        .iter()
        .map(|(k, n)| format!("{n} {k}"))
        .collect::<Vec<_>>()
        .join(" · ")
}

/// "Raptor Lake-P · i915".
pub fn gpu_detail(gpu: &Gpu) -> String {
    [gpu.chip.as_str(), gpu.driver.as_str()]
        .iter()
        .filter(|s| !s.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(" · ")
}

/// Everything as plain text, one fact per line, empty ones left out.
pub fn as_text(i: &Info) -> String {
    let mut facts: Vec<(&str, String)> = vec![
        ("Computer", i.computer.clone()),
        ("Name", i.host.clone()),
        ("System", i.system.clone()),
        ("Kernel", i.kernel.clone()),
        ("Hyprland", i.hyprland.clone()),
        ("Quickshell", i.quickshell.clone()),
        ("Packages", packages_text(&i.packages)),
        (
            "Processor",
            if i.cpu.is_empty() {
                String::new()
            } else {
                format!("{} ({} threads)", i.cpu, i.threads)
            },
        ),
        (
            "Graphics",
            i.gpus
                .iter()
                .map(|g| format!("{} ({})", g.name, gpu_detail(g)))
                .collect::<Vec<_>>()
                .join(", "),
        ),
        (
            "Memory",
            if i.mem_total_kib == 0 {
                String::new()
            } else {
                gib(i.mem_total_kib)
            },
        ),
        (
            "Disks",
            i.disks
                .iter()
                .map(|d| format!("{} {} ({} free)", d.mount, d.size, d.avail))
                .collect::<Vec<_>>()
                .join(", "),
        ),
    ];
    if let Some(b) = &i.battery {
        let cycles = b.cycles.map(|c| format!(", {c} cycles")).unwrap_or_default();
        facts.push((
            "Battery",
            format!(
                "{} % {}, health {:.0} % ({:.1} of {:.1} Wh{cycles})",
                b.percent,
                b.status,
                b.health() * 100.0,
                b.full_wh,
                b.design_wh
            ),
        ));
    }
    if let Some(n) = &i.network {
        facts.push(("Network", format!("{} {} {}", n.kind, n.device, n.addresses.join(" "))));
    }
    if let Some(r) = &i.repo {
        facts.push((
            "Dots",
            format!(
                "{} {} {}{}",
                r.slug,
                r.branch,
                r.commit,
                if r.changed > 0 { " (changed files)" } else { "" }
            ),
        ));
    }
    facts.push(("Settings app", i.app.clone()));
    facts
        .iter()
        .filter(|(_, v)| !v.trim().is_empty())
        .map(|(k, v)| format!("{k}: {v}\n"))
        .collect()
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
        let info =
            "processor\t: 0\nmodel name\t: Intel(R) Core(TM) i5\nprocessor\t: 1\nmodel name\t: Intel(R) Core(TM) i5\n";
        assert_eq!(cpu(info), ("Intel Core i5".to_string(), 2));
        assert_eq!(meminfo_kib("MemTotal:       15686628 kB\n", "MemTotal"), 15686628);
        assert_eq!(gib(15686628), "15.0 GiB");
    }

    #[test]
    fn formats_uptime() {
        assert_eq!(duration(720), "12 min");
        assert_eq!(duration(7500), "2 h 5 min");
        assert_eq!(duration(86400 + 3 * 3600), "1 day 3 h");
    }

    #[test]
    fn names_gpus_like_people_do() {
        let intel = r#"00:02.0 "VGA compatible controller" "Intel Corporation" "Raptor Lake-P [Iris Xe Graphics]" -r04 -p00 "Dell" "Device 0c0e""#;
        let (slot, gpu) = parse_gpu(intel).unwrap();
        assert_eq!(slot, "00:02.0");
        assert_eq!(gpu.name, "Intel Iris Xe Graphics");
        assert_eq!(gpu.chip, "Raptor Lake-P");
        let nvidia = r#"01:00.0 "3D controller" "NVIDIA Corporation" "AD107M [GeForce RTX 4060 Max-Q / Mobile]" -ra1"#;
        assert_eq!(
            parse_gpu(nvidia).unwrap().1.name,
            "NVIDIA GeForce RTX 4060 Max-Q / Mobile"
        );
        let amd = r#"03:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Navi 23 [Radeon RX 6600]""#;
        assert_eq!(parse_gpu(amd).unwrap().1.name, "AMD Radeon RX 6600");
        assert_eq!(
            parse_gpu(r#"00:14.0 "USB controller" "Intel Corporation" "xHCI""#),
            None
        );
        let gpu = Gpu {
            name: String::new(),
            chip: "Raptor Lake-P".into(),
            driver: "i915".into(),
        };
        assert_eq!(gpu_detail(&gpu), "Raptor Lake-P · i915");
    }

    #[test]
    fn lists_each_disk_once() {
        let df = "Filesystem Mounted Size Avail Use%\n/dev/a / 460G 145G 68%\n/dev/a /home 460G 145G 68%\n/dev/b /mnt/DATA 1.4T 393G 70%\n/dev/c /boot 1G 500M 50%\n";
        let list = disks(df);
        assert_eq!(list.len(), 2);
        assert!((list[0].used - 0.68).abs() < 1e-6);
    }

    #[test]
    fn reads_batteries_by_charge_or_energy() {
        let attrs = |pairs: &'static [(&'static str, &'static str)]| {
            move |k: &str| pairs.iter().find(|(a, _)| *a == k).map(|(_, v)| v.to_string())
        };
        let charge = parse_battery(attrs(&[
            ("capacity", "80"),
            ("status", "Not charging"),
            ("charge_full", "3323000"),
            ("charge_full_design", "5000000"),
            ("voltage_min_design", "11400000"),
            ("voltage_now", "11867000"),
            ("current_now", "1000"),
            ("cycle_count", "373"),
            ("temp", "276"),
            ("charge_control_start_threshold", "75"),
            ("charge_control_end_threshold", "80"),
            ("manufacturer", "BYD"),
            ("model_name", "DELL 0HYH831"),
            ("manufacture_year", "2023"),
            ("manufacture_month", "1"),
        ]))
        .unwrap();
        assert!((charge.design_wh - 57.0).abs() < 0.01);
        assert!((charge.health() - 0.6646).abs() < 0.001);
        assert_eq!(charge.power_w, None);
        assert_eq!(charge.temp_c, Some(27.6));
        assert_eq!(charge.limit, (Some(75), Some(80)));
        assert_eq!(charge.model, "BYD DELL 0HYH831");
        assert_eq!(charge.made, "2023-01");
        let energy = parse_battery(attrs(&[
            ("capacity", "50"),
            ("energy_full", "40000000"),
            ("energy_full_design", "50000000"),
            ("power_now", "8500000"),
        ]))
        .unwrap();
        assert!((energy.health() - 0.8).abs() < 1e-6);
        assert_eq!(energy.power_w, Some(8.5));
        assert_eq!(energy.cycles, None);
        assert!(parse_battery(attrs(&[])).is_none());
    }

    #[test]
    fn reads_github_remotes() {
        let page = Some("https://github.com/Gren-95/hyprland-dots".to_string());
        assert_eq!(
            parse_remote("https://github.com/Gren-95/hyprland-dots.git"),
            ("Gren-95/hyprland-dots".into(), page.clone())
        );
        assert_eq!(
            parse_remote("git@github.com:Gren-95/hyprland-dots.git"),
            ("Gren-95/hyprland-dots".into(), page)
        );
        assert_eq!(parse_remote("https://gitlab.com/a/b.git"), ("a/b".into(), None));
    }

    #[test]
    fn counts_packages() {
        assert_eq!(
            packages_text(&[("RPM", 3066), ("Flatpak", 10)]),
            "3066 RPM · 10 Flatpak"
        );
    }
}
