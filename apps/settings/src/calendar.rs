//! Calendar feeds, kept in ~/.config/quickshell/calendar.url, one per line:
//!
//!     [#off ]<url>[ #color=<colour>][ #name=<name>]
//!
//! The shell's IcsCalendar watches the file, fetches the feeds that are on
//! (a feed switched off is a "#off" comment) and colours each feed's events
//! with its #color (IcsParse.js parseFeedList). Other comment lines are kept
//! at the top. The links carry private tokens, so the panel shows them
//! shortened, never fills a field with one, and the file stays readable only
//! by the user.

use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

use iced::widget::{column, container, row, text, text_input};
use iced::{Alignment, Element, Length};

use crate::style::{self, Action};
use crate::ui;

/// Feed colours: (name in the file, label, colour). The empty name is the
/// colour by position, in this order (IcsCalendar.qml `feedColors`).
const COLORS: &[(&str, &str, u32)] = &[
    ("blue", "Blue", 0x4c9aff),
    ("orange", "Orange", 0xff7a1a),
    ("red", "Red", 0xff4d5e),
    ("green", "Green", 0x2ee59d),
    ("purple", "Purple", 0xb57bff),
    ("pink", "Pink", 0xff6fb5),
    ("teal", "Teal", 0x2ee6d6),
];

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Feed {
    pub url: String,
    pub name: String,
    /// A COLORS name, or empty for the colour by position.
    pub color: String,
    pub on: bool,
}

/// The feed being edited: its name, a new link (empty keeps the old one)
/// and its colour.
#[derive(Debug, Clone, Default)]
struct Editor {
    index: usize,
    name: String,
    link: String,
    color: String,
}

#[derive(Default)]
pub struct State {
    comments: Vec<String>,
    feeds: Vec<Feed>,
    draft: String,
    editor: Option<Editor>,
    /// Feed whose Remove was picked once; picking it again removes it.
    confirming: Option<usize>,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Refresh,
    Draft(String),
    Add,
    Switch(usize, bool),
    Edit(usize),
    EditName(String),
    EditLink(String),
    EditColor(&'static str),
    Save,
    Cancel,
    MoveUp(usize),
    Remove(usize),
}

fn path() -> PathBuf {
    crate::store::home().join(".config/quickshell/calendar.url")
}

/// One feed line's parts after the "#off " marker: link, colour, name.
fn parse_body(body: &str) -> Option<Feed> {
    let url = body.split_whitespace().next()?;
    if !url.contains("://") {
        return None;
    }
    let color = body
        .split_whitespace()
        .find_map(|w| w.strip_prefix("#color="))
        .unwrap_or_default()
        .to_string();
    let name = body
        .split_once(" #name=")
        .map(|(_, n)| n.trim().to_string())
        .unwrap_or_default();
    Some(Feed {
        url: url.into(),
        name,
        color,
        on: true,
    })
}

/// The file's other comment lines and its feeds, in order.
pub fn parse(text: &str) -> (Vec<String>, Vec<Feed>) {
    let (mut comments, mut feeds) = (Vec::new(), Vec::new());
    for line in text.lines().map(str::trim).filter(|l| !l.is_empty()) {
        if let Some(body) = line.strip_prefix("#off ") {
            match parse_body(body) {
                Some(feed) => feeds.push(Feed { on: false, ..feed }),
                None => comments.push(line.to_string()),
            }
        } else if line.starts_with('#') {
            comments.push(line.to_string());
        } else if let Some(feed) = parse_body(line) {
            feeds.push(feed);
        }
    }
    (comments, feeds)
}

/// The file's text: comments first, then one line per feed.
pub fn render(comments: &[String], feeds: &[Feed]) -> String {
    let mut out = String::new();
    for c in comments {
        out.push_str(c);
        out.push('\n');
    }
    for f in feeds {
        if !f.on {
            out.push_str("#off ");
        }
        out.push_str(&f.url);
        if !f.color.is_empty() {
            out.push_str(&format!(" #color={}", f.color));
        }
        if !f.name.is_empty() {
            out.push_str(&format!(" #name={}", f.name));
        }
        out.push('\n');
    }
    out
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

/// A link as it goes in the file: webcal:// becomes https://, anything that
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

/// A name fit for one line of the file.
fn clean_name(name: &str) -> String {
    name.chars()
        .filter(|c| !c.is_control())
        .collect::<String>()
        .trim()
        .to_string()
}

/// The colour a feed is drawn in: its own, else the one for its position
/// among the feeds that are on.
fn color_of(feeds: &[Feed], index: usize) -> iced::Color {
    let feed = &feeds[index];
    let hex = COLORS
        .iter()
        .find(|(n, _, _)| *n == feed.color)
        .map(|(_, _, h)| *h)
        .unwrap_or_else(|| {
            let position = feeds[..index].iter().filter(|f| f.on).count();
            COLORS[position % COLORS.len()].2
        });
    style::from_hex(hex)
}

/// Write atomically, readable only by the user.
fn write(text: &str) -> io::Result<()> {
    let target = path();
    let tmp = target.with_extension("url.tmp");
    fs::write(&tmp, text)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(0o600))?;
    fs::rename(&tmp, &target)
}

impl State {
    /// Read calendar.url; a missing file is no feeds. A file that cannot be
    /// read keeps the list shown and says so, and no change is written over
    /// it (that would drop the feeds it holds).
    fn load(&mut self) -> Result<(), String> {
        let text = match fs::read_to_string(path()) {
            Ok(t) => t,
            Err(e) if e.kind() == io::ErrorKind::NotFound => String::new(),
            Err(e) => {
                let e = format!("Could not read calendar.url: {e}");
                self.error = Some(e.clone());
                return Err(e);
            }
        };
        if self
            .error
            .as_deref()
            .is_some_and(|e| e.starts_with("Could not read calendar.url"))
        {
            self.error = None;
        }
        let (comments, feeds) = parse(&text);
        self.comments = comments;
        self.feeds = feeds;
        Ok(())
    }

