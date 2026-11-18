//! About panel: a header with the distro logo, hardware tiles, storage
//! meters, software versions and the dots repository, plus a button that
//! copies it all as text for bug reports (battery and network included,
//! though Power and Network show those). The facts come from sysinfo.rs.

use iced::widget::{Column, Row, Space, column, container, image, row, svg, text};
use iced::{Alignment, Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::infoview::{TILE, bar, fact, facts, heading, tile};
use crate::memory;
use crate::style::{self, Action};
use crate::sysinfo::{self, Disk, Info, Repo, duration};
use crate::system;
use crate::ui;

const LOGO: f32 = 84.0;

#[derive(Default)]
pub struct State {
    info: Option<Info>,
    copied: bool,
    error: Option<String>,
}

#[derive(Debug, Clone)]
pub enum Msg {
    Load,
    Loaded(Box<Info>),
    Copy,
    Copied(Result<(), String>),
    /// Open a web page in the browser.
    Open(String),
    Opened(Result<(), String>),
}

impl State {
    pub fn update(&mut self, msg: Msg) -> Task<Msg> {
        match msg {
            Msg::Load => {
                return Task::perform(system::spawn(sysinfo::load), |i| {
                    Msg::Loaded(Box::new(i.unwrap_or_default()))
                });
            }
            Msg::Loaded(i) => {
                self.info = Some(*i);
                self.copied = false;
            }
            Msg::Copy => {
                if let Some(i) = &self.info {
                    let text = sysinfo::as_text(i);
                    return Task::perform(system::run("wl-copy", vec![], Some(text)), |r| {
                        Msg::Copied(r.map(|_| ()))
                    });
                }
            }
            Msg::Copied(r) => {
                self.copied = r.is_ok();
                self.error = r.err();
            }
            Msg::Open(url) => {
                return Task::perform(system::run("xdg-open", vec![url], None), |r| Msg::Opened(r.map(|_| ())));
            }
            Msg::Opened(r) => self.error = r.err(),
        }
        Task::none()
    }

    pub fn view<'a>(&'a self, mut body: Column<'a, Msg>) -> Column<'a, Msg> {
        if let Some(e) = &self.error {
            body = body.push(ui::error(e));
        }
        let Some(i) = &self.info else {
            return ui::section(body, "This system", vec![ui::note("Loading…")]);
        };
        body = body.push(hero(i)).push(heading("Hardware")).push(hardware(i));
        body = ui::section(body, "Memory", memory_rows(i));
        if !i.disks.is_empty() {
            body = ui::section(body, "Storage", i.disks.iter().map(disk).collect());
        }
        let software = [
            (ico::BOX, "Kernel", i.kernel.clone()),
            (ico::LAYOUT_GRID, "Hyprland", i.hyprland.clone()),
            (ico::PANELS_TOP_LEFT, "Quickshell", i.quickshell.clone()),
            (ico::PACKAGE, "Packages", sysinfo::packages_text(&i.packages)),
            (ico::SETTINGS, "Settings app", i.app.clone()),
        ];
        body = ui::section(body, "Software", facts(software));
        if let Some(r) = &i.repo {
            body = ui::section(body, "Dots repository", repo(r));
        }
        let label = if self.copied {
            "Copied to the clipboard"
        } else {
            "Copy as text"
        };
        body.push(
            row![
                text("For bug reports: all of the above, as text")
                    .size(12)
                    .color(style::MUTED_DEEP)
                    .width(Length::Fill),
                ui::action(label, Some(Msg::Copy), Action::Primary),
            ]
            .align_y(Alignment::Center)
            .padding([4, 6]),
        )
    }
}

/// Logo, system name, computer, and chips for the host name and uptime.
fn hero(i: &Info) -> Element<'_, Msg> {
    let logo: Element<'_, Msg> = match &i.logo {
        Some(p) if p.extension().is_some_and(|e| e == "svg") => {
            svg(svg::Handle::from_path(p)).width(LOGO).height(LOGO).into()
        }
        Some(p) => image(image::Handle::from_path(p)).width(LOGO).height(LOGO).into(),
        None => ui::icon(ico::MONITOR, LOGO * 0.6),
    };
    let mut chips = Row::new().spacing(8);
    if !i.host.is_empty() {
        chips = chips.push(chip(ico::AT_SIGN, i.host.clone()));
    }
    if i.uptime_secs > 0 {
        chips = chips.push(chip(ico::CLOCK, format!("Up {}", duration(i.uptime_secs))));
    }
    let info = column![
        text(i.system.clone()).font(style::FONT_BOLD).size(26).color(style::FG),
        text(i.computer.clone()).size(14).color(style::FG_MUTED),
        Space::new().height(6),
        chips.wrap(),
    ]
    .spacing(2);
    container(
        row![container(logo).center_x(LOGO + 8.0).center_y(LOGO + 8.0), info]
            .spacing(20)
            .align_y(Alignment::Center),
    )
    .padding([22, 24])
    .width(Length::Fill)
    .style(style::hero)
    .into()
}

