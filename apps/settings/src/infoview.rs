//! Read-only system facts drawn the same way on About, Power and Network:
//! section headings, tiles with a meter, fact rows, the battery block and
//! the network details.

use iced::widget::{Column, Row, Space, column, container, progress_bar, row, text};
use iced::{Alignment, Element, Length};
use lucide_iced::bytes as ico;

use crate::style;
use crate::sysinfo::{Battery, Network};
use crate::ui;

/// Height of a tile: two lines of value, a meter and a detail.
pub const TILE: f32 = 124.0;

pub fn heading<'a, M: 'a>(title: &str) -> Element<'a, M> {
    column![
        Space::new().height(8),
        text(title.to_uppercase())
            .font(style::FONT_BOLD)
            .size(11)
            .color(style::MUTED_DEEP)
    ]
    .into()
}

/// A usage bar drawn with one of the style::*_meter looks.
pub fn bar<'a, M: 'a>(share: f32, look: impl Fn(&iced::Theme) -> progress_bar::Style + 'a) -> Element<'a, M> {
    progress_bar(0.0..=1.0, share).girth(6).style(look).into()
}

/// Charge and health tiles, then the rest of what the battery reports.
pub fn battery<'a, M: 'a>(body: Column<'a, M>, b: &'a Battery) -> Column<'a, M> {
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

pub fn tile<'a, M: 'a>(
    glyph: ui::Icon,
    label: &'a str,
    value: String,
    detail: String,
    meter: Option<Element<'a, M>>,
) -> Element<'a, M> {
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

/// Fact rows for the non-empty values.
pub fn facts<'a, M: 'a, const N: usize>(list: [(ui::Icon, &'a str, String); N]) -> Vec<Element<'a, M>> {
    list.into_iter()
        .filter(|(_, _, v)| !v.is_empty())
        .map(|(g, k, v)| fact(g, k, v, None))
        .collect()
}

pub fn fact<'a, M: 'a>(
    glyph: ui::Icon,
    label: &'a str,
    value: String,
    control: Option<Element<'a, M>>,
) -> Element<'a, M> {
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

/// A device's addresses, gateway, DNS, hardware address and interface,
/// for the Details under a connected network row.
pub fn connection_details<'a, M: 'a>(n: &'a Network) -> Element<'a, M> {
    let rows = facts([
        (ico::NETWORK, "Address", n.addresses.join("\n")),
        (ico::ROUTER, "Gateway", n.gateway.clone()),
        (ico::BOOK_OPEN, "DNS", n.dns.join("\n")),
        (ico::TAG, "Hardware address", n.hardware.clone()),
        (ico::CABLE, "Interface", n.device.clone()),
    ]);
    container(column(rows).spacing(0))
        .padding(iced::Padding {
            top: 0.0,
            right: 0.0,
            bottom: 6.0,
            left: 38.0,
        })
        .into()
}
