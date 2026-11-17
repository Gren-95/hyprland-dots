//! Pieces every panel is built from: section headers, cards, list rows and
//! small action buttons.

use iced::widget::{Column, Space, button, column, container, row, text};
use iced::{Alignment, Element, Length};

use crate::style;

/// A section header followed by a card holding `rows`.
pub fn section<'a, M: 'a>(body: Column<'a, M>, title: &str, rows: Vec<Element<'a, M>>) -> Column<'a, M> {
    body.push(Space::new().height(8))
        .push(
            text(title.to_uppercase())
                .font(style::FONT_BOLD)
                .size(11)
                .color(style::MUTED_DEEP),
        )
        .push(container(column(rows).spacing(2)).padding(6).style(style::card))
}

/// A list row: glyph, a title with a muted line under it, and controls on
/// the right.
pub fn item<'a, M: 'a>(
    glyph: &'static str,
    title: String,
    detail: String,
    controls: Vec<Element<'a, M>>,
) -> Element<'a, M> {
    let mut info = column![text(title).size(14).color(style::FG)]
        .spacing(2)
        .width(Length::Fill);
    if !detail.is_empty() {
        info = info.push(text(detail).size(12).color(style::MUTED_DEEP));
    }
    let line = row![text(glyph).font(style::GLYPH_FONT).size(18).width(26).center(), info]
        .extend(controls)
        .spacing(12)
        .align_y(Alignment::Center);
    container(line).padding([10, 14]).into()
}

/// A muted line inside a card, for empty lists and loading.
pub fn note<'a, M: 'a>(message: impl text::IntoFragment<'a>) -> Element<'a, M> {
    container(text(message).size(13).color(style::FG_MUTED))
        .padding([10, 14])
        .into()
}

/// An error line under a panel's title.
pub fn error<'a, M: 'a>(message: &'a str) -> Element<'a, M> {
    text(message).size(13).color(style::RED).into()
}

/// A small text button; `on_press` None draws it disabled.
pub fn action<'a, M: Clone + 'a>(label: &'a str, on_press: Option<M>, kind: style::Action) -> Element<'a, M> {
    button(text(label).size(13))
        .on_press_maybe(on_press)
        .padding([5, 12])
        .style(style::action(kind))
        .into()
}
