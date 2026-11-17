//! The window: the sidebar (sidebar.rs) and the open panel: settings read
//! from and written to the Quickshell settings store, or the Network and
//! Bluetooth pages (network.rs, bluetooth.rs).

use std::collections::HashMap;
use std::time::{Duration, Instant};

use iced::keyboard as keys;
use iced::widget::{Column, Space, column, container, responsive, row, scrollable, text};
use iced::{Element, Length, Subscription, Task, Theme};

use crate::audio;
use crate::bluetooth;
use crate::calendar;
use crate::controls;
use crate::keyboard;
use crate::network;
use crate::reveal;
use crate::schema::{PANELS, Page, Panel, Section, all_settings};
use crate::sidebar;
use crate::store::{Store, Value};
use crate::style;
use crate::ui;

/// How often the files are read again, so changes made in the shell show up.
const RELOAD_EVERY: Duration = Duration::from_secs(1);
/// How often the open Network or Bluetooth page asks the system again.
const SYSTEM_REFRESH_EVERY: Duration = Duration::from_secs(3);
pub const SEARCH_ID: &str = "search";
/// How long a revealed setting stays outlined (cleared on the next reload
/// tick after it).
const HIGHLIGHT_FOR: Duration = Duration::from_secs(2);
const SIDEBAR_WIDTH: f32 = 230.0;
const SIDEBAR_COMPACT_WIDTH: f32 = 64.0;
/// Below this window width the sidebar shows only icons.
const COMPACT_SIDEBAR_BELOW: f32 = 820.0;
/// Below this panel width controls go under their labels.
const STACK_BELOW: f32 = 640.0;

/// How the window adapts to its width.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Layout {
    pub compact_sidebar: bool,
    pub sidebar_width: f32,
    pub stacked: bool,
}

impl Layout {
    /// `searching` keeps the full sidebar, for the search field, however
    /// narrow the window.
    pub fn for_width(width: f32, searching: bool) -> Self {
        let compact_sidebar = width < COMPACT_SIDEBAR_BELOW && !searching;
        let sidebar_width = if compact_sidebar {
            SIDEBAR_COMPACT_WIDTH
        } else {
            SIDEBAR_WIDTH
        };
        Layout {
            compact_sidebar,
            sidebar_width,
            stacked: width - sidebar_width - 1.0 < STACK_BELOW,
        }
    }
}

