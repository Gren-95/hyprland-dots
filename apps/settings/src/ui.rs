//! Pieces every panel is built from: section headers, cards, list rows and
//! small action buttons.

use std::fmt;

use iced::widget::{Column, Row, Space, TextInput, button, column, container, pick_list, row, text, tooltip};
use iced::{Alignment, Element, Length};

use crate::focus::focusable;
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

/// `content` with `words` in a small card under it on hover: help text
/// and what an icon button does live here instead of on the row.
pub fn tip<'a, M: 'a>(content: impl Into<Element<'a, M>>, words: impl text::IntoFragment<'a>) -> Element<'a, M> {
    tooltip(
        content,
        container(text(words).size(12))
            .padding([4, 8])
            .max_width(340)
            .style(style::card),
        tooltip::Position::Bottom,
    )
    .into()
}

/// A small icon button that says what it does on hover; `on_press` None
/// draws it disabled.
pub fn icon_action<'a, M: Clone + 'a>(
    glyph: Icon,
    words: &'a str,
    on_press: Option<M>,
    kind: style::Action,
) -> Element<'a, M> {
    let activate = on_press.clone();
    let b = button(icon(glyph, 15.0))
        .on_press_maybe(on_press)
        .padding([6, 8])
        .style(style::action(kind));
    tip(focusable(b, activate), words)
}

/// A destructive action that confirms (UI.md): an icon first, then "Sure?"
/// in red while it waits for the second press.
pub fn confirm_action<'a, M: Clone + 'a>(
    glyph: Icon,
    words: &'a str,
    asking: bool,
    on_press: Option<M>,
) -> Element<'a, M> {
    if asking {
        action("Sure?", on_press, style::Action::Danger)
    } else {
        icon_action(glyph, words, on_press, style::Action::Normal)
    }
}

/// A small text button; `on_press` None draws it disabled.
pub fn action<'a, M: Clone + 'a>(label: &'a str, on_press: Option<M>, kind: style::Action) -> Element<'a, M> {
    let activate = on_press.clone();
    let b = button(text(label).size(13))
        .on_press_maybe(on_press)
        .padding([5, 12])
        .style(style::action(kind));
    focusable(b, activate).into()
}

/// An on/off switch that Tab reaches and Enter or Space flips.
pub fn switch<'a, M: Clone + 'a>(on: bool, on_toggle: Option<impl Fn(bool) -> M + 'a>) -> Element<'a, M> {
    let activate = on_toggle.as_ref().map(|f| f(!on));
    focusable(iced::widget::toggler(on).on_toggle_maybe(on_toggle), activate)
        .radius(10.0)
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
        let activate = on_press.clone();
        let b = button(text(label).size(GROUP_TEXT).center().width(Length::Fill))
            .on_press_maybe(on_press)
            .padding([8, 10])
            .width(share(label))
            .style(style::segment(selected, style::Joint::of(i, count)));
        focusable(b, activate).into()
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
        let activate = on_press.clone();
        let b = button(container(content).center_x(Length::Fill))
            .on_press_maybe(on_press)
            .padding([8, 10])
            .width(share(label))
            .style(style::segment(on, style::Joint::of(i, count)));
        focusable(b, activate).into()
    });
    Row::with_children(buttons).spacing(-1.0).width(width).into()
}

/// Entries from which a collapsed list shows a search field when open.
pub const LIST_SEARCH_FROM: usize = 8;

/// Whether `label` matches a list's search text (case does not matter).
pub fn matches_query(label: &str, query: &str) -> bool {
    let q = query.trim().to_lowercase();
    q.is_empty() || label.to_lowercase().contains(&q)
}

/// A long list at a glance (UI.md: lists stay short): a summary row with a
/// count and Details; open, a search field for long lists and the entries
/// hanging under it as a tree.
#[allow(clippy::too_many_arguments)]
pub fn collapsed_list<'a, M: Clone + 'a>(
    glyph: Icon,
    title: &str,
    summary: String,
    open: bool,
    on_toggle: M,
    query: &'a str,
    on_query: impl Fn(String) -> M + 'a,
    entries: Vec<Element<'a, M>>,
    total: usize,
) -> Vec<Element<'a, M>> {
    let mut rows = vec![item(
        glyph,
        title.to_string(),
        summary,
        vec![disclosure(open, on_toggle)],
    )];
    if !open {
        return rows;
    }
    if total >= LIST_SEARCH_FROM {
        let search = iced::widget::text_input("Search", query)
            .on_input(on_query)
            .padding([6, 10])
            .size(13)
            .style(style::field);
        rows.push(container(search).padding([4, 14]).into());
    }
    if entries.is_empty() {
        rows.push(note("No match"));
    }
    let count = entries.len();
    rows.extend(entries.into_iter().enumerate().map(|(i, e)| branch(e, i + 1 == count)));
    rows
}

/// Whether on/off options become a switch tree (UI.md): more than two.
/// Two stay a joined button group.
pub fn is_switch_tree(count: usize) -> bool {
    count > 2
}

/// What a switch tree's summary row says: the options that are on, "None",
/// or "All".
pub fn on_summary(items: &[(&str, bool)]) -> String {
    let on: Vec<&str> = items.iter().filter(|(_, on)| *on).map(|(l, _)| *l).collect();
    match on.len() {
        0 => "None".into(),
        n if n == items.len() && n > 2 => "All".into(),
        _ => on.join(", "),
    }
}

