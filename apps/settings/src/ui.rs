//! Pieces every panel is built from: section headers, cards, list rows and
//! small action buttons.

use std::fmt;

use iced::widget::{Column, Row, Space, TextInput, button, column, container, pick_list, row, text};
use iced::{Alignment, Element, Length};

use crate::style;

/// A Lucide icon's SVG bytes (`lucide_iced::bytes::*`).
pub type Icon = &'static [u8];

/// An icon drawn in the colour of the text around it (the accent in a
/// selected sidebar entry, muted in a row), like a glyph.
pub fn icon<'a, M: 'a>(icon: Icon, size: f32) -> Element<'a, M> {
    lucide_iced::themed_icon(icon, size)
}

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
pub fn item<'a, M: 'a>(glyph: Icon, title: String, detail: String, controls: Vec<Element<'a, M>>) -> Element<'a, M> {
    let mut info = column![text(title).size(14).color(style::FG)]
        .spacing(2)
        .width(Length::Fill);
    if !detail.is_empty() {
        info = info.push(text(detail).size(12).color(style::MUTED_DEEP));
    }
    let line = row![container(icon(glyph, 18.0)).width(26).center_x(26), info]
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
        let mut content = row![].spacing(6).align_y(Alignment::Center);
        if on {
            content = content.push(icon(lucide_iced::bytes::CHECK, GROUP_TEXT));
        }
        let content = content.push(text(label).size(GROUP_TEXT));
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

/// A dropdown entry: shown by label, picked by position.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Entry {
    index: usize,
    label: String,
}

impl fmt::Display for Entry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.label)
    }
}

/// A dropdown of options, each (label, selected, message when picked).
pub fn select<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>, width: Length) -> Element<'a, M> {
    let entries: Vec<Entry> = items
        .iter()
        .enumerate()
        .map(|(index, (label, _, _))| Entry {
            index,
            label: label.to_string(),
        })
        .collect();
    let selected = items.iter().position(|(_, on, _)| *on).map(|i| entries[i].clone());
    let messages: Vec<Option<M>> = items.into_iter().map(|(_, _, m)| m).collect();
    // iced's pick_list cannot be disabled, so a busy dropdown is drawn as a
    // disabled button showing the current pick.
    if messages.iter().any(Option::is_none) {
        let shown = selected.map(|e| e.label).unwrap_or_default();
        return disabled(shown, width);
    }
    let messages: Vec<M> = messages.into_iter().flatten().collect();
    pick_list(entries, selected, move |e: Entry| messages[e.index].clone())
        .text_size(GROUP_TEXT)
        .width(width)
        .into()
}

/// A greyed-out, inert stand-in for a control.
fn disabled<'a, M: Clone + 'a>(label: String, width: Length) -> Element<'a, M> {
    button(text(label).size(GROUP_TEXT))
        .padding([5, 10])
        .width(width)
        .style(style::action(style::Action::Normal))
        .into()
}

/// One choice out of several (UI.md): two options are a joined button
/// group, three or more a dropdown.
pub fn choice<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>, width: Length) -> Element<'a, M> {
    if items.len() == 2 {
        segmented(items, width)
    } else {
        select(items, width)
    }
}

/// Width of every "More" dropdown, so rows line up.
const MORE_WIDTH: f32 = 128.0;

/// The main action as a button with the other actions in a "More" dropdown
/// beside it (UI.md: more than two buttons on a row). With one other action
/// the two are a joined button group instead.
pub fn more_actions<'a, M: Clone + 'a>(
    main: (&'a str, Option<M>, style::Action),
    others: Vec<(&'a str, Option<M>)>,
) -> Element<'a, M> {
    // Two actions in all: a joined pair, no menu with one entry in it.
    if let [(label, on_press)] = others.as_slice() {
        return button_group(vec![(*label, on_press.clone(), style::Action::Normal), main]);
    }
    row![menu(others), action(main.0, main.1, main.2)]
        .spacing(6)
        .align_y(Alignment::Center)
        .into()
}

/// A "More" dropdown of actions. Actions without a message are left out;
/// with none left it is drawn disabled.
pub fn menu<'a, M: Clone + 'a>(actions: Vec<(&'a str, Option<M>)>) -> Element<'a, M> {
    let usable: Vec<(&'a str, M)> = actions
        .into_iter()
        .filter_map(|(label, m)| m.map(|m| (label, m)))
        .collect();
    if usable.is_empty() {
        return disabled("More".into(), Length::Fixed(MORE_WIDTH));
    }
    let entries: Vec<Entry> = usable
        .iter()
        .enumerate()
        .map(|(index, (label, _))| Entry {
            index,
            label: label.to_string(),
        })
        .collect();
    let messages: Vec<M> = usable.into_iter().map(|(_, m)| m).collect();
    pick_list(entries, None::<Entry>, move |e: Entry| messages[e.index].clone())
        .placeholder("More")
        .text_size(13)
        .padding([5, 10])
        .width(MORE_WIDTH)
        .into()
}

/// One match of a search picker: label, the font to draw it in (fonts are
/// previewed in themselves), a muted detail on the right, and the message.
pub struct PickerMatch<M> {
    pub label: String,
    pub font: Option<iced::Font>,
    pub detail: String,
    pub on_pick: M,
}

/// A search field with the matching entries listed under it (UI.md: search
/// picker). Used for long lists: keyboard layouts, fonts.
pub fn search_picker<'a, M: Clone + 'a>(
    placeholder: &'a str,
    query: &'a str,
    on_input: impl Fn(String) -> M + 'a,
    matches: Vec<PickerMatch<M>>,
) -> Element<'a, M> {
    let field = iced::widget::text_input(placeholder, query)
        .on_input(on_input)
        .padding([7, 10])
        .style(style::field);
    let mut list = column![field].spacing(2);
    for m in matches {
        let mut label = text(m.label).size(14).width(Length::Fill);
        if let Some(font) = m.font {
            label = label.font(font);
        }
        list = list.push(
            button(row![label, text(m.detail).size(12).color(style::MUTED_DEEP)].align_y(Alignment::Center))
                .on_press(m.on_pick)
                .width(Length::Fill)
                .padding([6, 12])
                .style(style::nav(false)),
        );
    }
    list.into()
}

/// A row of rounded filter pills that wraps; one is picked at a time (the
/// shortcut categories). Each item is (label, picked, message).
pub fn pills<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>) -> Element<'a, M> {
    let buttons = items.into_iter().map(|(label, picked, on_press)| {
        button(text(label).size(13))
            .on_press_maybe(on_press)
            .padding([4, 12])
            .style(style::filter_pill(picked))
            .into()
    });
    Row::with_children(buttons).spacing(6).wrap().into()
}
