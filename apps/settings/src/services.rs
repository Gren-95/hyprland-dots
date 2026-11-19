//! Services panel: what runs in the background, from one probe
//! (scripts/services-status.sh, shared with the bar's Services flyout).
//! Dotwatch shows whether it runs and can be started or restarted (the
//! systemd user units are units.rs, the autostart apps startup.rs);
//! the scheduled syncs and the on-demand services have a switch, through
//! the same toggle scripts the flyout uses.

use iced::{Element, Task};
use lucide_iced::bytes as ico;

use crate::style::Action;
use crate::system;
use crate::ui;

struct Daemon {
    key: &'static str,
    label: &'static str,
    detail: &'static str,
    /// The script that starts it, run detached (it outlives this app).
    script: &'static str,
}

/// Started at login by restart.sh rather than as a systemd unit (those are
/// in units.rs).
const DAEMONS: &[Daemon] = &[Daemon {
    key: "dotwatch",
    label: "Dotwatch",
    detail: "Reloads dotfiles when they are edited",
    script: "dotwatch.sh",
}];

/// A service with an on/off switch: (key, label, detail, toggle script and
/// its arguments).
struct Switchable {
    key: &'static str,
    label: &'static str,
    detail: &'static str,
    toggle: &'static [&'static str],
}

const SCHEDULED: &[Switchable] = &[
    Switchable {
        key: "immich",
        label: "Immich sync",
        detail: "Photos, every hour",
        toggle: &["sync-toggle.sh", "toggle", "immich"],
    },
    Switchable {
        key: "jellyfin",
        label: "Jellyfin sync",
        detail: "Music, every day",
        toggle: &["sync-toggle.sh", "toggle", "jellyfin"],
    },
];

const ON_DEMAND: &[Switchable] = &[
    Switchable {
        key: "wayvnc",
        label: "Remote access",
        detail: "VNC",
        toggle: &["wayvnc-toggle.sh"],
    },
    Switchable {
        key: "winvm",
        label: "Windows VM",
        detail: "The WinApps container",
        toggle: &["winvm-toggle.sh", "toggle"],
    },
    Switchable {
        key: "games-browser",
        label: "Games browser",
        detail: "Web page of the games library on port 8080",
        toggle: &["games-browser-toggle.sh", "toggle"],
    },
];

const GAMES_BROWSER_URL: &str = "http://127.0.0.1:8080/";

/// `services-status.sh`: "key=value " pairs on one line.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Status {
    pairs: Vec<(String, String)>,
    /// When the Jellyfin timer fires next, as "Thu 03:00" (filled in by the
    /// probe, not while drawing).
    pub jellyfin_next: String,
}

impl Status {
    pub fn parse(line: &str) -> Status {
        let pairs = line
            .split_whitespace()
            .filter_map(|p| p.split_once('='))
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        Status {
            pairs,
            jellyfin_next: String::new(),
        }
    }

    fn get(&self, key: &str) -> Option<&str> {
        self.pairs.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }

    pub fn up(&self, key: &str) -> bool {
        self.get(key) == Some("1")
    }

    /// When the Jellyfin timer fires next, as Unix time.
    pub fn jellyfin_next(&self) -> Option<u64> {
        self.get("jfnext").and_then(|v| v.parse().ok()).filter(|t| *t > 0)
    }
}

fn script(name: &str) -> String {
    crate::store::home()
        .join(".config/scripts")
        .join(name)
        .to_string_lossy()
        .into_owned()
}

fn probe() -> Status {
    let mut st =
        Status::parse(&system::run_blocking("bash", &[script("services-status.sh")], None).unwrap_or_default());
    if let Some(next) = st.jellyfin_next() {
        st.jellyfin_next = next_run(next);
    }
    st
}

fn start(name: &'static str) -> Result<(), String> {
    std::process::Command::new("setsid")
        .args(["-f", "bash", &script(name)])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map_err(|e| e.to_string())
        .and_then(|s| s.success().then_some(()).ok_or_else(|| format!("{name} did not start")))
}