/// The summary of a switch tree beside its label: what is on, and Details
/// to show the switches.
pub fn switch_tree_head<'a, M: Clone + 'a>(
    items: &[(&'a str, bool, Option<M>)],
    open: bool,
    on_toggle: M,
) -> Element<'a, M> {
    let summary = on_summary(&items.iter().map(|(l, on, _)| (*l, *on)).collect::<Vec<_>>());
    row![
        text(summary)
            .size(13)
            .color(style::FG_MUTED)
            .wrapping(text::Wrapping::None),
        disclosure(open, on_toggle)
    ]
    .spacing(12)
    .align_y(Alignment::Center)
    .into()
}

/// The options of an open switch tree: one row each with its own switch,
/// hanging under the summary row. Each item is (label, on, message that
/// flips it).
pub fn switch_rows<'a, M: Clone + 'a>(items: Vec<(&'a str, bool, Option<M>)>) -> Vec<Element<'a, M>> {
    let count = items.len();
    items
        .into_iter()
        .enumerate()
        .map(|(i, (label, on, message))| {
            let flip = message.map(|m| move |_: bool| m.clone());
            let line = row![
                text(label).size(14).color(style::FG).width(Length::Fill),
                switch(on, flip)
            ]
            .spacing(12)
            .align_y(Alignment::Center);
            // As tall as a list row, so the branch tick meets the middle.
            let row = container(line).padding([0, 14]).height(ROW_HEIGHT).center_y(ROW_HEIGHT);
            branch(row.into(), i + 1 == count)
        })
        .collect()
}

/// A "Details" button that shows or hides more about a row, with a chevron
/// for its state. It is not an action (UI.md): it does not count toward a
/// row's buttons.
pub fn disclosure<'a, M: Clone + 'a>(open: bool, on_press: M) -> Element<'a, M> {
    let glyph = if open {
        lucide_iced::bytes::CHEVRON_UP
    } else {
        lucide_iced::bytes::CHEVRON_DOWN
    };
    let b = button(icon(glyph, 15.0))
        .on_press(on_press.clone())
        .padding([6, 8])
        .style(style::action(style::Action::Normal));
    tip(
        focusable(b, Some(on_press)),
        if open { "Hide details" } else { "Details" },
    )
}

/// Height from the top of a list row to the middle of its title line, where
/// a tree branch meets it.
const BRANCH_AT: f32 = 27.0;

/// Height of a one-line row in a tree (a switch tree's options).
const ROW_HEIGHT: f32 = BRANCH_AT * 2.0;

/// `content` as one branch of a tree under the row above it (UI.md: the
/// networks under the Wi-Fi switch): a guide line down the left with a tick
/// to the content. `last` ends the guide line at this branch.
pub fn branch<'a, M: 'a>(content: Element<'a, M>, last: bool) -> Element<'a, M> {
    let line = |height: Length| container(Space::new()).width(1).height(height).style(style::divider);
    let guide: Element<'a, M> = if last {
        column![line(Length::Fixed(BRANCH_AT + 1.0)), Space::new().height(Length::Fill)].into()
    } else {
        line(Length::Fill).into()
    };
    let tick = column![
        Space::new().height(BRANCH_AT),
        container(Space::new()).width(12).height(1).style(style::divider)
    ];
    row![
        Space::new().width(26),
        guide,
        tick,
        container(content).width(Length::Fill)
    ]
    .height(Length::Shrink)
    .into()
}

/// A dialog over the window: `content` in a card in the middle, the rest
/// dimmed; clicking outside sends `on_close`.
pub fn modal<'a, M: Clone + 'a>(base: Element<'a, M>, content: Element<'a, M>, on_close: M) -> Element<'a, M> {
    let card = container(content).padding(20).max_width(460).style(style::card);
    let dialog = iced::widget::mouse_area(
        container(iced::widget::opaque(card))
            .center(Length::Fill)
            .style(style::backdrop),
    )
    .on_press(on_close);
    iced::widget::stack![base, iced::widget::opaque(dialog)].into()
}

/// Plain action buttons joined into one group: (label, message, kind).
pub fn button_group<'a, M: Clone + 'a>(buttons: Vec<(&'a str, Option<M>, style::Action)>) -> Element<'a, M> {
    let count = buttons.len();
    let parts = buttons.into_iter().enumerate().map(|(i, (label, on_press, kind))| {
        let activate = on_press.clone();
        let b = button(text(label).size(13))
            .on_press_maybe(on_press)
            .padding([5, 12])
            .style(style::action_at(kind, style::Joint::of(i, count)));
        focusable(b, activate).into()
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
    // From the keyboard, Enter or Space picks the next option.
    let next = selected.as_ref().map_or(0, |e| (e.index + 1) % messages.len().max(1));
    let activate = messages.get(next).cloned();
    let list = pick_list(entries, selected, move |e: Entry| messages[e.index].clone())
        .text_size(GROUP_TEXT)
        .width(width);
    focusable(list, activate).into()
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
        list = list.push(focusable(
            button(row![label, text(m.detail).size(12).color(style::MUTED_DEEP)].align_y(Alignment::Center))
                .on_press(m.on_pick.clone())
                .width(Length::Fill)
                .padding([6, 12])
                .style(style::nav(false)),
            Some(m.on_pick),
        ));
    }
    list.into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn more_than_two_options_are_a_switch_tree() {
        assert!(!is_switch_tree(2));
        assert!(is_switch_tree(3));
    }

    #[test]
    fn summarises_what_is_on() {
        assert_eq!(on_summary(&[("A", true), ("B", false)]), "A");
        assert_eq!(on_summary(&[("A", false), ("B", false)]), "None");
        assert_eq!(on_summary(&[("A", true), ("B", true), ("C", true)]), "All");
        assert_eq!(on_summary(&[("A", true), ("B", true), ("C", false)]), "A, B");
    }
}