fn chip<'a>(glyph: ui::Icon, label: String) -> Element<'a, Msg> {
    container(
        row![ui::icon(glyph, 13.0), text(label).size(12).color(style::FG_MUTED)]
            .spacing(6)
            .align_y(Alignment::Center),
    )
    .padding([4, 10])
    .style(style::pill)
    .into()
}

/// Processor, memory and graphics side by side.
fn hardware(i: &Info) -> Element<'_, Msg> {
    let used = i.memory.used();
    let memory_share = if i.memory.total == 0 {
        0.0
    } else {
        used as f32 / i.memory.total as f32
    };
    let gpu_names = i.gpus.iter().map(|g| g.name.clone()).collect::<Vec<_>>().join("\n");
    let gpu_detail = i.gpus.iter().map(sysinfo::gpu_detail).collect::<Vec<_>>().join("\n");
    let tiles = [
        tile(
            ico::CPU,
            "Processor",
            i.cpu.clone(),
            format!("{} threads", i.threads),
            None,
        ),
        tile(
            ico::MEMORY_STICK,
            "Memory",
            memory::kib(i.memory.total),
            format!("{} in use", memory::kib(used)),
            Some(bar(memory_share, style::meter(memory_share))),
        ),
        tile(ico::MONITOR, "Graphics", gpu_names, gpu_detail, None),
    ];
    Row::with_children(tiles).spacing(10).height(TILE).into()
}

/// The modules, what is in use and cached, swap and zswap.
fn memory_rows(i: &Info) -> Vec<Element<'_, Msg>> {
    let m = &i.memory;
    let mut rows = Vec::new();
    if let Some(modules) = &i.modules {
        rows.extend(facts([
            (ico::MEMORY_STICK, "Type", memory::modules_kind(modules)),
            (ico::LAYERS, "Installed", memory::modules_layout(modules)),
        ]));
    }
    rows.extend(facts([
        (
            ico::ACTIVITY,
            "In use",
            format!("{} of {} usable", memory::kib(m.used()), memory::kib(m.total)),
        ),
        (
            ico::DATABASE,
            "Cache",
            format!("{}, given back when apps need it", memory::kib(m.cache)),
        ),
        (ico::CIRCLE_CHECK, "Available", memory::kib(m.available)),
    ]));
    for swap in &i.swaps {
        let label = if swap.zram { "Swap (zram)" } else { "Swap (disk)" };
        let value = format!(
            "{} of {} used · {}",
            memory::kib(swap.used),
            memory::kib(swap.size),
            swap.name
        );
        rows.push(fact(ico::ARROW_LEFT_RIGHT, label, value, None));
    }
    if m.zswapped > 0 {
        let value = format!("{} kept in {}", memory::kib(m.zswapped), memory::kib(m.zswap));
        rows.push(fact(ico::SHRINK, "Zswap", value, None));
    }
    rows
}

fn disk(d: &Disk) -> Element<'_, Msg> {
    let line = row![
        container(ui::icon(ico::HARD_DRIVE, 18.0)).width(26).center_x(26),
        column![
            row![
                text(d.mount.clone()).size(14).color(style::FG).width(Length::Fill),
                text(format!("{} free of {}", d.avail, d.size))
                    .size(12)
                    .color(style::MUTED_DEEP),
            ],
            bar(d.used, style::meter(d.used)),
        ]
        .spacing(8),
    ]
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}

fn plural(n: usize, word: &str) -> String {
    format!("{n} {word}{}", if n == 1 { "" } else { "s" })
}

fn repo(r: &Repo) -> Vec<Element<'_, Msg>> {
    let open = r
        .url
        .as_ref()
        .map(|u| ui::action("Open on GitHub", Some(Msg::Open(u.clone())), Action::Normal));
    let commit = if r.when.is_empty() {
        r.commit.clone()
    } else {
        format!("{}\n{}", r.commit, r.when)
    };
    let mut state = Vec::new();
    if r.unpushed > 0 {
        state.push(format!("{} not pushed", plural(r.unpushed, "commit")));
    }
    if r.changed > 0 {
        state.push(format!("{} not committed", plural(r.changed, "changed file")));
    }
    let state = if state.is_empty() {
        "Everything pushed".to_string()
    } else {
        state.join(" · ")
    };
    vec![
        fact(ico::GIT_FORK, "Repository", r.slug.clone(), open),
        fact(ico::GIT_BRANCH, "Branch", r.branch.clone(), None),
        fact(ico::GIT_COMMIT_HORIZONTAL, "Last commit", commit, None),
        fact(ico::UPLOAD, "State", state, None),
    ]
}