#[derive(Default)]
pub struct State {
    status: Option<Status>,
    /// Remote access Details: open, and what they hold (vnc.rs).
    vnc_open: bool,
    vnc: crate::vnc::State,
    /// The service being switched, until the next probe shows it.
    busy: Option<&'static str>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Refreshed(Status),
    Start(usize),
    Toggle(&'static str),
    OpenGamesBrowser,
    ToggleVnc,
    Vnc(crate::vnc::Msg),
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Refresh => return Task::perform(system::spawn(probe), |s| Msg::Refreshed(s.unwrap_or_default())),
            Msg::Refreshed(s) => {
                self.status = Some(s);
                self.busy = None;
            }
            Msg::Start(i) => {
                let daemon = &DAEMONS[i];
                self.busy = Some(daemon.key);
                let name = daemon.script;
                return Task::perform(system::spawn(move || start(name)), |r| {
                    Msg::Done(r.unwrap_or_else(|| Err("starting stopped unexpectedly".into())))
                });
            }
            Msg::Toggle(key) => {
                let Some(s) = SCHEDULED.iter().chain(ON_DEMAND).find(|s| s.key == key) else {
                    return Task::none();
                };
                self.busy = Some(key);
                let mut list = vec![script(s.toggle[0])];
                list.extend(s.toggle[1..].iter().map(|a| a.to_string()));
                return Task::perform(system::run("bash", list, None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::ToggleVnc => {
                self.vnc_open = !self.vnc_open;
                if self.vnc_open {
                    return self.vnc.update(crate::vnc::Msg::Load).map(Msg::Vnc);
                }
            }
            Msg::Vnc(m) => return self.vnc.update(m).map(Msg::Vnc),
            Msg::OpenGamesBrowser => {
                return Task::perform(system::run("xdg-open", vec![GAMES_BROWSER_URL.into()], None), |r| {
                    Msg::Done(r.map(|_| ()))
                });
            }
            Msg::Done(r) => {
                self.error = r.err();
                // Remote access may have started or stopped: its address too.
                let vnc = if self.vnc_open {
                    self.vnc.update(crate::vnc::Msg::Load).map(Msg::Vnc)
                } else {
                    Task::none()
                };
                return Task::batch([self.update(Msg::Refresh), vnc]);
            }
        }
        Task::none()
    }

    pub fn daemon_rows(&self) -> Vec<Element<'_, Msg>> {
        let Some(st) = &self.status else {
            return vec![ui::note("Looking…")];
        };
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        for (i, d) in DAEMONS.iter().enumerate() {
            let up = st.up(d.key);
            let busy = self.busy == Some(d.key);
            let detail = if busy {
                "Starting…".to_string()
            } else if up {
                format!("Running · {}", d.detail)
            } else {
                format!("Stopped · {}", d.detail)
            };
            let label = if up { "Restart" } else { "Start" };
            let kind = if up { Action::Normal } else { Action::Primary };
            rows.push(ui::item(
                if up { ico::CIRCLE_CHECK } else { ico::CIRCLE_X },
                d.label.into(),
                detail,
                vec![ui::action(label, (!busy).then_some(Msg::Start(i)), kind)],
            ));
        }
        rows
    }

    fn switch_rows(&self, list: &'static [Switchable]) -> Vec<Element<'_, Msg>> {
        let Some(st) = &self.status else {
            return vec![ui::note("Looking…")];
        };
        let mut rows = Vec::new();
        for s in list {
            let on = st.up(s.key);
            let busy = self.busy == Some(s.key);
            let mut detail = s.detail.to_string();
            if s.key == "wayvnc" {
                detail = format!("VNC on port {}", self.vnc.port());
            }
            if s.key == "jellyfin" && on && !st.jellyfin_next.is_empty() {
                detail = format!("{detail} · next {}", st.jellyfin_next);
            }
            if busy {
                detail = "Switching…".into();
            }
            let key = s.key;
            let mut controls = Vec::new();
            if key == "games-browser" && on {
                controls.push(ui::action("Open", Some(Msg::OpenGamesBrowser), Action::Normal));
            }
            // Remote access has its address, login and options behind Details.
            if key == "wayvnc" {
                controls.push(ui::disclosure(self.vnc_open, Msg::ToggleVnc));
            }
            controls.push(ui::switch(on, (!busy).then_some(move |_| Msg::Toggle(key))));
            rows.push(ui::item(service_glyph(key), s.label.into(), detail, controls));
            if key == "wayvnc" && self.vnc_open {
                let details: Vec<Element<'_, Msg>> = self.vnc.rows().into_iter().map(|r| r.map(Msg::Vnc)).collect();
                let count = details.len();
                rows.extend(
                    details
                        .into_iter()
                        .enumerate()
                        .map(|(i, d)| ui::branch(d, i + 1 == count)),
                );
            }
        }
        rows
    }

    pub fn scheduled_rows(&self) -> Vec<Element<'_, Msg>> {
        self.switch_rows(SCHEDULED)
    }

    pub fn on_demand_rows(&self) -> Vec<Element<'_, Msg>> {
        self.switch_rows(ON_DEMAND)
    }
}

fn service_glyph(key: &str) -> ui::Icon {
    match key {
        "immich" => ico::IMAGES,
        "jellyfin" => ico::AUDIO_LINES,
        "wayvnc" => ico::MONITOR_UP,
        "winvm" => ico::APP_WINDOW,
        _ => ico::GAMEPAD_2,
    }
}

/// A Unix time as "Thu 03:00" in local time.
fn next_run(secs: u64) -> String {
    system::run_blocking("date", &system::args(&["-d", &format!("@{secs}"), "+%a %H:%M"]), None)
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_probe() {
        let st =
            Status::parse("battery-notify=1 power-auto=0 dotwatch=1 wayvnc=0 immich=1 jellyfin=1 jfnext=1795200000\n");
        assert!(st.up("battery-notify") && !st.up("power-auto") && st.up("immich"));
        assert!(!st.up("missing"));
        assert_eq!(st.jellyfin_next(), Some(1_795_200_000));
        assert_eq!(Status::parse("jfnext=0").jellyfin_next(), None);
    }
}
