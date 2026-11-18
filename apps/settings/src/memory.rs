//! Memory for the About panel: the installed modules (type, speed, size,
//! from the firmware tables systemd's udev exposes without root), what is in
//! use (/proc/meminfo) and swap (/proc/swaps).

use serde_json::{Value as Json, json};

/// How the memory sits on the board.
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum Mounting {
    /// Chips soldered to the board: it cannot be upgraded.
    Soldered,
    /// Modules in sockets (DIMM, SODIMM): they can be swapped or added.
    Socketed,
    #[default]
    Unknown,
}

impl Mounting {
    /// From a firmware form factor ("Row Of Chips", "SODIMM", "DIMM").
    pub fn from_form_factor(form: &str) -> Mounting {
        if form == "Row Of Chips" {
            Mounting::Soldered
        } else if form.contains("DIMM") {
            Mounting::Socketed
        } else {
            Mounting::Unknown
        }
    }

    fn id(self) -> &'static str {
        match self {
            Mounting::Soldered => "soldered",
            Mounting::Socketed => "socketed",
            Mounting::Unknown => "unknown",
        }
    }

    fn from_id(id: &str) -> Option<Mounting> {
        [Mounting::Soldered, Mounting::Socketed, Mounting::Unknown]
            .into_iter()
            .find(|m| m.id() == id)
    }
}

/// The installed memory, as the firmware describes it.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Modules {
    /// "LPDDR5".
    pub kind: String,
    /// Rated speed in MT/s.
    pub speed: Option<u32>,
    /// Speed it runs at, when lower than rated.
    pub configured: Option<u32>,
    pub count: usize,
    /// Bytes installed, all modules together.
    pub installed: u64,
    pub mounting: Mounting,
    /// Memory slots or chip positions the board has.
    pub slots: Option<usize>,
    /// Most the board takes, in bytes.
    pub max: Option<u64>,
}

/// What /proc/meminfo says, in KiB.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Usage {
    pub total: u64,
    pub available: u64,
    /// Page cache and reclaimable kernel memory: in use, but given back on
    /// demand.
    pub cache: u64,
    /// Zswap: what was swapped out, and what it takes compressed.
    pub zswapped: u64,
    pub zswap: u64,
}

