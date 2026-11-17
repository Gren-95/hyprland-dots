//! Pieces every panel is built from: section headers, cards, list rows and
//! small action buttons.

use iced::widget::{Column, Row, Space, TextInput, button, column, container, row, text};
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

/// A button's share of its group's width: longer labels get more room, so
/// none wraps while the group still fills its width.
fn share(label: &str) -> Length {
    Length::FillPortion(label.chars().count().clamp(3, 30) as u16 + 4)
}

/// Height of every part of a joined group, so they line up.
const GROUP_TEXT: f32 = 14.0;

/// A segmented control: joined buttons, one per option, the selected one
/// filled. Each item is (label, selected, message when pressed).
pub fn segmented<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>, width: Length) -> Element<'a, M> {
    let count = items.len();
    let buttons = items.into_iter().enumerate().map(|(i, (label, selected, on_press))| {
        button(text(label).size(GROUP_TEXT).center().width(Length::Fill))
            .on_press_maybe(on_press)
            .padding([8, 10])
            .width(share(label))
            .style(style::segment(selected, style::Joint::of(i, count)))
            .into()
    });
    // Overlap by one pixel so neighbours share a single border line.
    Row::with_children(buttons).spacing(-1.0).width(width).into()
}

/// A multi-select button group: joined buttons that are each on or off;
/// on ones are filled and checked. Each item is (label, on, message).
pub fn multi_select<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>, width: Length) -> Element<'a, M> {
    let count = items.len();
    let buttons = items.into_iter().enumerate().map(|(i, (label, on, on_press))| {
        let mark = text(if on { "󰄬" } else { "" }).font(style::GLYPH_FONT).size(GROUP_TEXT);
        let content = row![mark, text(label).size(GROUP_TEXT)]
            .spacing(6)
            .align_y(Alignment::Center);
        button(container(content).center_x(Length::Fill))
            .on_press_maybe(on_press)
            .padding([8, 10])
            .width(share(label))
            .style(style::segment(on, style::Joint::of(i, count)))
            .into()
    });
    Row::with_children(buttons).spacing(-1.0).width(width).into()
}

/// Plain action buttons joined into one group: (label, message, kind).
pub fn button_group<'a, M: Clone + 'a>(buttons: Vec<(&'a str, Option<M>, style::Action)>) -> Element<'a, M> {
    let count = buttons.len();
    let parts = buttons.into_iter().enumerate().map(|(i, (label, on_press, kind))| {
        button(text(label).size(13))
            .on_press_maybe(on_press)
            .padding([5, 12])
            .style(style::action_at(kind, style::Joint::of(i, count)))
            .into()
    });
    Row::with_children(parts).spacing(-1.0).into()
}

/// An input group: a text field with buttons joined to its right.
pub fn input_group<'a, M: Clone + 'a>(
    field: TextInput<'a, M>,
    buttons: Vec<(&'a str, Option<M>, style::Action)>,
) -> Element<'a, M> {
    fields_group(vec![field], buttons)
}

/// An input group of several text fields followed by buttons.
pub fn fields_group<'a, M: Clone + 'a>(
    fields: Vec<TextInput<'a, M>>,
    buttons: Vec<(&'a str, Option<M>, style::Action)>,
) -> Element<'a, M> {
    let count = fields.len() + buttons.len();
    let mut group = Row::new().spacing(-1.0).align_y(Alignment::Center);
    let field_count = fields.len();
    for (i, field) in fields.into_iter().enumerate() {
        group = group.push(
            field
                .size(GROUP_TEXT)
                .padding([8, 10])
                .width(Length::Fill)
                .style(style::field_at(style::Joint::of(i, count))),
        );
    }
    for (i, (label, on_press, kind)) in buttons.into_iter().enumerate() {
        group = group.push(
            button(text(label).size(GROUP_TEXT))
                .on_press_maybe(on_press)
                .padding([8, 14])
                .style(style::action_at(kind, style::Joint::of(field_count + i, count))),
        );
    }
    group.into()
}
