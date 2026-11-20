//! Users panel: the picture and full name of the user, through
//! AccountsService over D-Bus (busctl). A user may change their own without
//! a password. A new picture is copied by AccountsService to
//! /var/lib/AccountsService/icons/<user>, which the lock screen shows
//! (~/.config/hypr/avatar.png points there); "Make initials picture" runs
//! scripts/generate-avatar.sh.

use iced::widget::{container, image, text_input};
use iced::{Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::store::home;
use crate::style::{self, Action};
use crate::system::{self, args};
use crate::ui;

const ACCOUNTS: &str = "org.freedesktop.Accounts";
const USER_IFACE: &str = "org.freedesktop.Accounts.User";

/// busctl prints a string as `s "text"` and an object path as `o "/path"`,
/// with C escapes such as \303\274 for non-ASCII bytes.
pub fn parse_busctl_string(out: &str) -> Option<String> {
    let quoted = out.trim().split_once(' ')?.1.trim();
    let inner = quoted.strip_prefix('"')?.strip_suffix('"')?;
    let mut bytes = Vec::new();
    let mut chars = inner.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\\' {
            let mut buf = [0; 4];
            bytes.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
            continue;
        }
        let octal: String = std::iter::from_fn(|| chars.next_if(|d| d.is_digit(8)))
            .take(3)
            .collect();
        if octal.is_empty() {
            if let Some(next) = chars.next() {
                bytes.push(next as u8);
            }
        } else {
            bytes.push(u8::from_str_radix(&octal, 8).ok()?);
        }
    }
    String::from_utf8(bytes).ok()
}

fn user_path() -> Result<String, String> {
    let name = std::env::var("USER").map_err(|_| "USER is not set".to_string())?;
    let out = system::run_blocking(
        "busctl",
        &args(&[
            "call",
            ACCOUNTS,
            "/org/freedesktop/Accounts",
            ACCOUNTS,
            "FindUserByName",
            "s",
            &name,
        ]),
        None,
    )?;
    parse_busctl_string(&out).ok_or_else(|| format!("AccountsService gave no path: {out}"))
}

fn property(path: &str, name: &str) -> Result<String, String> {
    let out = system::run_blocking(
        "busctl",
        &args(&["get-property", ACCOUNTS, path, USER_IFACE, name]),
        None,
    )?;
    parse_busctl_string(&out).ok_or_else(|| format!("Could not read {name}"))
}

fn set(method: &'static str, value: String) -> Task<Msg> {
    let work = move || -> Result<(), String> {
        let path = user_path()?;
        system::run_blocking(
            "busctl",
            &args(&["call", ACCOUNTS, &path, USER_IFACE, method, "s", &value]),
            None,
        )
        .map(|_| ())
    };
    Task::perform(system::spawn(work), |r| {
        Msg::Done(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
    })
}

#[derive(Debug, Clone, Default)]
pub struct Reading {
    pub login: String,
    pub real_name: String,
    /// The picture, read once per load: a handle by path would keep showing
    /// the cached old picture, since the path stays the same after a change.
    pub icon: Option<image::Handle>,
}

fn read() -> Result<Reading, String> {
    let path = user_path().map_err(|e| format!("AccountsService is not available: {e}"))?;
    let icon = property(&path, "IconFile")
        .ok()
        .and_then(|p| std::fs::read(p).ok())
        .map(image::Handle::from_bytes);
    Ok(Reading {
        login: std::env::var("USER").unwrap_or_default(),
        real_name: property(&path, "RealName")?,
        icon,
    })
}

#[derive(Default)]
pub struct State {
    reading: Option<Result<Reading, String>>,
    name_draft: Option<String>,
    busy: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Result<Reading, String>),
    Name(String),
    SaveName,
    Choose,
    Picked(Result<Option<String>, String>),
    Initials,
    Done(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::perform(system::spawn(read), |r| {
                    Msg::Loaded(r.unwrap_or_else(|| Err("stopped unexpectedly".into())))
                });
            }
            Msg::Loaded(r) => {
                self.reading = Some(r);
                self.busy = false;
            }
            Msg::Name(t) => self.name_draft = Some(t),
            Msg::SaveName => {
                let Some(name) = self.name_draft.take() else {
                    return Task::none();
                };
                let name = name.trim().to_string();
                if name.is_empty() || name.contains([':', '\n']) {
                    self.error = Some("A name cannot be empty or hold a colon".into());
                    return Task::none();
                }
                self.busy = true;
                return set("SetRealName", name);
            }
            Msg::Choose => {
                let list = args(&[
                    "--file-selection",
                    "--title=Choose a picture",
                    "--file-filter=Pictures | *.jpg *.jpeg *.png *.webp",
                ]);
                return Task::perform(system::pick(list), Msg::Picked);
            }
            Msg::Picked(Ok(None)) => {}
            Msg::Picked(Err(e)) => self.error = Some(e),
            Msg::Picked(Ok(Some(path))) => {
                self.busy = true;
                return set("SetIconFile", path);
            }
            Msg::Initials => {
                self.busy = true;
                let script = home()
                    .join(".config/scripts/generate-avatar.sh")
                    .to_string_lossy()
                    .into_owned();
                return Task::perform(system::run("bash", vec![script], None), |r| Msg::Done(r.map(|_| ())));
            }
            Msg::Done(r) => {
                self.error = r.err().map(|e| format!("Not changed: {e}"));
                return self.update(Msg::Load);
            }
        }
        Task::none()
    }

    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let r = match &self.reading {
            None => return vec![ui::note("Looking…")],
            Some(Err(e)) => return vec![ui::note(e.clone())],
            Some(Ok(r)) => r,
        };
        let idle = !self.busy;
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        if let Some(icon) = &r.icon {
            let picture = image(icon.clone()).width(96).height(96);
            rows.push(container(picture).padding([8, 14]).into());
        }
        rows.push(ui::item(
            ico::IMAGE,
            "Picture".into(),
            "Lock and login screens".into(),
            vec![ui::button_group(vec![
                ("Choose…", idle.then_some(Msg::Choose), Action::Normal),
                ("Make initials picture", idle.then_some(Msg::Initials), Action::Normal),
            ])],
        ));
        let shown = self.name_draft.as_deref().unwrap_or(&r.real_name);
        let field = text_input("Full name", shown)
            .on_input(Msg::Name)
            .on_submit(Msg::SaveName)
            .padding([6, 10])
            .width(Length::Fixed(260.0))
            .style(style::field);
        rows.push(ui::item(
            ico::USER,
            "Full name".into(),
            format!("Login name {} · Enter to save", r.login),
            vec![field.into()],
        ));
        rows
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_busctl_strings() {
        assert_eq!(parse_busctl_string("s \"Ann Lee\"\n"), Some("Ann Lee".into()));
        assert_eq!(parse_busctl_string("s \"G\\303\\274nther\""), Some("Günther".into()));
        assert_eq!(
            parse_busctl_string("o \"/org/freedesktop/Accounts/User1000\""),
            Some("/org/freedesktop/Accounts/User1000".into())
        );
        assert_eq!(parse_busctl_string("s \"say \\\"hi\\\"\""), Some("say \"hi\"".into()));
        assert_eq!(parse_busctl_string(""), None);
    }
}