impl Usage {
    pub fn used(&self) -> u64 {
        self.total.saturating_sub(self.available)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Swap {
    /// "zram0", "nvme0n1p3", "swapfile".
    pub name: String,
    /// Compressed RAM (zram) rather than disk.
    pub zram: bool,
    /// KiB.
    pub size: u64,
    pub used: u64,
}

/// The MEMORY_DEVICE_* properties of `udevadm info --query=property
/// --path=/sys/devices/virtual/dmi/id`. None when there are none (no
/// firmware tables, or udev without the memory rules).
pub fn parse_modules(props: &str) -> Option<Modules> {
    let get = |key: &str| {
        props
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{key}=")))
            .map(str::trim)
    };
    let mut m = Modules {
        slots: get("MEMORY_ARRAY_NUM_DEVICES").and_then(|s| s.parse().ok()),
        ..Modules::default()
    };
    // Empty slots are listed too, without a size; stop after the last device.
    let listed = |i: usize| props.lines().any(|l| l.starts_with(&format!("MEMORY_DEVICE_{i}_")));
    for i in (0..).take_while(|i| listed(*i)) {
        let field = |name: &str| get(&format!("MEMORY_DEVICE_{i}_{name}"));
        let Some(size) = field("SIZE").and_then(|s| s.parse::<u64>().ok()) else {
            continue;
        };
        m.count += 1;
        m.installed += size;
        if m.kind.is_empty() {
            m.kind = field("TYPE").unwrap_or_default().to_string();
            m.speed = field("SPEED_MTS").and_then(|s| s.parse().ok());
            m.configured = field("CONFIGURED_SPEED_MTS").and_then(|s| s.parse().ok());
            m.mounting = Mounting::from_form_factor(field("FORM_FACTOR").unwrap_or_default());
        }
    }
    m.max = get("MEMORY_ARRAY_MAX_CAPACITY").and_then(|s| s.parse().ok());
    (m.count > 0).then_some(m)
}

pub fn parse_usage(meminfo: &str) -> Usage {
    let kib = |key: &str| {
        meminfo
            .lines()
            .find_map(|l| l.strip_prefix(&format!("{key}:")))
            .and_then(|v| v.split_whitespace().next()?.parse().ok())
            .unwrap_or(0)
    };
    Usage {
        total: kib("MemTotal"),
        available: kib("MemAvailable"),
        cache: kib("Cached") + kib("Buffers") + kib("SReclaimable"),
        zswapped: kib("Zswapped"),
        zswap: kib("Zswap"),
    }
}

/// /proc/swaps: one line per swap area after the header.
pub fn parse_swaps(swaps: &str) -> Vec<Swap> {
    swaps
        .lines()
        .skip(1)
        .filter_map(|l| {
            let f: Vec<&str> = l.split_whitespace().collect();
            let name = f.first()?.rsplit('/').next()?.to_string();
            Some(Swap {
                zram: name.starts_with("zram"),
                size: f.get(2)?.parse().ok()?,
                used: f.get(3)?.parse().ok()?,
                name,
            })
        })
        .collect()
}

/// KiB as "332 MiB" or "15.0 GiB".
pub fn kib(n: u64) -> String {
    let mib = n as f64 / 1024.0;
    if mib < 1024.0 {
        format!("{mib:.0} MiB")
    } else {
        format!("{:.1} GiB", mib / 1024.0)
    }
}

/// Bytes as whole GiB when they are whole, else like `kib`.
pub fn bytes(n: u64) -> String {
    let gib = n as f64 / 1024.0 / 1024.0 / 1024.0;
    if gib >= 1.0 && gib.fract() == 0.0 {
        format!("{gib:.0} GiB")
    } else {
        kib(n / 1024)
    }
}

/// "LPDDR5 · 6400 MT/s, running at 4800 MT/s".
pub fn modules_kind(m: &Modules) -> String {
    let mut s = m.kind.clone();
    if let Some(speed) = m.speed {
        s = format!("{s} · {speed} MT/s");
        if let Some(c) = m.configured.filter(|c| *c < speed) {
            s = format!("{s}, running at {c} MT/s");
        }
    }
    s
}

/// "soldered, 8 chips", "socketed, 2 of 4 slots used" or "2 modules".
pub fn mounting_text(m: &Modules) -> String {
    let plural = |n: usize, word: &str| format!("{n} {word}{}", if n == 1 { "" } else { "s" });
    match (m.mounting, m.slots) {
        (Mounting::Soldered, _) => format!("soldered, {}", plural(m.count, "chip")),
        (Mounting::Socketed, Some(slots)) if slots >= m.count => {
            format!("socketed, {} of {} used", m.count, plural(slots, "slot"))
        }
        (Mounting::Socketed, _) => format!("socketed, {}", plural(m.count, "module")),
        (Mounting::Unknown, _) => plural(m.count, "module"),
    }
}

/// "16 GiB, soldered, 8 chips · board takes up to 16 GiB".
pub fn modules_layout(m: &Modules) -> String {
    let mut s = format!("{}, {}", bytes(m.installed), mounting_text(m));
    if let Some(max) = m.max.filter(|max| *max > 0) {
        s = format!("{s} · board takes up to {}", bytes(max));
    }
    s
}

pub fn modules_to_json(m: &Modules) -> Json {
    json!({"kind": m.kind, "speed": m.speed, "configured": m.configured, "count": m.count,
           "installed": m.installed, "mounting": m.mounting.id(), "slots": m.slots, "max": m.max})
}

pub fn modules_from_json(v: &Json) -> Option<Modules> {
    Some(Modules {
        kind: v["kind"].as_str()?.to_string(),
        speed: v["speed"].as_u64().map(|n| n as u32),
        configured: v["configured"].as_u64().map(|n| n as u32),
        count: v["count"].as_u64()? as usize,
        installed: v["installed"].as_u64()?,
        mounting: Mounting::from_id(v["mounting"].as_str()?)?,
        slots: v["slots"].as_u64().map(|n| n as usize),
        max: v["max"].as_u64(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const UDEV: &str = "MEMORY_ARRAY_MAX_CAPACITY=17179869184\nMEMORY_DEVICE_0_SIZE=2147483648\nMEMORY_DEVICE_0_FORM_FACTOR=Row Of Chips\nMEMORY_DEVICE_0_TYPE=LPDDR5\nMEMORY_DEVICE_0_SPEED_MTS=6400\nMEMORY_DEVICE_0_CONFIGURED_SPEED_MTS=4800\nMEMORY_DEVICE_1_SIZE=2147483648\nMEMORY_DEVICE_1_TYPE=LPDDR5\n";

    #[test]
    fn reads_modules_from_udev() {
        let m = parse_modules(UDEV).unwrap();
        assert_eq!((m.count, m.installed, m.mounting), (2, 4 << 30, Mounting::Soldered));
        assert_eq!(modules_kind(&m), "LPDDR5 · 6400 MT/s, running at 4800 MT/s");
        assert_eq!(
            modules_layout(&m),
            "4 GiB, soldered, 2 chips · board takes up to 16 GiB"
        );
        assert_eq!(modules_from_json(&modules_to_json(&m)), Some(m));
        assert_eq!(parse_modules("ID_FOO=1\n"), None);
    }

    #[test]
    fn tells_socketed_memory_and_free_slots() {
        let props = "MEMORY_ARRAY_NUM_DEVICES=4\nMEMORY_DEVICE_0_SIZE=8589934592\nMEMORY_DEVICE_0_FORM_FACTOR=SODIMM\nMEMORY_DEVICE_0_TYPE=DDR5\nMEMORY_DEVICE_1_PRESENT=0\nMEMORY_DEVICE_1_FORM_FACTOR=SODIMM\nMEMORY_DEVICE_2_SIZE=8589934592\nMEMORY_DEVICE_2_FORM_FACTOR=SODIMM\nMEMORY_DEVICE_3_PRESENT=0\n";
        let m = parse_modules(props).unwrap();
        assert_eq!((m.count, m.installed, m.mounting), (2, 16 << 30, Mounting::Socketed));
        assert_eq!(mounting_text(&m), "socketed, 2 of 4 slots used");
        assert_eq!(Mounting::from_form_factor("Other"), Mounting::Unknown);
    }

    #[test]
    fn reads_usage_and_swaps() {
        let u = parse_usage(
            "MemTotal: 16000 kB\nMemAvailable: 12000 kB\nBuffers: 100 kB\nCached: 900 kB\nSReclaimable: 50 kB\nZswap: 48 kB\nZswapped: 300 kB\n",
        );
        assert_eq!((u.used(), u.cache, u.zswap, u.zswapped), (4000, 1050, 48, 300));
        let swaps = parse_swaps(
            "Filename Type Size Used Priority\n/dev/zram0 partition 15685628 340708 100\n/dev/nvme0n1p3 partition 16383996 0 -1\n",
        );
        assert_eq!(swaps.len(), 2);
        assert!(swaps[0].zram && !swaps[1].zram);
        assert_eq!(swaps[1].name, "nvme0n1p3");
    }

    #[test]
    fn formats_sizes() {
        assert_eq!(kib(340708), "333 MiB");
        assert_eq!(kib(15685628), "15.0 GiB");
        assert_eq!(bytes(16 << 30), "16 GiB");
    }
}
