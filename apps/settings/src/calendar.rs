//! Calendar feeds: the ICS URLs in ~/.config/quickshell/calendar.url (one
//! per line, blank lines and #-comments allowed). The shell's IcsCalendar
//! watches the file and fetches again when it changes. The URLs carry
//! private tokens, so the panel shows them shortened and the file stays
//! readable only by the user.

use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

use iced::widget::{Column, container, row, text, text_input};
use iced::{Alignment, Element, Length};

use crate::style::{self, Action};
use crate::ui;

/// Colours of the feeds in the day panel, in feed order (IcsCalendar.qml
/// `feedColors`, from Theme.base).
const FEED_COLORS: [u32; 7] = [0x4c9aff, 0xff7a1a, 0xff4d5e, 0x2ee59d, 0xb57bff, 0xff6fb5, 0x2ee6d6];

#[derive(Default)]
pub struct State {
    feeds: Vec<String>,
    draft: String,
    /// Feed whose Remove was clicked once; a second click removes it.
    confirming: Option<usize>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Draft(String),
    Add,
    Remove(usize),
}

fn path() -> PathBuf {
    crate::store::home().join(".config/quickshell/calendar.url")
}

/// The feed URLs in the file's text.
pub fn parse_feeds(text: &str) -> Vec<String> {
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(String::from)
        .collect()
}

/// "host · …/file.ics": enough to tell feeds apart, without the token.
pub fn mask(url: &str) -> String {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    let rest = rest.split(['?', '#']).next().unwrap_or(rest);
    let mut parts = rest.split('/').filter(|p| !p.is_empty());
    let host = parts.next().unwrap_or("");
    match parts.next_back() {
        Some(file) => format!("{host} · …/{file}"),
        None => host.to_string(),
    }
}

/// A URL as it goes in the file: webcal:// becomes https://, anything that
/// is not http(s) or has spaces is refused.
pub fn normalize(input: &str) -> Result<String, String> {
    let url = input.trim();
    let url = match url.strip_prefix("webcal://") {
        Some(rest) => format!("https://{rest}"),
        None => url.to_string(),
    };
    if !(url.starts_with("https://") || url.starts_with("http://")) || url.contains(char::is_whitespace) {
        return Err("Enter an https://, http:// or webcal:// link".into());
    }
    Ok(url)
}

/// The file's text with one more feed at the end.
pub fn with_feed(text: &str, url: &str) -> String {
    let mut out = text.to_string();
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    out.push_str(url);
    out.push('\n');
    out
}

/// The file's text without its `index`-th feed; other lines stay as they are.
pub fn without_feed(text: &str, index: usize) -> String {
    let mut seen = 0;
    let mut out = String::new();
    for line in text.lines() {
        let trimmed = line.trim();
        let is_feed = !trimmed.is_empty() && !trimmed.starts_with('#');
        if is_feed {
            seen += 1;
            if seen - 1 == index {
                continue;
            }
        }
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// Write atomically, readable only by the user.
fn write(text: &str) -> io::Result<()> {
    let target = path();
    let tmp = target.with_extension("url.tmp");
    fs::write(&tmp, text)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))?;
    fs::rename(&tmp, &target)
}

fn read() -> String {
    fs::read_to_string(path()).unwrap_or_default()
}

impl State {
    pub fn update(&mut self, msg: Msg) {
        if !matches!(msg, Msg::Remove(_) | Msg::Refresh) {
            self.confirming = None;
        }
        match msg {
            Msg::Refresh => self.feeds = parse_feeds(&read()),
            Msg::Draft(text) => self.draft = text,
            Msg::Add => match normalize(&self.draft) {
                Ok(url) if self.feeds.contains(&url) => self.error = Some("That feed is already in the list".into()),
                Ok(url) => match write(&with_feed(&read(), &url)) {
                    Ok(()) => {
                        self.draft.clear();
                        self.error = None;
                        self.feeds = parse_feeds(&read());
                    }
                    Err(e) => self.error = Some(format!("Could not save calendar.url: {e}")),
                },
                Err(e) => self.error = Some(e),
            },
            Msg::Remove(index) if self.confirming != Some(index) => self.confirming = Some(index),
            Msg::Remove(index) => match write(&without_feed(&read(), index)) {
                Ok(()) => {
                    self.confirming = None;
                    self.error = None;
                    self.feeds = parse_feeds(&read());
                }
                Err(e) => self.error = Some(format!("Could not save calendar.url: {e}")),
            },
        }
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let mut rows: Vec<Element<'a, Msg>> = self
            .feeds
            .iter()
            .enumerate()
            .map(|(i, url)| {
                let color = style::from_hex(FEED_COLORS[i % FEED_COLORS.len()]);
                let dot = container(text(""))
                    .width(12)
                    .height(12)
                    .style(move |_| style::dot(color));
                let line = row![
                    dot,
                    text(mask(url)).size(14).color(style::FG).width(Length::Fill),
                    ui::action(
                        if self.confirming == Some(i) { "Sure?" } else { "Remove" },
                        Some(Msg::Remove(i)),
                        Action::Danger,
                    ),
                ]
                .spacing(14)
                .align_y(Alignment::Center);
                container(line).padding([10, 14]).into()
            })
            .collect();
        if rows.is_empty() {
            rows.push(ui::note("No feeds yet"));
        }
        let field = text_input("https://… or webcal://… (.ics link)", &self.draft)
            .on_input(Msg::Draft)
            .on_submit(Msg::Add);
        let add = (!self.draft.trim().is_empty()).then_some(Msg::Add);
        rows.push(
            container(ui::input_group(field, vec![("Add", add, Action::Primary)]))
                .padding([8, 14])
                .into(),
        );
        ui::section(body, "Feeds", rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "# work\nhttps://a.example/cal/secret123/basic.ics\n\nhttps://d.example/two.ics\n# off: https://b.example/x.ics\nhttps://c.example/feed?token=abc\n";

    #[test]
    fn reads_feed_lines_only() {
        assert_eq!(
            parse_feeds(FILE),
            [
                "https://a.example/cal/secret123/basic.ics",
                "https://d.example/two.ics",
                "https://c.example/feed?token=abc"
            ]
        );
    }

    #[test]
    fn masks_tokens() {
        assert_eq!(
            mask("https://a.example/cal/secret123/basic.ics"),
            "a.example · …/basic.ics"
        );
        assert_eq!(mask("https://c.example/feed?token=abc"), "c.example · …/feed");
        assert_eq!(mask("https://host.only"), "host.only");
    }

    #[test]
    fn normalizes_links() {
        assert_eq!(
            normalize(" webcal://p.example/x.ics "),
            Ok("https://p.example/x.ics".into())
        );
        assert_eq!(
            normalize("https://p.example/x.ics"),
            Ok("https://p.example/x.ics".into())
        );
        assert!(normalize("ftp://x").is_err());
        assert!(normalize("https://a b").is_err());
    }

    #[test]
    fn adds_and_removes_keeping_other_lines() {
        assert_eq!(with_feed("a", "b"), "a\nb\n");
        assert_eq!(with_feed("", "b"), "b\n");
        let removed = without_feed(FILE, 1);
        assert!(!removed.contains("two.ics"));
        assert!(removed.contains("# work") && removed.contains("# off: https://b.example/x.ics"));
        assert_eq!(parse_feeds(&removed).len(), 2);
    }
}
