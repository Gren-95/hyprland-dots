//! The window: the sidebar (sidebar.rs) and the open panel's settings, read
//! from and written to the Quickshell settings store.

use std::collections::HashMap;
use std::time::Duration;

use iced::widget::{Column, Space, column, container, responsive, row, scrollable, text};
use iced::{Element, Length, Subscription, Task, Theme, keyboard};

use crate::controls;
use crate::schema::{PANELS, Panel, Section, all_settings};
use crate::sidebar;
use crate::store::{Store, Value};
use crate::style;

/// How often the files are read again, so changes made in the shell show up.
const RELOAD_EVERY: Duration = Duration::from_secs(1);
pub const SEARCH_ID: &str = "search";
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
    Reload,
}

impl App {
    pub fn new(panel: usize, query: String, store: Store) -> Self {
        let searching = !query.is_empty();
        let mut app = App {
            panel,
            store,
            values: HashMap::new(),
            drafts: HashMap::new(),
            dragging: None,
            query,
            searching,
            error: None,
        };
        app.reload();
        app
    }

    fn reload(&mut self) {
        for s in all_settings() {
            if self.dragging == Some(s.file) {
                continue;
            }
            let value = self.store.read(s.file, s.kind()).unwrap_or_else(|| s.default_value());
            self.values.insert(s.file, value);
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
        let keys = keyboard::listen().filter_map(|event| match event {
            keyboard::Event::KeyPressed { key, modifiers, .. } => match key.as_ref() {
                keyboard::Key::Character("f") if modifiers.command() => Some(Message::FocusSearch),
                keyboard::Key::Named(keyboard::key::Named::Escape) => Some(Message::ClearSearch),
                _ => None,
            },
            _ => None,
        });
        Subscription::batch([iced::time::every(RELOAD_EVERY).map(|_| Message::Reload), keys])
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectPanel(i) => {
                self.panel = i;
                // The results stay in a full sidebar; a compact one folds
                // back to give the panel its room.
                self.searching = false;
            }
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
            Message::Reload => self.reload(),
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
        let (padding, title_size) = if layout.stacked { (16, 20) } else { (28, 24) };
        let mut body = column![text(panel.title).font(style::FONT_BOLD).size(title_size)]
            .spacing(10)
            .padding(padding)
            .max_width(760);
        for section in panel.sections {
            body = self.section(body, section, layout);
        }
        if let Some(error) = &self.error {
            body = body.push(text(error).color(style::RED));
        }
        // One scroll position per panel.
        scrollable(container(body).center_x(Length::Fill))
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
            let value = self.values.get(s.file).cloned().unwrap_or_else(|| s.default_value());
            controls::setting_row(s, value, self.drafts.get(s.file), layout.stacked)
        });
        body.push(Space::new().height(8))
            .push(
                text(section.title.to_uppercase())
                    .font(style::FONT_BOLD)
                    .size(11)
                    .color(style::MUTED_DEEP),
            )
            .push(container(column(rows).spacing(2)).padding(6).style(style::card))
    }
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