pub struct App {
    panel: usize,
    store: Store,
    values: HashMap<&'static str, Value>,
    /// Text being typed into an entry, applied on Enter.
    drafts: HashMap<&'static str, String>,
    /// Slider being dragged: shown live, written once on release, and not
    /// reloaded from its file meanwhile.
    dragging: Option<&'static str>,
    /// Text in the sidebar search field.
    query: String,
    /// The search field is in use (it widens a compact sidebar).
    searching: bool,
    /// Setting a search result pointed at, outlined until the time passes.
    highlight: Option<(&'static str, Instant)>,
    network: network::State,
    bluetooth: bluetooth::State,
    audio: audio::State,
    calendar: calendar::State,
    keyboard: keyboard::State,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Message {
    SelectPanel(usize),
    Set(&'static str, Value),
    /// A slider moved: show the value, write it on Commit.
    Preview(&'static str, Value),
    Commit(&'static str),
    Draft(&'static str, String),
    Submit(&'static str),
    Search(String),
    /// Ctrl+F or the search glyph: put the cursor in the search field.
    FocusSearch,
    /// Escape: empty the search field.
    ClearSearch,
    /// A search result: open the panel, scroll to the setting, outline it.
    Reveal(usize, &'static str),
    Reload,
    Network(network::Msg),
    Bluetooth(bluetooth::Msg),
    Audio(audio::Msg),
    Calendar(calendar::Msg),
    Keyboard(keyboard::Msg),
}

impl App {
    /// The app, and the first refresh of its panel when that shows system
    /// state.
    pub fn new(panel: usize, query: String, store: Store) -> (Self, Task<Message>) {
        let searching = !query.is_empty();
        let mut app = App {
            panel,
            store,
            values: HashMap::new(),
            drafts: HashMap::new(),
            dragging: None,
            query,
            searching,
            highlight: None,
            network: network::State::default(),
            bluetooth: bluetooth::State::default(),
            audio: audio::State::default(),
            calendar: calendar::State::default(),
            keyboard: keyboard::State::default(),
            error: None,
        };
        app.reload();
        let task = app.refresh_page();
        (app, task)
    }

    /// Ask the system again, when the open panel shows system state.
    fn refresh_page(&mut self) -> Task<Message> {
        match PANELS[self.panel].page {
            Page::Settings => Task::none(),
            Page::Network => self.network.update(network::Msg::Refresh).map(Message::Network),
            Page::Bluetooth => self.bluetooth.update(bluetooth::Msg::Refresh).map(Message::Bluetooth),
            Page::Sound => self.audio.update(audio::Msg::Refresh).map(Message::Audio),
            Page::Calendar => {
                self.calendar.update(calendar::Msg::Refresh);
                Task::none()
            }
            Page::Keyboard => self.keyboard.update(keyboard::Msg::Load).map(Message::Keyboard),
        }
    }

    fn reload(&mut self) {
        for (file, kind, default) in all_settings().flat_map(|s| s.files()) {
            if self.dragging == Some(file) {
                continue;
            }
            let value = self.store.read(file, kind).unwrap_or(default);
            self.values.insert(file, value);
        }
    }

    fn text_of(&self, file: &'static str) -> String {
        match self.values.get(file) {
            Some(Value::Text(t)) => t.clone(),
            _ => String::new(),
        }
    }

    fn write(&mut self, file: &'static str, value: Value) {
        match self.store.write(file, &value) {
            Ok(()) => {
                self.values.insert(file, value);
                self.error = None;
            }
            Err(e) => self.error = Some(format!("Could not save {file}: {e}")),
        }
    }

    pub fn title(&self) -> String {
        format!("Settings — {}", PANELS[self.panel].title)
    }

    pub fn theme(&self) -> Theme {
        style::theme(style::accent(
            &self.text_of("accent-primary"),
            &self.text_of("accent-auto-hex"),
        ))
    }

    pub fn subscription(&self) -> Subscription<Message> {
        let keys = keys::listen().filter_map(|event| match event {
            keys::Event::KeyPressed { key, modifiers, .. } => match key.as_ref() {
                keys::Key::Character("f") if modifiers.command() => Some(Message::FocusSearch),
                keys::Key::Named(keys::key::Named::Escape) => Some(Message::ClearSearch),
                _ => None,
            },
            _ => None,
        });
        let mut subscriptions = vec![iced::time::every(RELOAD_EVERY).map(|_| Message::Reload), keys];
        // Subscription::map takes only closures that capture nothing.
        match PANELS[self.panel].page {
            Page::Settings => {}
            Page::Network => subscriptions
                .push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Network(network::Msg::Refresh))),
            Page::Bluetooth => subscriptions
                .push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Bluetooth(bluetooth::Msg::Refresh))),
            Page::Sound => {
                subscriptions.push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Audio(audio::Msg::Refresh)))
            }
            Page::Calendar => subscriptions
                .push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Calendar(calendar::Msg::Refresh))),
            Page::Keyboard => {}
        }
        Subscription::batch(subscriptions)
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectPanel(i) => {
                self.panel = i;
                // The results stay in a full sidebar; a compact one folds
                // back to give the panel its room.
                self.searching = false;
                return self.refresh_page();
            }
            Message::Network(msg) => return self.network.update(msg).map(Message::Network),
            Message::Bluetooth(msg) => return self.bluetooth.update(msg).map(Message::Bluetooth),
            Message::Audio(msg) => return self.audio.update(msg).map(Message::Audio),
            Message::Calendar(msg) => self.calendar.update(msg),
            Message::Keyboard(msg) => return self.keyboard.update(msg).map(Message::Keyboard),
            Message::Search(query) => {
                self.query = query;
                self.searching = true;
            }
            Message::FocusSearch => {
                self.searching = true;
                return iced::widget::operation::focus(SEARCH_ID);
            }
            Message::ClearSearch => {
                self.query.clear();
                self.searching = false;
            }
            Message::Set(file, value) => self.write(file, value),
            Message::Preview(file, value) => {
                self.dragging = Some(file);
                self.values.insert(file, value);
            }
            Message::Commit(file) => {
                self.dragging = None;
                if let Some(value) = self.values.get(file).cloned() {
                    self.write(file, value);
                }
            }
            Message::Draft(file, draft) => {
                self.drafts.insert(file, draft);
            }
            Message::Submit(file) => {
                if let Some(draft) = self.drafts.remove(file) {
                    self.write(file, Value::Text(draft.trim().to_string()));
                }
            }
            Message::Reveal(panel, file) => {
                self.panel = panel;
                self.searching = false;
                self.highlight = Some((file, Instant::now()));
                return reveal::reveal(PANELS[panel].id, file);
            }
            Message::Reload => {
                self.reload();
                if self
                    .highlight
                    .is_some_and(|(_, since)| since.elapsed() >= HIGHLIGHT_FOR)
                {
                    self.highlight = None;
                }
            }
        }
        Task::none()
    }

    pub fn view(&self) -> Element<'_, Message> {
        responsive(move |size| {
            let layout = Layout::for_width(size.width, self.searching);
            let divider = container(Space::new())
                .width(1)
                .height(Length::Fill)
                .style(style::divider);
            row![
                sidebar::view(self.panel, &self.query, layout),
                divider,
                self.panel_view(&PANELS[self.panel], layout)
            ]
            .into()
        })
        .into()
    }

    fn panel_view(&self, panel: &'static Panel, layout: Layout) -> Element<'_, Message> {
        let content: Element<'_, Message> = match panel.page {
            Page::Settings => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Network => Element::from(self.network.view(page_column(panel.title, layout))).map(Message::Network),
            Page::Bluetooth => {
                Element::from(self.bluetooth.view(page_column(panel.title, layout))).map(Message::Bluetooth)
            }
            Page::Sound => {
                let max_volume = match self.values.get("max-volume") {
                    Some(Value::Int(n)) => *n,
                    _ => 100,
                };
                Element::from(self.audio.view(page_column(panel.title, layout), max_volume)).map(Message::Audio)
            }
            Page::Calendar => {
                let feeds = Element::from(self.calendar.view(page_column(panel.title, layout))).map(Message::Calendar);
                let pad = if layout.stacked { 16.0 } else { 28.0 };
                let mut options = Column::new()
                    .spacing(10)
                    .padding(iced::Padding {
                        top: 0.0,
                        right: pad,
                        bottom: pad,
                        left: pad,
                    })
                    .max_width(760);
                for section in panel.sections {
                    options = self.section(options, section, layout);
                }
                column![feeds, options].into()
            }
            Page::Keyboard => {
                Element::from(self.keyboard.view(page_column(panel.title, layout))).map(Message::Keyboard)
            }
        };
        // One scroll position per panel.
        scrollable(container(content).center_x(Length::Fill))
            .id(panel.id)
            .height(Length::Fill)
            .into()
    }

    /// A section header and a card of setting rows.
    fn section<'a>(
        &'a self,
        body: Column<'a, Message>,
        section: &'static Section,
        layout: Layout,
    ) -> Column<'a, Message> {
        let rows = section.settings.iter().map(|s| {
            let highlighted = self.highlight.is_some_and(|(file, _)| file == s.file);
            controls::setting_row(s, &self.values, self.drafts.get(s.file), layout.stacked, highlighted)
        });
        ui::section(body, section.title, rows.collect())
    }
}

/// A panel's column, starting with its title.
fn page_column<'a, M: 'a>(title: &'static str, layout: Layout) -> Column<'a, M> {
    let (padding, title_size) = if layout.stacked { (16, 20) } else { (28, 24) };
    column![text(title).font(style::FONT_BOLD).size(title_size)]
        .spacing(10)
        .padding(padding)
        .max_width(760)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_adapts_to_the_window_width() {
        let wide = Layout::for_width(1200.0, false);
        assert!(!wide.compact_sidebar && !wide.stacked);
        // Full sidebar, but the panel beside it is too narrow for rows.
        let medium = Layout::for_width(850.0, false);
        assert!(!medium.compact_sidebar && medium.stacked);
        // Icon sidebar gives the panel room for rows again.
        let narrowish = Layout::for_width(800.0, false);
        assert!(narrowish.compact_sidebar && !narrowish.stacked);
        let narrow = Layout::for_width(500.0, false);
        assert!(narrow.compact_sidebar && narrow.stacked);
    }

    #[test]
    fn searching_keeps_the_full_sidebar() {
        let narrow = Layout::for_width(500.0, true);
        assert!(!narrow.compact_sidebar);
        assert_eq!(narrow.sidebar_width, SIDEBAR_WIDTH);
    }
}