    /// Change the feeds and write the file.
    fn change(&mut self, edit: impl FnOnce(&mut Vec<Feed>) -> Result<(), String>) {
        if self.load().is_err() {
            return;
        }
        let mut feeds = self.feeds.clone();
        let result = edit(&mut feeds).and_then(|()| {
            write(&render(&self.comments, &feeds)).map_err(|e| format!("Could not save calendar.url: {e}"))
        });
        match result {
            Ok(()) => {
                self.feeds = feeds;
                self.error = None;
            }
            Err(e) => self.error = Some(e),
        }
    }

    pub fn update(&mut self, msg: Msg) {
        if !matches!(msg, Msg::Remove(_) | Msg::Refresh) {
            self.confirming = None;
        }
        match msg {
            // Keep what the user is editing; the list itself follows the file.
            Msg::Refresh => {
                let _ = self.load();
            }
            Msg::Draft(text) => self.draft = text,
            Msg::Add => match normalize(&self.draft) {
                Ok(url) if self.feeds.iter().any(|f| f.url == url) => {
                    self.error = Some("That feed is already in the list".into())
                }
                Ok(url) => {
                    self.draft.clear();
                    self.change(|feeds| {
                        feeds.push(Feed {
                            url,
                            on: true,
                            ..Feed::default()
                        });
                        Ok(())
                    });
                }
                Err(e) => self.error = Some(e),
            },
            Msg::Switch(i, on) => self.change(|feeds| {
                feeds.get_mut(i).ok_or("That feed is gone")?.on = on;
                Ok(())
            }),
            Msg::Edit(i) => {
                if let Some(f) = self.feeds.get(i) {
                    self.editor = Some(Editor {
                        index: i,
                        name: f.name.clone(),
                        link: String::new(),
                        color: f.color.clone(),
                    });
                }
            }
            Msg::EditName(text) => {
                if let Some(e) = &mut self.editor {
                    e.name = text;
                }
            }
            Msg::EditLink(text) => {
                if let Some(e) = &mut self.editor {
                    e.link = text;
                }
            }
            Msg::EditColor(color) => {
                if let Some(e) = &mut self.editor {
                    e.color = color.to_string();
                }
            }
            Msg::Cancel => self.editor = None,
            Msg::Save => {
                if let Some(editor) = self.editor.take() {
                    let link = if editor.link.trim().is_empty() {
                        None
                    } else {
                        Some(normalize(&editor.link))
                    };
                    if let Some(Err(e)) = link {
                        self.error = Some(e);
                        self.editor = Some(editor);
                        return;
                    }
                    self.change(|feeds| {
                        let feed = feeds.get_mut(editor.index).ok_or("That feed is gone")?;
                        feed.name = clean_name(&editor.name);
                        feed.color = editor.color.clone();
                        if let Some(Ok(url)) = link {
                            feed.url = url;
                        }
                        Ok(())
                    });
                }
            }
            Msg::MoveUp(i) => self.change(|feeds| {
                if i > 0 && i < feeds.len() {
                    feeds.swap(i - 1, i);
                }
                Ok(())
            }),
            Msg::Remove(i) if self.confirming != Some(i) => self.confirming = Some(i),
            Msg::Remove(i) => {
                self.confirming = None;
                self.editor = None;
                self.change(|feeds| {
                    if i < feeds.len() {
                        feeds.remove(i);
                    }
                    Ok(())
                });
            }
        }
    }

