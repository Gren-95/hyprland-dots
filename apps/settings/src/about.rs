//! About panel: a header with the distro logo, hardware and battery tiles,
//! storage meters, the network, software versions and the dots repository,
//! plus a button that copies it all as text for bug reports. The facts come
//! from sysinfo.rs.

use iced::widget::{Column, Row, Space, column, container, image, progress_bar, row, svg, text};
use iced::{Alignment, Element, Length, Task};
use lucide_iced::bytes as ico;

use crate::style::{self, Action};
use crate::sysinfo::{self, Battery, Disk, Info, Network, Repo, duration, gib};
use crate::system;
use crate::ui;

const LOGO: f32 = 84.0;
/// Height of a tile: two lines of value, a meter and a detail.
const TILE: f32 = 124.0;

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
        if let Some(b) = &i.battery {
            body = battery(body, b);
        }
        if !i.disks.is_empty() {
            body = ui::section(body, "Storage", i.disks.iter().map(disk).collect());
        }
        if let Some(n) = &i.network {
            body = ui::section(body, "Network", network(n));
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

fn heading<'a>(title: &str) -> Element<'a, Msg> {
    column![
        Space::new().height(8),
        text(title.to_uppercase())
            .font(style::FONT_BOLD)
            .size(11)
            .color(style::MUTED_DEEP)
    ]
    .into()
}

/// Logo, system name, computer, and chips for the host name, uptime and IP.
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
    if let Some(address) = i.network.as_ref().and_then(|n| n.addresses.first()) {
        chips = chips.push(chip(
            ico::NETWORK,
            address.split('/').next().unwrap_or_default().to_string(),
        ));
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

/// A usage bar drawn with one of the style::*_meter looks.
fn bar<'a>(share: f32, look: impl Fn(&iced::Theme) -> progress_bar::Style + 'a) -> Element<'a, Msg> {
    progress_bar(0.0..=1.0, share).girth(6).style(look).into()
}

/// Processor, memory and graphics side by side.
fn hardware(i: &Info) -> Element<'_, Msg> {
    let used = i.mem_total_kib.saturating_sub(i.mem_avail_kib);
    let memory_share = if i.mem_total_kib == 0 {
        0.0
    } else {
        used as f32 / i.mem_total_kib as f32
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
            gib(i.mem_total_kib),
            format!("{} in use", gib(used)),
            Some(bar(memory_share, style::meter(memory_share))),
        ),
        tile(ico::MONITOR, "Graphics", gpu_names, gpu_detail, None),
    ];
    Row::with_children(tiles).spacing(10).height(TILE).into()
}

/// Charge and health tiles, then the rest of what the battery reports.
fn battery<'a>(body: Column<'a, Msg>, b: &'a Battery) -> Column<'a, Msg> {
    let health = b.health();
    let charge = b.percent as f32 / 100.0;
    let limit = match b.limit {
        (Some(start), Some(end)) => format!(" · charges {start}–{end} %"),
        (None, Some(end)) => format!(" · charges to {end} %"),
        _ => String::new(),
    };
    let cycles = b.cycles.map(|c| format!(" · {c} cycles")).unwrap_or_default();
    let tiles = Row::with_children([
        tile(
            ico::BATTERY_CHARGING,
            "Charge",
            format!("{} %", b.percent),
            format!("{}{limit}", b.status),
            Some(bar(charge, style::health_meter(charge, 0.2, 0.4))),
        ),
        tile(
            ico::HEART_PULSE,
            "Health",
            format!("{:.0} %", health * 100.0),
            format!("{:.1} of {:.1} Wh when new{cycles}", b.full_wh, b.design_wh),
            Some(bar(health, style::health_meter(health, 0.5, 0.8))),
        ),
    ])
    .spacing(10)
    .height(TILE);
    let model = [b.model.as_str(), b.technology.as_str()]
        .iter()
        .filter(|s| !s.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(" · ");
    let rows = facts([
        (
            ico::ZAP,
            "Power",
            b.power_w.map(|w| format!("{w:.1} W")).unwrap_or_default(),
        ),
        (
            ico::THERMOMETER,
            "Temperature",
            b.temp_c.map(|t| format!("{t:.1} °C")).unwrap_or_default(),
        ),
        (ico::BATTERY, "Model", model),
        (ico::CALENDAR, "Made", b.made.clone()),
    ]);
    let body = body.push(heading("Battery")).push(tiles);
    if rows.is_empty() {
        body
    } else {
        body.push(container(column(rows).spacing(2)).padding(6).style(style::card))
    }
}

fn tile<'a>(
    glyph: ui::Icon,
    label: &'a str,
    value: String,
    detail: String,
    meter: Option<Element<'a, Msg>>,
) -> Element<'a, Msg> {
    let col = column![
        row![
            ui::icon(glyph, 16.0),
            text(label.to_uppercase())
                .font(style::FONT_BOLD)
                .size(10)
                .color(style::MUTED_DEEP)
        ]
        .spacing(8)
        .align_y(Alignment::Center),
        text(value).size(14).color(style::FG),
    ]
    .push(meter)
    .push((!detail.is_empty()).then(|| text(detail).size(12).color(style::MUTED_DEEP)))
    .spacing(8);
    container(col)
        .padding([14, 16])
        .width(Length::Fill)
        .height(Length::Fill)
        .style(style::card)
        .into()
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

fn network(n: &Network) -> Vec<Element<'_, Msg>> {
    let glyph = if n.kind == "Wi-Fi" {
        ico::WIFI
    } else {
        ico::ETHERNET_PORT
    };
    let connection = [n.connection.as_str(), n.device.as_str()]
        .iter()
        .filter(|s| !s.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(" · ");
    facts([
        (glyph, n.kind.as_str(), connection),
        (ico::NETWORK, "Address", n.addresses.join("\n")),
        (ico::ROUTER, "Gateway", n.gateway.clone()),
        (ico::BOOK_OPEN, "DNS", n.dns.join("\n")),
    ])
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

/// Fact rows for the non-empty values.
fn facts<'a, const N: usize>(list: [(ui::Icon, &'a str, String); N]) -> Vec<Element<'a, Msg>> {
    list.into_iter()
        .filter(|(_, _, v)| !v.is_empty())
        .map(|(g, k, v)| fact(g, k, v, None))
        .collect()
}

fn fact<'a>(glyph: ui::Icon, label: &'a str, value: String, control: Option<Element<'a, Msg>>) -> Element<'a, Msg> {
    let line = row![
        container(ui::icon(glyph, 18.0)).width(26).center_x(26),
        text(label).size(14).color(style::FG).width(130),
        text(value).size(14).color(style::FG_MUTED).width(Length::Fill),
    ]
    .push(control)
    .spacing(12)
    .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}
