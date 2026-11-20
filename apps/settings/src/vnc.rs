//! Remote access (WayVNC) details under its row on the Sharing panel: where
//! clients connect, the login (shown on request, copied, replaced), and how
//! the server runs. The settings are store files read by
//! scripts/wayvnc-toggle.sh when it starts the server.

use iced::widget::text_input;
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::store::{Kind, Store, Value};
use crate::style::{self, Action};
use crate::system;
use crate::ui;

const LISTEN: &[(&str, &str)] = &[
    ("tailscale", "Tailnet only"),
    ("local", "This computer only"),
    ("lan", "Local network too"),
];
const FPS: &[(i64, &str)] = &[(15, "15 fps"), (30, "30 fps"), (60, "60 fps")];

/// The settings, as stored (defaults when unset).
#[derive(Debug, Clone, PartialEq)]
pub struct Config {
    pub listen: String,
    pub port: i64,
    pub view_only: bool,
    pub max_fps: i64,
    pub cursor: bool,
}

fn store() -> Store {
    Store::new(Store::default_dir())
}

fn read_config() -> Config {
    let s = store();
    let text = |f: &str, d: &str| match s.read(f, Kind::Text) {
        Some(Value::Text(t)) if !t.is_empty() => t,
        _ => d.to_string(),
    };
    let int = |f: &str, d: i64| match s.read(f, Kind::Int) {
        Some(Value::Int(n)) => n,
        _ => d,
    };
    let flag = |f: &str| matches!(s.read(f, Kind::Bool), Some(Value::Bool(true)));
    Config {
        listen: text("vnc-listen", "tailscale"),
        port: int("vnc-port", 5900),
        view_only: flag("vnc-view-only"),
        max_fps: int("vnc-max-fps", 30),
        cursor: flag("vnc-cursor"),
    }
}

/// `wayvnc-toggle.sh password`: "user:     name" and "password: secret".
pub fn parse_login(out: &str) -> Option<(String, String)> {
    let field = |key: &str| {
        out.lines()
            .find_map(|l| l.strip_prefix(key))
            .map(|v| v.trim().to_string())
    };
    Some((field("user:")?, field("password:")?))
}

/// A port a server can listen on.
pub fn valid_port(text: &str) -> Option<i64> {
    text.trim().parse::<i64>().ok().filter(|p| (1024..=65535).contains(p))
}

fn script() -> String {
    crate::store::home()
        .join(".config/scripts/wayvnc-toggle.sh")
        .to_string_lossy()
        .into_owned()
}

fn run(arg: &str) -> Result<String, String> {
    system::run_blocking("bash", &[script(), arg.to_string()], None)
}

/// What the details show, read off the UI thread.
#[derive(Debug, Clone, Default)]
pub struct Info {
    pub address: String,
    pub login: Option<(String, String)>,
}

fn load() -> Info {
    Info {
        address: run("address").map(|a| a.trim().to_string()).unwrap_or_default(),
        login: run("password").ok().and_then(|o| parse_login(&o)),
    }
}

pub struct State {
    config: Config,
    info: Option<Info>,
    show_password: bool,
    port_draft: String,
    note: Option<String>,
    error: Option<String>,
}

impl Default for State {
    fn default() -> Self {
        State {
            config: read_config(),
            info: None,
            show_password: false,
            port_draft: String::new(),
            note: None,
            error: None,
        }
    }
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Info),
    ShowPassword,
    Copy(String),
    NewPassword,
    Listen(&'static str),
    PortText(String),
    SavePort,
    ViewOnly(bool),
    Fps(i64),
    Cursor(bool),
    Done(Result<(), String>),
}

impl State {
    /// The port remote access listens on.
    pub fn port(&self) -> i64 {
        self.config.port
    }