    /// The feeds, each with its editor when open, then the add field.
    pub fn rows(&self) -> Vec<Element<'_, Msg>> {
        let mut rows: Vec<Element<'_, Msg>> = Vec::new();
        if let Some(e) = &self.error {
            rows.push(ui::error(e));
        }
        for (i, feed) in self.feeds.iter().enumerate() {
            rows.push(self.feed_row(i, feed));
            if let Some(editor) = self.editor.as_ref().filter(|e| e.index == i) {
                rows.push(self.editor_view(editor));
            }
        }
        if rows.is_empty() {
            rows.push(ui::note("No feeds yet"));
        }
        let field = text_input("Add a feed: https://… or webcal://… (.ics link)", &self.draft)
            .on_input(Msg::Draft)
            .on_submit(Msg::Add);
        let add = (!self.draft.trim().is_empty()).then_some(Msg::Add);
        rows.push(
            container(ui::input_group(field, vec![("Add", add, Action::Primary)]))
                .padding([8, 14])
                .into(),
        );
        rows
    }

    fn feed_row<'a>(&'a self, i: usize, feed: &'a Feed) -> Element<'a, Msg> {
        let color = color_of(&self.feeds, i);
        let dot = container(text(""))
            .width(12)
            .height(12)
            .style(move |_| style::dot(if feed.on { color } else { style::MUTED_DEEP }));
        let (title, detail) = if feed.name.is_empty() {
            (mask(&feed.url), String::new())
        } else {
            (feed.name.clone(), mask(&feed.url))
        };
        let detail = if feed.on {
            detail
        } else {
            format!("Off · {detail}").trim_end_matches(" · ").to_string()
        };
        let mut info = column![
            text(title)
                .size(14)
                .color(if feed.on { style::FG } else { style::FG_MUTED })
        ]
        .spacing(2)
        .width(Length::Fill);
        if !detail.is_empty() {
            info = info.push(text(detail).size(12).color(style::MUTED_DEEP));
        }
        let remove = if self.confirming == Some(i) {
            "Remove — sure?"
        } else {
            "Remove"
        };
        let menu = ui::menu(vec![
            ("Edit", Some(Msg::Edit(i))),
            ("Move up", (i > 0).then_some(Msg::MoveUp(i))),
            (remove, Some(Msg::Remove(i))),
        ]);
        let line = row![dot, info, menu, ui::switch(feed.on, Some(move |on| Msg::Switch(i, on)))]
            .spacing(14)
            .align_y(Alignment::Center);
        container(line).padding([10, 14]).into()
    }

