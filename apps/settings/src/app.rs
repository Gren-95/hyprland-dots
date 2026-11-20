//! The window: the sidebar (sidebar.rs) and the open panel: settings read
//! from and written to the Quickshell settings store, or the Network and
//! Bluetooth pages (network.rs, bluetooth.rs).

use std::collections::HashMap;
use std::time::{Duration, Instant};

use iced::keyboard as keys;
use iced::widget::{Column, Space, column, container, responsive, row, scrollable, text};
use iced::{Element, Length, Subscription, Task, Theme};

use crate::about;
use crate::appearance;
use crate::audio;
use crate::backup;
use crate::bluetooth;
use crate::calendar;
use crate::controls;
use crate::defaultapps;
use crate::displays;
use crate::flatpak;
use crate::gaming;
use crate::hiddenapps;
use crate::hyprpage;
use crate::idle;
use crate::keyboard;
use crate::mouse;
use crate::network;
use crate::notifapps;
use crate::ocr;
use crate::placement;
use crate::power;
use crate::privacy;
use crate::proton;
use crate::region;
use crate::reveal;
use crate::schema::{PANELS, Page, Panel, Section, all_settings};
use crate::services;
use crate::sharing;
use crate::shortcuts;
use crate::sidebar;
use crate::startup;
use crate::store::{Store, Value};
use crate::style;
use crate::sync;
use crate::sysunits;
use crate::themes;
use crate::ui;
use crate::units;
use crate::updates;
use crate::users;
use crate::windowrules;
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
    /// Keyboard shows its key binds page instead of its settings.
    shortcuts_open: bool,
    /// The panel whose Reset asks for confirmation.
    confirm_reset: Option<usize>,
    /// A timed refresh is still running: the next tick waits for it, so a
    /// slow or hung tool cannot pile up reads.
    polling: bool,
    default_apps: defaultapps::State,
    windows: hyprpage::State,
    about: about::State,
    power: power::State,
    notif_apps: notifapps::State,
    ocr: ocr::State,
    region: region::State,
    sync: sync::State,
    window_rules: windowrules::State,
    appearance: appearance::State,
    backup: backup::State,
    sharing: sharing::State,
    flatpak: flatpak::State,
    privacy: privacy::State,
    users: users::State,
    displays: displays::State,
    updates: updates::State,
    hidden_apps: hiddenapps::State,
    gaming: gaming::State,
    gaming_display: hyprpage::State,
    proton: proton::State,
    services: services::State,
    startup: startup::State,
    units: units::State,
    sysunits: sysunits::State,
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
    Browsed(&'static str, Result<Option<String>, String>),
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
    /// Open (true) or leave (false) Keyboard's key binds page.
    ShowShortcuts(bool),
    /// A timed refresh finished.
    Polled,
    /// Reset every setting of a panel: the first press asks, the second
    /// does it.
    ResetPanel(usize),
    /// A saved setting was applied outside the shell, or why not.
    Applied(&'static str, Result<(), String>),
    DefaultApps(defaultapps::Msg),
    Windows(hyprpage::Msg),
    About(about::Msg),
    Power(power::Msg),
    NotifApps(notifapps::Msg),
    HiddenApps(hiddenapps::Msg),
    Ocr(ocr::Msg),
    Region(region::Msg),
    Sync(sync::Msg),
    WindowRules(windowrules::Msg),
    Appearance(appearance::Msg),
    Backup(backup::Msg),
    Sharing(sharing::Msg),
    Flatpak(flatpak::Msg),
    Privacy(privacy::Msg),
    Users(users::Msg),
    Displays(displays::Msg),
    Updates(updates::Msg),
    Gaming(gaming::Msg),
    GamingDisplay(hyprpage::Msg),
    Proton(proton::Msg),
    Services(services::Msg),
    Startup(startup::Msg),
    Units(units::Msg),
    SysUnits(sysunits::Msg),
    Fonts(Vec<&'static str>),
}

impl App {
    /// The app, and the first refresh of its panel when that shows system
    /// state.
    pub fn new(panel: usize, query: String, open_shortcuts: bool, store: Store) -> (Self, Task<Message>) {
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
            shortcuts_open: open_shortcuts,
            polling: false,
            confirm_reset: None,
            default_apps: defaultapps::State::default(),
            windows: hyprpage::State::default(),
            about: about::State::default(),
            power: power::State::default(),
            notif_apps: notifapps::State::default(),
            ocr: ocr::State::default(),
            region: region::State::default(),
            sync: sync::State::default(),
            window_rules: windowrules::State::default(),
            appearance: appearance::State::default(),
            backup: backup::State::default(),
            sharing: sharing::State::default(),
            flatpak: flatpak::State::default(),
            privacy: privacy::State::default(),
            users: users::State::default(),
            displays: displays::State::default(),
            updates: updates::State::default(),
            hidden_apps: hiddenapps::State::default(),
            gaming: gaming::State::default(),
            gaming_display: hyprpage::State::default(),
            proton: proton::State::default(),
            services: services::State::default(),
            startup: startup::State::default(),
            units: units::State::default(),
            sysunits: sysunits::State::default(),
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

    /// The timed refresh of a polling page: only the parts that change on
    /// their own. A part being edited (an idle time slider, the time zone
    /// picker) would be reset by a read.
    fn poll_page(&mut self) -> Task<Message> {
        match PANELS[self.panel].page {
            Page::Power => self.power.update(power::Msg::Refresh).map(Message::Power),
            Page::DateTime => {
                self.calendar.update(calendar::Msg::Refresh);
                Task::none()
            }
            _ => self.refresh_page(),
        }
    }

    /// Ask the system again, when the open panel shows system state.
    fn refresh_page(&mut self) -> Task<Message> {
        match PANELS[self.panel].page {
            Page::Settings | Page::Changed | Page::Privacy => Task::none(),
            Page::Users => self.users.update(users::Msg::Load).map(Message::Users),
            Page::Displays => self.displays.update(displays::Msg::Load).map(Message::Displays),
            Page::Updates => self.updates.update(updates::Msg::Load).map(Message::Updates),
            Page::Services => Task::batch([
                self.services.update(services::Msg::Refresh).map(Message::Services),
                self.units.update(units::Msg::Load).map(Message::Units),
                self.startup.update(startup::Msg::Load).map(Message::Startup),
                self.sysunits.update(sysunits::Msg::Load).map(Message::SysUnits),
            ]),
            Page::Gaming => Task::batch([
                self.gaming.update(gaming::Msg::Refresh).map(Message::Gaming),
                self.gaming_display
                    .update(hyprpage::Msg::Load, gaming::DISPLAY)
                    .map(Message::GamingDisplay),
                self.proton.update(proton::Msg::Load).map(Message::Proton),
            ]),
            Page::Launcher => self.hidden_apps.update(hiddenapps::Msg::Load).map(Message::HiddenApps),
            Page::Recording => self.ocr.update(ocr::Msg::Load).map(Message::Ocr),
            Page::Sync => Task::batch([
                self.services.update(services::Msg::Refresh).map(Message::Services),
                self.sync.update(sync::Msg::Load).map(Message::Sync),
            ]),
            Page::Sharing => self.sharing.update(sharing::Msg::Refresh).map(Message::Sharing),
            Page::Flatpak => self.flatpak.update(flatpak::Msg::Load).map(Message::Flatpak),
            Page::Notifications => {
                self.notif_apps.update(notifapps::Msg::Load);
                Task::none()
            }
            Page::Network => self.network.update(network::Msg::Refresh).map(Message::Network),
            Page::Bluetooth => self.bluetooth.update(bluetooth::Msg::Refresh).map(Message::Bluetooth),
            Page::Sound => self.audio.update(audio::Msg::Refresh).map(Message::Audio),
            Page::DateTime => {
                self.calendar.update(calendar::Msg::Refresh);
                self.region.update(region::Msg::Load).map(Message::Region)
            }
            Page::Keyboard if self.shortcuts_open => {
                self.shortcuts.update(shortcuts::Msg::Load).map(Message::Shortcuts)
            }
            Page::Keyboard => self.keyboard.update(keyboard::Msg::Load).map(Message::Keyboard),
            Page::Mouse => self
                .mouse
                .update(hyprpage::Msg::Load, mouse::SECTIONS)
                .map(Message::Mouse),
            Page::Bar => self.placement.update(placement::Msg::Refresh).map(Message::Placement),
            Page::Appearance => Task::batch([
                self.themes.update(themes::Msg::Load).map(Message::Themes),
                self.appearance.update(appearance::Msg::Load).map(Message::Appearance),
            ]),
            Page::DefaultApps => self
                .default_apps
                .update(defaultapps::Msg::Load)
                .map(Message::DefaultApps),
            Page::Windows => Task::batch([
                self.windows
                    .update(hyprpage::Msg::Load, windows::SECTIONS)
                    .map(Message::Windows),
                self.window_rules
                    .update(windowrules::Msg::Load)
                    .map(Message::WindowRules),
            ]),
            Page::About => self.about.update(about::Msg::Load).map(Message::About),
            Page::Power => Task::batch([
                self.power.update(power::Msg::Refresh).map(Message::Power),
                self.idle.update(idle::Msg::Load).map(Message::Idle),
            ]),
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

    /// Save a setting; the returned task applies it outside the shell
    /// where needed (Hyprland, GTK, a script) and reports a failure.
    fn write(&mut self, file: &'static str, value: Value) -> Task<Message> {
        match self.store.write(file, &value) {
            Ok(()) => {
                self.values.insert(file, value);
                self.error = None;
                let work = crate::system::after_write(file);
                if work.is_empty() {
                    return Task::none();
                }
                Task::perform(
                    crate::system::spawn(move || crate::system::after_write_result(work)),
                    move |r| Message::Applied(file, r.unwrap_or_else(|| Err("stopped unexpectedly".into()))),
                )
            }
            Err(e) => {
                self.error = Some(format!("Could not save {file}: {e}"));
                Task::none()
            }
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
        // A display change counts down to its undo, panel open or not.
        if self.displays.counting() {
            subscriptions
                .push(iced::time::every(Duration::from_secs(1)).map(|_| Message::Displays(displays::Msg::Second)));
        }
        if PANELS[self.panel].page.polls() {
            subscriptions.push(iced::time::every(SYSTEM_REFRESH_EVERY).map(|_| Message::Tick));
        }
        Subscription::batch(subscriptions)
    }

    pub fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::SelectPanel(i) => {
                self.panel = i;
                self.confirm_reset = None;
                self.shortcuts_open = false;
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
            Message::ShowShortcuts(open) => {
                self.shortcuts_open = open;
                return self.refresh_page().chain(iced::widget::operation::snap_to(
                    PANELS[self.panel].id,
                    iced::widget::scrollable::RelativeOffset::START,
                ));
            }
            Message::DefaultApps(msg) => return self.default_apps.update(msg).map(Message::DefaultApps),
            Message::Windows(msg) => return self.windows.update(msg, windows::SECTIONS).map(Message::Windows),
            Message::About(msg) => return self.about.update(msg).map(Message::About),
            Message::Power(msg) => return self.power.update(msg).map(Message::Power),
            Message::NotifApps(msg) => self.notif_apps.update(msg),
            Message::HiddenApps(msg) => return self.hidden_apps.update(msg).map(Message::HiddenApps),
            Message::Ocr(msg) => return self.ocr.update(msg).map(Message::Ocr),
            Message::Region(msg) => return self.region.update(msg).map(Message::Region),
            Message::Sync(msg) => return self.sync.update(msg).map(Message::Sync),
            Message::WindowRules(msg) => return self.window_rules.update(msg).map(Message::WindowRules),
            Message::Appearance(msg) => return self.appearance.update(msg).map(Message::Appearance),
            Message::Backup(msg) => {
                // An import changed the store: show its values.
                if matches!(msg, backup::Msg::Applied(Ok(()))) {
                    self.reload();
                }
                return self.backup.update(msg).map(Message::Backup);
            }
            Message::Sharing(sharing::Msg::OpenNetwork) => {
                if let Some(i) = crate::schema::panel_index("network") {
                    return self.update(Message::SelectPanel(i));
                }
            }
            Message::Sharing(msg) => return self.sharing.update(msg).map(Message::Sharing),
            Message::Flatpak(msg) => return self.flatpak.update(msg).map(Message::Flatpak),
            Message::Privacy(msg) => return self.privacy.update(msg).map(Message::Privacy),
            Message::Users(msg) => return self.users.update(msg).map(Message::Users),
            Message::Displays(msg) => return self.displays.update(msg).map(Message::Displays),
            Message::Updates(msg) => return self.updates.update(msg).map(Message::Updates),
            Message::Gaming(gaming::Msg::OpenBluetooth) => {
                if let Some(i) = crate::schema::panel_index("bluetooth") {
                    return self.update(Message::SelectPanel(i));
                }
            }
            Message::Gaming(msg) => return self.gaming.update(msg).map(Message::Gaming),
            Message::Services(msg) => return self.services.update(msg).map(Message::Services),
            Message::Startup(msg) => return self.startup.update(msg).map(Message::Startup),
            Message::Units(msg) => return self.units.update(msg).map(Message::Units),
            Message::SysUnits(msg) => return self.sysunits.update(msg).map(Message::SysUnits),
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
            Message::Tick if self.polling => {}
            Message::Tick => {
                self.polling = true;
                return self.poll_page().chain(Task::done(Message::Polled));
            }
            Message::Polled => self.polling = false,
            Message::ResetPanel(i) if self.confirm_reset != Some(i) => self.confirm_reset = Some(i),
            Message::ResetPanel(i) => {
                self.confirm_reset = None;
                let mut tasks = Vec::new();
                for setting in PANELS[i].sections.iter().flat_map(|s| s.settings.iter()) {
                    for (file, _, default) in setting.files() {
                        self.drafts.remove(file);
                        tasks.push(self.write(file, default));
                    }
                }
                return Task::batch(tasks);
            }
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
                return self.write(file, value);
            }
            Message::Applied(_, Ok(())) => {}
            Message::Applied(file, Err(e)) => {
                self.error = Some(format!("Saved {file}, but could not apply it now: {e}"));
            }
            Message::Fonts(fonts) => self.fonts = fonts,
            Message::Browse(file) => {
                let picture = all_settings().any(|s| {
                    s.file == file && matches!(s.control, crate::schema::Control::Folder { picture: true, .. })
                });
                let current = match self.values.get(file) {
                    Some(Value::Text(t)) => t.clone(),
                    _ => String::new(),
                };
                let args = if picture {
                    vec![
                        "--file-selection".into(),
                        "--title=Choose a picture".into(),
                        "--file-filter=Pictures | *.jpg *.jpeg *.png *.webp".into(),
                        format!("--filename={current}"),
                    ]
                } else {
                    vec![
                        "--file-selection".into(),
                        "--directory".into(),
                        "--title=Choose a folder".into(),
                        format!("--filename={}/", current.trim_end_matches('/')),
                    ]
                };
                return Task::perform(crate::system::pick(args), move |r| Message::Browsed(file, r));
            }
            Message::Browsed(file, Ok(Some(path))) => {
                self.drafts.remove(file);
                return self.write(file, Value::Text(path));
            }
            Message::Browsed(_, Ok(None)) => {}
            Message::Browsed(_, Err(e)) => self.error = Some(e),
            Message::AddPill(file) => {
                let typed = self.drafts.remove(file).unwrap_or_default();
                let item = typed.trim();
                if let (false, Some(Value::Json(list))) = (item.is_empty(), self.values.get(file)) {
                    let mut items = list.as_array().cloned().unwrap_or_default();
                    if !items.iter().any(|v| v.as_str() == Some(item)) {
                        items.push(serde_json::Value::String(item.to_string()));
                    }
                    return self.write(file, Value::Json(serde_json::Value::Array(items)));
                }
            }
            Message::RemovePill(file, index) => {
                if let Some(Value::Json(list)) = self.values.get(file) {
                    let mut items = list.as_array().cloned().unwrap_or_default();
                    if index < items.len() {
                        items.remove(index);
                    }
                    return self.write(file, Value::Json(serde_json::Value::Array(items)));
                }
            }
            Message::Reset(file) => {
                if let Some(setting) = all_settings().find(|s| s.file == file) {
                    let mut tasks = Vec::new();
                    for (file, _, default) in setting.files() {
                        self.drafts.remove(file);
                        tasks.push(self.write(file, default));
                    }
                    return Task::batch(tasks);
                }
            }
            Message::Preview(file, value) => {
                self.dragging = Some(file);
                self.values.insert(file, value);
            }
            Message::Commit(file) => {
                self.dragging = None;
                if let Some(value) = self.values.get(file).cloned() {
                    return self.write(file, value);
                }
            }
            Message::Draft(file, draft) => {
                self.drafts.insert(file, draft);
            }
            Message::Submit(file) => {
                if let Some(draft) = self.drafts.remove(file) {
                    return self.write(file, Value::Text(draft.trim().to_string()));
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
                let startup = self
                    .startup
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::Startup))
                    .collect();
                body = ui::section(body, "Apps at login", startup);
                let mut background: Vec<Element<'_, Message>> = self
                    .units
                    .own_rows()
                    .into_iter()
                    .map(|r| r.map(Message::Units))
                    .collect();
                background.extend(services_rows(self.services.daemon_rows()));
                body = ui::section(body, "Background services", background);
                body = ui::section(body, "On demand", services_rows(self.services.on_demand_rows()));
                let mut system: Vec<Element<'_, Message>> = self
                    .sysunits
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::SysUnits))
                    .collect();
                system.extend(self.units.system_rows().into_iter().map(|r| r.map(Message::Units)));
                body = ui::section(body, "System services", system);
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
            Page::DateTime => {
                let mut body = page_column(panel.title, layout);
                let time = self
                    .region
                    .time_rows()
                    .into_iter()
                    .map(|r| r.map(Message::Region))
                    .collect();
                body = ui::section(body, "Time", time);
                let current = match self.values.get("clock-date-format") {
                    Some(Value::Text(t)) => t.as_str(),
                    _ => "ddd, dd MMM",
                };
                for section in panel.sections {
                    let extra = match section.title {
                        "Date" => vec![self.region.date_row(current)],
                        // The feeds, then how often they download.
                        "Calendar" => self
                            .calendar
                            .rows()
                            .into_iter()
                            .map(|r| r.map(Message::Calendar))
                            .collect(),
                        _ => Vec::new(),
                    };
                    body = self.section_with(body, section, layout, extra);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Sync => {
                let mut body = page_column(panel.title, layout);
                body = ui::section(body, "Syncs", services_rows(self.services.scheduled_rows()));
                for section in panel.sections {
                    let extra: Vec<Element<'_, sync::Msg>> = match section.title {
                        "Immich" => self.sync.immich_rows(),
                        _ => self.sync.jellyfin_rows(),
                    };
                    let extra = extra.into_iter().map(|r| r.map(Message::Sync)).collect();
                    body = self.section_with(body, section, layout, extra);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Updates => {
                let mut body = page_column(panel.title, layout);
                let run = self
                    .updates
                    .update_rows()
                    .into_iter()
                    .map(|r| r.map(Message::Updates))
                    .collect();
                body = ui::section(body, "System", run);
                let snaps = self
                    .updates
                    .snapshot_rows()
                    .into_iter()
                    .map(|r| r.map(Message::Updates))
                    .collect();
                ui::section(body, "Snapshots", snaps).into()
            }
            Page::Displays => {
                let mut body = page_column(panel.title, layout);
                let rows = self
                    .displays
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::Displays))
                    .collect();
                body = ui::section(body, "Monitors", rows);
                for section in panel.sections {
                    let extra = if section.title == "Night light" {
                        self.displays
                            .night_rows()
                            .into_iter()
                            .map(|r| r.map(Message::Displays))
                            .collect()
                    } else {
                        Vec::new()
                    };
                    body = self.section_with(body, section, layout, extra);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Users => {
                let body = page_column(panel.title, layout);
                let rows = self.users.rows().into_iter().map(|r| r.map(Message::Users)).collect();
                ui::section(body, "You", rows).into()
            }
            Page::Privacy => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    let extra = if section.title == "Clipboard" {
                        self.privacy
                            .rows()
                            .into_iter()
                            .map(|r| r.map(Message::Privacy))
                            .collect()
                    } else {
                        Vec::new()
                    };
                    body = self.section_with(body, section, layout, extra);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::Changed => {
                let body = page_column(panel.title, layout);
                let list = crate::changed::changed(&self.values);
                let rows: Vec<Element<'_, Message>> = if list.is_empty() {
                    vec![ui::note("Every setting is at its default")]
                } else {
                    list.into_iter()
                        .map(|(i, s)| {
                            ui::item(
                                PANELS[i].glyph,
                                s.label.into(),
                                format!("{} · {}", PANELS[i].title, crate::changed::shown(s, &self.values)),
                                vec![
                                    ui::icon_action(
                                        lucide_iced::bytes::ARROW_UP_RIGHT,
                                        "Show it",
                                        Some(Message::Reveal(i, s.file)),
                                        style::Action::Normal,
                                    ),
                                    ui::icon_action(
                                        lucide_iced::bytes::ROTATE_CCW,
                                        "Reset to default",
                                        Some(Message::Reset(s.file)),
                                        style::Action::Normal,
                                    ),
                                ],
                            )
                        })
                        .collect()
                };
                ui::section(body, "Not at their default", rows).into()
            }
            Page::Flatpak => {
                let body = page_column(panel.title, layout);
                let rows = self
                    .flatpak
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::Flatpak))
                    .collect();
                ui::section(body, "Flatpak apps", rows).into()
            }
            Page::Sharing => {
                let mut body = page_column(panel.title, layout);
                body = ui::section(body, "Screen", sharing_rows(self.sharing.screen_rows()));
                body = ui::section(body, "Remote login", sharing_rows(self.sharing.login_rows()));
                let tailnet = sharing_rows(self.sharing.tailnet_rows());
                if !tailnet.is_empty() {
                    body = ui::section(body, "Tailnet", tailnet);
                }
                body.into()
            }
            Page::Recording => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                let ocr = self.ocr.rows().into_iter().map(|r| r.map(Message::Ocr)).collect();
                body = ui::section(body, "Text recognition", ocr);
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
                let devices =
                    Element::from(self.audio.view(page_column(panel.title, layout), max_volume)).map(Message::Audio);
                self.with_settings(devices, panel, layout)
            }
            Page::Keyboard if self.shortcuts_open => {
                let pad = if layout.stacked { 16.0 } else { 28.0 };
                let back = ui::action("‹ Keyboard", Some(Message::ShowShortcuts(false)), style::Action::Normal);
                let binds = Element::from(self.shortcuts.view(page_column("Keyboard shortcuts", layout)))
                    .map(Message::Shortcuts);
                column![container(back).padding(iced::Padding::from([0.0, pad]).top(pad)), binds]
                    .width(Length::Fill)
                    .max_width(PAGE_WIDTH)
                    .into()
            }
            Page::Keyboard => {
                let keys = Element::from(self.keyboard.view(page_column(panel.title, layout))).map(Message::Keyboard);
                let open = ui::item(
                    lucide_iced::bytes::COMMAND,
                    "Keyboard shortcuts".into(),
                    "Search, run and change the key binds · Super+F1".into(),
                    vec![ui::icon_action(
                        lucide_iced::bytes::ARROW_UP_RIGHT,
                        "Open keyboard shortcuts",
                        Some(Message::ShowShortcuts(true)),
                        style::Action::Normal,
                    )],
                );
                let rest = ui::section(tail_column(layout), "Shortcuts", vec![open]);
                column![keys, rest].width(Length::Fill).max_width(PAGE_WIDTH).into()
            }
            Page::Mouse => {
                Element::from(self.mouse.view(page_column(panel.title, layout), mouse::SECTIONS)).map(Message::Mouse)
            }
            Page::Bar => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    body = self.section(body, section, layout);
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                let items = Element::from(self.placement.view(tail_column(layout))).map(Message::Placement);
                column![body, items].width(Length::Fill).max_width(PAGE_WIDTH).into()
            }
            Page::Appearance => {
                let mut body = page_column(panel.title, layout);
                for section in panel.sections {
                    if section.title == "Wallpaper" {
                        let picker = self
                            .appearance
                            .wallpaper_rows()
                            .into_iter()
                            .map(|r| r.map(Message::Appearance))
                            .collect();
                        body = self.section_with(body, section, layout, picker);
                        continue;
                    }
                    body = self.section(body, section, layout);
                    // The theme rows (not store settings) follow Colour.
                    if section.title == "Colour" {
                        let mut themes: Vec<Element<'_, Message>> = self
                            .appearance
                            .style_rows()
                            .into_iter()
                            .map(|r| r.map(Message::Appearance))
                            .collect();
                        themes.extend(self.themes.rows_all().into_iter().map(|r| r.map(Message::Themes)));
                        body = ui::section(body, "Themes", themes);
                    }
                }
                if let Some(error) = &self.error {
                    body = body.push(text(error).color(style::RED));
                }
                body.into()
            }
            Page::DefaultApps => {
                Element::from(self.default_apps.view(page_column(panel.title, layout))).map(Message::DefaultApps)
            }
            Page::Windows => {
                let look = Element::from(self.windows.view(page_column(panel.title, layout), windows::SECTIONS))
                    .map(Message::Windows);
                let rules = self
                    .window_rules
                    .rows()
                    .into_iter()
                    .map(|r| r.map(Message::WindowRules))
                    .collect();
                let mut rest = tail_column(layout);
                for section in panel.sections {
                    rest = self.section(rest, section, layout);
                }
                if let Some(error) = &self.error {
                    rest = rest.push(text(error).color(style::RED));
                }
                let rest = ui::section(rest, "Window rules", rules);
                column![look, rest].width(Length::Fill).max_width(PAGE_WIDTH).into()
            }
            Page::Power => {
                let battery = Element::from(self.power.view(page_column(panel.title, layout))).map(Message::Power);
                // Power sections, the idle times, then the lock sections.
                let split = panel
                    .sections
                    .iter()
                    .position(|s| s.title == "Stay awake")
                    .unwrap_or(panel.sections.len());
                let mut power = tail_column(layout);
                for section in &panel.sections[..split] {
                    power = self.section(power, section, layout);
                }
                let times = Element::from(self.idle.view(tail_column(layout))).map(Message::Idle);
                let mut lock = tail_column(layout);
                for section in &panel.sections[split..] {
                    lock = self.section(lock, section, layout);
                }
                if let Some(error) = &self.error {
                    lock = lock.push(text(error).color(style::RED));
                }
                column![battery, power, times, lock]
                    .width(Length::Fill)
                    .max_width(PAGE_WIDTH)
                    .into()
            }
            Page::About => {
                let about = Element::from(self.about.view(page_column(panel.title, layout))).map(Message::About);
                let rows = self.backup.rows().into_iter().map(|r| r.map(Message::Backup)).collect();
                let pad = if layout.stacked { 16.0 } else { 28.0 };
                let backup = Column::new()
                    .spacing(10)
                    .padding(iced::Padding {
                        top: 0.0,
                        right: pad,
                        bottom: pad,
                        left: pad,
                    })
                    .width(Length::Fill)
                    .max_width(PAGE_WIDTH);
                let backup = ui::section(backup, "Backup", rows);
                column![about, backup].width(Length::Fill).max_width(PAGE_WIDTH).into()
            }
        };
        // Panels with store settings end with a reset for all of them.
        let content = if !panel.sections.is_empty() && crate::changed::panel_changed(panel, &self.values) {
            let i = self.panel;
            let asking = self.confirm_reset == Some(i);
            let row = ui::item(
                lucide_iced::bytes::ROTATE_CCW,
                "Reset this panel".into(),
                if asking {
                    "All settings here back to default".into()
                } else {
                    "All settings here back to default".into()
                },
                vec![ui::confirm_action(
                    lucide_iced::bytes::ROTATE_CCW,
                    "Reset this panel",
                    asking,
                    Some(Message::ResetPanel(i)),
                )],
            );
            column![content, ui::section(tail_column(layout), "Defaults", vec![row])]
                .width(Length::Fill)
                .max_width(PAGE_WIDTH)
                .into()
        } else {
            content
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
        let mut options = tail_column(layout);
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
        self.section_with(body, section, layout, Vec::new())
    }

    /// A section of store settings followed by `extra` rows that belong to
    /// it but are not store settings.
    fn section_with<'a>(
        &'a self,
        body: Column<'a, Message>,
        section: &'static Section,
        layout: Layout,
        extra: Vec<Element<'a, Message>>,
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
        ui::section(body, section.title, rows.chain(extra).collect())
    }
}

fn sharing_rows(rows: Vec<Element<'_, sharing::Msg>>) -> Vec<Element<'_, Message>> {
    rows.into_iter().map(|r| r.map(Message::Sharing)).collect()
}

fn services_rows(rows: Vec<Element<'_, services::Msg>>) -> Vec<Element<'_, Message>> {
    rows.into_iter().map(|r| r.map(Message::Services)).collect()
}

/// The column that continues a panel's page below another part: the page's
/// side and bottom padding, no title.
fn tail_column<'a, M: 'a>(layout: Layout) -> Column<'a, M> {
    let pad = if layout.stacked { 16.0 } else { 28.0 };
    Column::new()
        .spacing(10)
        .padding(iced::Padding {
            top: 0.0,
            right: pad,
            bottom: pad,
            left: pad,
        })
        .width(Length::Fill)
        .max_width(PAGE_WIDTH)
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