    fn save(&mut self, file: &str, value: Value) {
        match store().write(file, &value) {
            Ok(()) => {
                self.config = read_config();
                self.note = Some("Takes effect the next time remote access starts".into());
                self.error = None;
            }
            Err(e) => self.error = Some(format!("Could not save: {e}")),
        }
    }

    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                self.config = read_config();
                return Task::perform(system::spawn(load), |i| Msg::Loaded(i.unwrap_or_default()));
            }
            Msg::Loaded(i) => self.info = Some(i),
            Msg::ShowPassword => self.show_password = !self.show_password,
            Msg::Copy(text) => {
                self.note = Some("Copied".into());
                return Task::perform(system::run("wl-copy", vec![text], None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::NewPassword => {
                self.note = Some("New password made; it is used from the next start".into());
                return Task::perform(system::spawn(|| run("rotate").map(|_| ())), |r| {
                    Msg::Done(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
                });
            }
            Msg::Listen(l) => self.save("vnc-listen", Value::Text(l.into())),
            Msg::PortText(t) => self.port_draft = t,
            Msg::SavePort => match valid_port(&self.port_draft) {
                Some(p) => {
                    self.port_draft.clear();
                    self.save("vnc-port", Value::Int(p));
                }
                None => self.error = Some("A port is a number from 1024 to 65535".into()),
            },
            Msg::ViewOnly(on) => self.save("vnc-view-only", Value::Bool(on)),
            Msg::Fps(n) => self.save("vnc-max-fps", Value::Int(n)),
            Msg::Cursor(on) => self.save("vnc-cursor", Value::Bool(on)),
            Msg::Done(r) => {
                self.error = r.err();
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    /// The rows under Remote access.
    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if let Some(n) = &self.note {
            rows.push(ui::note(n.clone()));
        }
        let info = self.info.clone().unwrap_or_default();
        let (address, copy_address) = if info.address.is_empty() {
            ("Not running".to_string(), None)
        } else {
            (info.address.clone(), Some(Msg::Copy(info.address.clone())))
        };
        rows.push(ui::item(
            ico::PLUG,
            "Connect to".into(),
            address,
            vec![ui::icon_action(ico::COPY, "Copy", copy_address, Action::Normal)],
        ));
        if let Some((user, password)) = &info.login {
            let shown = if self.show_password {
                password.clone()
            } else {
                "•".repeat(password.len().min(12))
            };
            let toggle = if self.show_password { "Hide" } else { "Show" };
            rows.push(ui::item(
                ico::KEY_ROUND,
                "Login".into(),
                format!("{user} · {shown}"),
                vec![ui::more_actions(
                    ("Copy password", Some(Msg::Copy(password.clone())), Action::Normal),
                    vec![
                        (toggle, Some(Msg::ShowPassword)),
                        ("New password", Some(Msg::NewPassword)),
                    ],
                )],
            ));
        }
        let c = &self.config;
        let listen = LISTEN
            .iter()
            .map(|(v, l)| (*l, c.listen == *v, Some(Msg::Listen(v))))
            .collect();
        rows.push(ui::item(
            ico::GLOBE,
            "Listen on".into(),
            "Tailnet only keeps it off the local network".into(),
            vec![ui::select(listen, Length::Fixed(220.0))],
        ));
        let port = text_input(&c.port.to_string(), &self.port_draft)
            .on_input(Msg::PortText)
            .on_submit(Msg::SavePort)
            .padding([6, 10])
            .width(100)
            .style(style::field);
        rows.push(ui::item(
            ico::HASH,
            "Port".into(),
            "Enter to save".into(),
            vec![port.into()],
        ));
        let fps = FPS
            .iter()
            .map(|(v, l)| (*l, c.max_fps == *v, Some(Msg::Fps(*v))))
            .collect();
        rows.push(ui::item(
            ico::GAUGE,
            "Frame rate".into(),
            "Most pictures a second sent".into(),
            vec![ui::select(fps, Length::Fixed(220.0))],
        ));
        rows.push(ui::item(
            ico::EYE,
            "View only".into(),
            "Remote keyboard and mouse do nothing".into(),
            vec![ui::switch(c.view_only, Some(Msg::ViewOnly))],
        ));
        rows.push(ui::item(
            ico::MOUSE_POINTER_2,
            "Draw the cursor".into(),
            "Into the picture, for clients that do not draw their own".into(),
            vec![ui::switch(c.cursor, Some(Msg::Cursor))],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_login() {
        assert_eq!(
            parse_login("user:     ghost\npassword: abc123\n"),
            Some(("ghost".to_string(), "abc123".to_string()))
        );
        assert_eq!(parse_login("nothing"), None);
    }

    #[test]
    fn checks_ports() {
        assert_eq!(valid_port("5900"), Some(5900));
        assert_eq!(valid_port("80"), None);
        assert_eq!(valid_port("x"), None);
    }
}