    fn editor_view<'a>(&'a self, editor: &'a Editor) -> Element<'a, Msg> {
        let name = text_input("Name, e.g. Work", &editor.name)
            .on_input(Msg::EditName)
            .on_submit(Msg::Save);
        let link = text_input("New link (leave empty to keep the current one)", &editor.link)
            .on_input(Msg::EditLink)
            .on_submit(Msg::Save);
        let mut colors = vec![("Automatic", editor.color.is_empty(), Some(Msg::EditColor("")))];
        colors.extend(
            COLORS
                .iter()
                .map(|(key, label, _)| (*label, editor.color == *key, Some(Msg::EditColor(key)))),
        );
        let line = |label: &'a str, control: Element<'a, Msg>| {
            row![text(label).size(13).color(style::FG_MUTED).width(70), control]
                .spacing(10)
                .align_y(Alignment::Center)
        };
        container(
            column![
                line("Name", ui::fields_group(vec![name], vec![])),
                line("Link", ui::fields_group(vec![link], vec![])),
                line("Colour", ui::choice(colors, Length::Fixed(220.0))),
                row![
                    iced::widget::Space::new().width(Length::Fill),
                    ui::button_group(vec![
                        ("Cancel", Some(Msg::Cancel), Action::Normal),
                        ("Save", Some(Msg::Save), Action::Primary),
                    ])
                ],
            ]
            .spacing(8),
        )
        .padding([6, 14])
        .style(style::card)
        .into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "# my feeds\nhttps://a.example/cal/secret/basic.ics #color=teal #name=Work and study\n#off https://b.example/old.ics #name=Old\n# a note\n\nhttps://c.example/feed?token=abc\n";

    #[test]
    fn reads_feeds_states_colours_and_names() {
        let (comments, feeds) = parse(FILE);
        assert_eq!(comments, ["# my feeds", "# a note"]);
        assert_eq!(feeds.len(), 3);
        assert_eq!(
            feeds[0],
            Feed {
                url: "https://a.example/cal/secret/basic.ics".into(),
                name: "Work and study".into(),
                color: "teal".into(),
                on: true
            }
        );
        assert!(!feeds[1].on);
        assert_eq!(feeds[1].name, "Old");
        assert_eq!(feeds[2].color, "");
    }

    #[test]
    fn writes_back_what_it_read() {
        let (comments, feeds) = parse(FILE);
        let text = render(&comments, &feeds);
        assert_eq!(parse(&text), (comments, feeds));
        assert!(text.contains("#off https://b.example/old.ics #name=Old\n"));
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
    fn normalizes_links_and_names() {
        assert_eq!(
            normalize(" webcal://p.example/x.ics "),
            Ok("https://p.example/x.ics".into())
        );
        assert!(normalize("ftp://x").is_err());
        assert!(normalize("https://a b").is_err());
        assert_eq!(clean_name(" Work\nstuff "), "Workstuff");
    }

    #[test]
    fn colours_by_position_skip_feeds_that_are_off() {
        let feeds = vec![
            Feed {
                url: "https://a".into(),
                on: false,
                ..Feed::default()
            },
            Feed {
                url: "https://b".into(),
                on: true,
                ..Feed::default()
            },
            Feed {
                url: "https://c".into(),
                color: "pink".into(),
                on: true,
                ..Feed::default()
            },
        ];
        assert_eq!(color_of(&feeds, 1), style::from_hex(0x4c9aff));
        assert_eq!(color_of(&feeds, 2), style::from_hex(0xff6fb5));
    }
}
