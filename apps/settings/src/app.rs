//! The window: the sidebar (sidebar.rs) and the open panel: settings read
//! from and written to the Quickshell settings store, or the Network and
//! Bluetooth pages (network.rs, bluetooth.rs).

use std::collections::HashMap;
use std::time::{Duration, Instant};

use iced::keyboard as keys;
use iced::widget::{Column, Space, column, container, responsive, row, scrollable, text};
use iced::{Element, Length, Subscription, Task, Theme};

use crate::about;
use crate::audio;
use crate::bluetooth;
use crate::calendar;
use crate::controls;
use crate::defaultapps;
use crate::gaming;
use crate::hiddenapps;
use crate::hyprpage;
use crate::idle;
use crate::keyboard;
use crate::mouse;
use crate::network;
use crate::notifapps;
use crate::placement;
use crate::power;
use crate::proton;
use crate::reveal;
use crate::schema::{PANELS, Page, Panel, Section, all_settings};
use crate::services;
use crate::shortcuts;
use crate::sidebar;
use crate::store::{Store, Value};
use crate::style;
use crate::themes;
use crate::ui;
use crate::windows;

/// How often the files are read again, so changes made in the shell show up.
const RELOAD_EVERY: Duration = Duration::from_secs(1);
/// How often the open Network or Bluetooth page asks the system again.
/// How far Page Up / Page Down scroll a panel.
const PAGE_SCROLL: f32 = 400.0;
const SYSTEM_REFRESH_EVERY: Duration = Duration::from_secs(3);
pub const SEARCH_ID: &str = "search";
/// How long a revealed setting stays outlined (cleared on the next reload
/// tick after it).
const HIGHLIGHT_FOR: Duration = Duration::from_secs(2);
const SIDEBAR_WIDTH: f32 = 230.0;
/// Widest a panel's content gets; it is centred in wider windows.
const PAGE_WIDTH: f32 = 760.0;
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
    /// The sidebar entry with the keyboard focus, while the sidebar has it.
    nav_focus: Option<usize>,
    /// The switch tree that is open, by setting file.
    open_list: Option<&'static str>,
    /// Setting a search result pointed at, outlined until the time passes.
    highlight: Option<(&'static str, Instant)>,
    network: network::State,
    bluetooth: bluetooth::State,
    audio: audio::State,
    calendar: calendar::State,
    keyboard: keyboard::State,
    mouse: hyprpage::State,
    placement: placement::State,
    idle: idle::State,
    themes: themes::State,
    shortcuts: shortcuts::State,
    default_apps: defaultapps::State,
    windows: hyprpage::State,
    about: about::State,
    power: power::State,
    notif_apps: notifapps::State,
    hidden_apps: hiddenapps::State,
    gaming: gaming::State,
    gaming_display: hyprpage::State,
    proton: proton::State,
    services: services::State,
    /// Installed font families, loaded once at start for the Font picker.
    fonts: Vec<&'static str>,
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
    /// Tab: the next control in the panel. Shift+Tab: back to the sidebar.
    FocusNext,
    FocusPrevious,
    /// Up / Down while the sidebar has the focus.
    NavStep(i32),
    /// Enter on a sidebar entry: open the panel, focus its first control.
    EnterPanel(usize),
    /// Open or close a switch tree, by setting file.
    ToggleList(&'static str),
    /// A pick from a search picker that opened under its row: set it and
    /// close the picker.
    Pick(&'static str, Value),
    /// Every few seconds on a page that polls (`Page::polls`).
    Tick,
    /// Alt+Down / Alt+Up: the next or previous panel.
    PanelStep(i32),
    /// Page Down / Page Up (pages) and Home / End (true: the top).
    ScrollPage(f32),
    ScrollEdge(bool),
    /// Add the typed text to a list setting (pills).
    AddPill(&'static str),
    /// Remove one item of a list setting.
    RemovePill(&'static str, usize),
    /// Open a folder chooser for a folder setting.
    Browse(&'static str),
    /// The chooser's answer; None when it was cancelled.
    Browsed(&'static str, Option<String>),
    /// Put a setting (every file of it) back to its default.
    Reset(&'static str),
    /// A search result: open the panel, scroll to the setting, outline it.
    Reveal(usize, &'static str),
    Reload,
    Network(network::Msg),
    Bluetooth(bluetooth::Msg),
    Audio(audio::Msg),
    Calendar(calendar::Msg),
    Keyboard(keyboard::Msg),
    Mouse(hyprpage::Msg),
    Placement(placement::Msg),
    Idle(idle::Msg),
    Themes(themes::Msg),
    Shortcuts(shortcuts::Msg),
    DefaultApps(defaultapps::Msg),
    Windows(hyprpage::Msg),
    About(about::Msg),
    Power(power::Msg),
    NotifApps(notifapps::Msg),
    HiddenApps(hiddenapps::Msg),
    Gaming(gaming::Msg),
    GamingDisplay(hyprpage::Msg),
    Proton(proton::Msg),
    Services(services::Msg),
    Fonts(Vec<&'static str>),
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
            nav_focus: None,
            open_list: None,
            highlight: None,
            network: network::State::default(),
            bluetooth: bluetooth::State::default(),
            audio: audio::State::default(),
            calendar: calendar::State::default(),
            keyboard: keyboard::State::default(),
            mouse: hyprpage::State::default(),
            placement: placement::State::default(),
            idle: idle::State::default(),
            themes: themes::State::default(),
            shortcuts: shortcuts::State::default(),
            default_apps: defaultapps::State::default(),
            windows: hyprpage::State::default(),
            about: about::State::default(),
            power: power::State::default(),
            notif_apps: notifapps::State::default(),
            hidden_apps: hiddenapps::State::default(),
            gaming: gaming::State::default(),
            gaming_display: hyprpage::State::default(),
            proton: proton::State::default(),
            services: services::State::default(),
            fonts: Vec::new(),
            error: None,
        };
        app.reload();
        let fonts = Task::perform(crate::system::spawn(crate::fonts::load), |f| {
            Message::Fonts(f.unwrap_or_default())
        });
        let task = Task::batch([app.refresh_page(), fonts]);
        (app, task)
    }

    /// Ask the system again, when the open panel shows system state.
    fn refresh_page(&mut self) -> Task<Message> {
        match PANELS[self.panel].page {
            Page::Settings => Task::none(),
            Page::Services => self.services.update(services::Msg::Refresh).map(Message::Services),
            Page::Gaming => Task::batch([
                self.gaming.update(gaming::Msg::Refresh).map(Message::Gaming),
                self.gaming_display
                    .update(hyprpage::Msg::Load, gaming::DISPLAY)
                    .map(Message::GamingDisplay),
                self.proton.update(proton::Msg::Load).map(Message::Proton),
            ]),
            Page::Launcher => self.hidden_apps.update(hiddenapps::Msg::Load).map(Message::HiddenApps),
            Page::Notifications => {
                self.notif_apps.update(notifapps::Msg::Load);
                Task::none()
            }
            Page::Network => self.network.update(network::Msg::Refresh).map(Message::Network),
            Page::Bluetooth => self.bluetooth.update(bluetooth::Msg::Refresh).map(Message::Bluetooth),
            Page::Sound => self.audio.update(audio::Msg::Refresh).map(Message::Audio),
            Page::Calendar => {
                self.calendar.update(calendar::Msg::Refresh);
                Task::none()
            }
            Page::Keyboard => self.keyboard.update(keyboard::Msg::Load).map(Message::Keyboard),
            Page::Mouse => self
                .mouse
                .update(hyprpage::Msg::Load, mouse::SECTIONS)
                .map(Message::Mouse),
            Page::BarItems => self.placement.update(placement::Msg::Refresh).map(Message::Placement),
            Page::Lock => self.idle.update(idle::Msg::Load).map(Message::Idle),
            Page::Themes => self.themes.update(themes::Msg::Load).map(Message::Themes),
            Page::Shortcuts => self.shortcuts.update(shortcuts::Msg::Load).map(Message::Shortcuts),
            Page::DefaultApps => self
                .default_apps
                .update(defaultapps::Msg::Load)
                .map(Message::DefaultApps),
            Page::Windows => self
                .windows
                .update(hyprpage::Msg::Load, windows::SECTIONS)
                .map(Message::Windows),
            Page::About => self.about.update(about::Msg::Load).map(Message::About),
            Page::Power => self.power.update(power::Msg::Refresh).map(Message::Power),
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
                // Runs on; the window does not wait for it.
                drop(crate::system::after_write(file));
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
                keys::Key::Named(keys::key::Named::Tab) if modifiers.shift() => Some(Message::FocusPrevious),
                keys::Key::Named(keys::key::Named::Tab) => Some(Message::FocusNext),
                keys::Key::Named(keys::key::Named::ArrowDown) if modifiers.alt() => Some(Message::PanelStep(1)),
                keys::Key::Named(keys::key::Named::ArrowUp) if modifiers.alt() => Some(Message::PanelStep(-1)),
                keys::Key::Named(keys::key::Named::ArrowDown) if modifiers.is_empty() => Some(Message::NavStep(1)),
                keys::Key::Named(keys::key::Named::ArrowUp) if modifiers.is_empty() => Some(Message::NavStep(-1)),
                keys::Key::Named(keys::key::Named::PageDown) => Some(Message::ScrollPage(1.0)),
                keys::Key::Named(keys::key::Named::PageUp) => Some(Message::ScrollPage(-1.0)),
                keys::Key::Named(keys::key::Named::Home) => Some(Message::ScrollEdge(true)),
                keys::Key::Named(keys::key::Named::End) => Some(Message::ScrollEdge(false)),
                _ => None,
            },
            _ => None,
        });
        let mut subscriptions = vec![iced::time::every(RELOAD_EVERY).map(|_| Message::Reload), keys];
        if PANELS[self.panel].page.polls() {
            subscriptions.push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Tick));
        }
        Subscription::batch(subscriptions)
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectPanel(i) => {
                self.panel = i;
                self.nav_focus = None;
                self.open_list = None;
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
            Message::Mouse(msg) => return self.mouse.update(msg, mouse::SECTIONS).map(Message::Mouse),
            Message::Placement(msg) => return self.placement.update(msg).map(Message::Placement),
            Message::Idle(msg) => return self.idle.update(msg).map(Message::Idle),
            Message::Themes(msg) => return self.themes.update(msg).map(Message::Themes),
            Message::Shortcuts(msg) => return self.shortcuts.update(msg).map(Message::Shortcuts),
            Message::DefaultApps(msg) => return self.default_apps.update(msg).map(Message::DefaultApps),
            Message::Windows(msg) => return self.windows.update(msg, windows::SECTIONS).map(Message::Windows),
            Message::About(msg) => return self.about.update(msg).map(Message::About),
            Message::Power(msg) => return self.power.update(msg).map(Message::Power),
            Message::NotifApps(msg) => self.notif_apps.update(msg),
            Message::HiddenApps(msg) => return self.hidden_apps.update(msg).map(Message::HiddenApps),
            Message::Gaming(gaming::Msg::OpenBluetooth) => {
                if let Some(i) = crate::schema::panel_index("bluetooth") {
                    return self.update(Message::SelectPanel(i));
                }
            }
            Message::Gaming(msg) => return self.gaming.update(msg).map(Message::Gaming),
            Message::Services(msg) => return self.services.update(msg).map(Message::Services),
            Message::Proton(msg) => return self.proton.update(msg).map(Message::Proton),
            Message::GamingDisplay(msg) => {
                return self
                    .gaming_display
                    .update(msg, gaming::DISPLAY)
                    .map(Message::GamingDisplay);
            }
            Message::Search(query) => {
                self.query = query;
                self.searching = true;
            }
            Message::FocusSearch => {
                self.searching = true;
                return iced::widget::operation::focus(SEARCH_ID);
            }
            Message::FocusNext => {
                self.nav_focus = None;
                return crate::focus::next(PANELS[self.panel].id);
            }
            Message::FocusPrevious => {
                self.nav_focus = Some(self.panel);
                return crate::focus::focus_id(crate::focus::nav_id(PANELS[self.panel].id));
            }
            Message::NavStep(step) => {
                if let Some(i) = self.nav_focus {
                    let next = (i as i32 + step).rem_euclid(PANELS.len() as i32) as usize;
                    self.nav_focus = Some(next);
                    return crate::focus::focus_id(crate::focus::nav_id(PANELS[next].id));
                }
            }
            Message::Tick => return self.refresh_page(),
            Message::Pick(file, value) => {
                self.open_list = None;
                return self.update(Message::Set(file, value));
            }
            Message::ToggleList(file) => {
                self.open_list = if self.open_list == Some(file) { None } else { Some(file) };
            }
            Message::EnterPanel(i) => {
                let open = self.update(Message::SelectPanel(i));
                return open.chain(crate::focus::first(PANELS[i].id));
            }
            Message::PanelStep(step) => {
                let count = PANELS.len() as i32;
                let next = (self.panel as i32 + step).rem_euclid(count) as usize;
                return self.update(Message::SelectPanel(next));
            }
            Message::ScrollPage(pages) => {
                let offset = iced::widget::scrollable::AbsoluteOffset {
                    x: 0.0,
                    y: pages * PAGE_SCROLL,
                };
                return iced::widget::operation::scroll_by(PANELS[self.panel].id, offset);
            }
            Message::ScrollEdge(top) => {
                let y = if top { 0.0 } else { 1.0 };
                return iced::widget::operation::snap_to(
                    PANELS[self.panel].id,
                    iced::widget::scrollable::RelativeOffset { x: None, y: Some(y) },
                );
            }
            Message::ClearSearch => {
                if self.network.dialog().is_some() {
                    return self.update(Message::Network(network::Msg::HiddenDialog(false)));
                }
                self.query.clear();
                self.searching = false;
            }
            Message::Set(file, value) => {
                // A pick from a search picker ends its search.
                self.drafts.remove(file);
                self.write(file, value);
            }
            Message::Fonts(fonts) => self.fonts = fonts,
            Message::Browse(file) => {
                let start = match self.values.get(file) {
                    Some(Value::Text(t)) => format!("{}/", t.trim_end_matches('/')),
                    _ => String::new(),
                };
                let args = vec![
                    "--file-selection".into(),
                    "--directory".into(),
                    "--title=Choose a folder".into(),
                    format!("--filename={start}"),
                ];
                // zenity exits 1 when cancelled: nothing to change then.
                return Task::perform(crate::system::run("zenity", args, None), move |r| {
                    Message::Browsed(file, r.ok().map(|p| p.trim().to_string()).filter(|p| !p.is_empty()))
                });
            }
            Message::Browsed(file, Some(path)) => {
                self.drafts.remove(file);
                self.write(file, Value::Text(path));
            }
            Message::Browsed(_, None) => {}
            Message::AddPill(file) => {
                let typed = self.drafts.remove(file).unwrap_or_default();
                let item = typed.trim();
                if let (false, Some(Value::Json(list))) = (item.is_empty(), self.values.get(file)) {
                    let mut items = list.as_array().cloned().unwrap_or_default();
                    if !items.iter().any(|v| v.as_str() == Some(item)) {
                        items.push(serde_json::Value::String(item.to_string()));
                    }
                    self.write(file, Value::Json(serde_json::Value::Array(items)));
                }
            }
            Message::RemovePill(file, index) => {
                if let Some(Value::Json(list)) = self.values.get(file) {
                    let mut items = list.as_array().cloned().unwrap_or_default();
                    if index < items.len() {
                        items.remove(index);
                    }
                    self.write(file, Value::Json(serde_json::Value::Array(items)));
                }
            }
            Message::Reset(file) => {
                if let Some(setting) = all_settings().find(|s| s.file == file) {
                    for (file, _, default) in setting.files() {
                        self.drafts.remove(file);
                        self.write(file, default);
                    }
                }
            }
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
            let base: Element<'_, Message> = row![
                sidebar::view(self.panel, &self.query, layout),
                divider,
                self.panel_view(&PANELS[self.panel], layout)
            ]
            .into();
            // A panel's dialog covers the whole window.
            match (PANELS[self.panel].page, self.network.dialog()) {
                (Page::Network, Some(dialog)) => ui::modal(
                    base,
                    dialog.map(Message::Network),
                    Message::Network(network::Msg::HiddenDialog(false)),
                ),
                _ => base,
            }
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
            Page::Services => {
                let mut body = page_column(panel.title, layout);
                body = ui::section(body, "At login", services_rows(self.services.daemon_rows()));
                body = ui::section(body, "Scheduled", services_rows(self.services.scheduled_rows()));
                body = ui::section(body, "On demand", services_rows(self.services.on_demand_rows()));
                body.into()
            }
            Page::Gaming => {
                let mut body = page_column(panel.title, layout);
                let switch = self.gaming.rows().into_iter().map(|r| r.map(Message::Gaming)).collect();
                body = ui::section(body, "Game mode", switch);
                let pads = self
                    .gaming
                    .controller_rows()
                    .into_iter()
                    .map(|r| r.map(Message::Gaming))
                    .collect();
                body = ui::section(body, "Controllers", pads);
                // Not everyone has Steam: no section without it.
                if self.proton.has_steam() {
                    let proton = self.proton.rows().into_iter().map(|r| r.map(Message::Proton)).collect();
                    body = ui::section(body, "Steam", proton);
                }
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                let display = Element::from(self.gaming_display.view(Column::new().spacing(10), gaming::DISPLAY))
                    .map(Message::GamingDisplay);
                body.push(display).into()
            }
            Page::Launcher => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                let hidden = self
                    .hidden_apps
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::HiddenApps))
                    .collect();
                body = ui::section(body, "Hidden apps", hidden);
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Notifications => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                let apps = self
                    .notif_apps
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::NotifApps))
                    .collect();
                body = ui::section(body, "Apps", apps);
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
                self.with_settings(feeds, panel, layout)
            }
            Page::Keyboard => {
                Element::from(self.keyboard.view(page_column(panel.title, layout))).map(Message::Keyboard)
            }
            Page::Mouse => {
                Element::from(self.mouse.view(page_column(panel.title, layout), mouse::SECTIONS)).map(Message::Mouse)
            }
            Page::BarItems => {
                Element::from(self.placement.view(page_column(panel.title, layout))).map(Message::Placement)
            }
            Page::Lock => {
                let times = Element::from(self.idle.view(page_column(panel.title, layout))).map(Message::Idle);
                self.with_settings(times, panel, layout)
            }
            Page::Themes => Element::from(self.themes.view(page_column(panel.title, layout))).map(Message::Themes),
            Page::Shortcuts => {
                Element::from(self.shortcuts.view(page_column(panel.title, layout))).map(Message::Shortcuts)
            }
            Page::DefaultApps => {
                Element::from(self.default_apps.view(page_column(panel.title, layout))).map(Message::DefaultApps)
            }
            Page::Windows => Element::from(self.windows.view(page_column(panel.title, layout), windows::SECTIONS))
                .map(Message::Windows),
            Page::Power => {
                let battery = Element::from(self.power.view(page_column(panel.title, layout))).map(Message::Power);
                self.with_settings(battery, panel, layout)
            }
            Page::About => Element::from(self.about.view(page_column(panel.title, layout))).map(Message::About),
        };
        // One scroll position per panel.
        scrollable(container(content).center_x(Length::Fill))
            .id(panel.id)
            .height(Length::Fill)
            .into()
    }

    /// A page's own part (feeds, idle times) followed by the panel's ordinary
    /// settings sections, at the width of one page column.
    fn with_settings<'a>(
        &'a self,
        top: Element<'a, Message>,
        panel: &'static Panel,
        layout: Layout,
    ) -> Element<'a, Message> {
        let pad = if layout.stacked { 16.0 } else { 28.0 };
        let mut options = Column::new()
            .spacing(10)
            .padding(iced::Padding {
                top: 0.0,
                right: pad,
                bottom: pad,
                left: pad,
            })
            .width(Length::Fill)
            .max_width(PAGE_WIDTH);
        for section in panel.sections {
            options = self.section(options, section, layout);
        }
        column![top, options].width(Length::Fill).max_width(PAGE_WIDTH).into()
    }

    /// A section header and a card of setting rows.
    fn section<'a>(
        &'a self,
        body: Column<'a, Message>,
        section: &'static Section,
        layout: Layout,
    ) -> Column<'a, Message> {
        let shown = |s: &&'static crate::schema::Setting| {
            let switch = crate::schema::SHOWN_WHEN
                .iter()
                .find(|(f, _)| *f == s.file)
                .map(|(_, w)| *w);
            // A search result still shows its row.
            switch.is_none_or(|w| matches!(self.values.get(w), Some(Value::Bool(true))))
                || self.highlight.is_some_and(|(file, _)| file == s.file)
        };
        let rows = section.settings.iter().filter(shown).map(|s| {
            let highlighted = self.highlight.is_some_and(|(file, _)| file == s.file);
            controls::setting_row(
                s,
                &self.values,
                self.drafts.get(s.file),
                &self.fonts,
                layout.stacked,
                highlighted,
                self.open_list,
            )
        });
        ui::section(body, section.title, rows.collect())
    }
}

fn services_rows(rows: Vec<Element<'_, services::Msg>>) -> Vec<Element<'_, Message>> {
    rows.into_iter().map(|r| r.map(Message::Services)).collect()
}

/// A panel's column, starting with its title.
fn page_column<'a, M: 'a>(title: &'static str, layout: Layout) -> Column<'a, M> {
    let (padding, title_size) = if layout.stacked { (16, 20) } else { (28, 24) };
    column![text(title).font(style::FONT_BOLD).size(title_size)]
        .spacing(10)
        .padding(padding)
        .width(Length::Fill)
        .max_width(PAGE_WIDTH)
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
