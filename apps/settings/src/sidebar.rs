//! The sidebar: a search field over the list of panels. While there is text
//! in the field the list shows the search results instead: the matching
//! panels, each with its matching settings under it. Clicking a result
//! opens its panel.

use iced::widget::{Column, Space, button, column, container, row, scrollable, text, text_input, tooltip};
use iced::{Alignment, Element, Length};

use crate::app::{Layout, Message, SEARCH_ID};
use crate::schema::PANELS;
use crate::search;
use crate::style;

/// `panel` is the open panel, `query` the text in the search field.
pub fn view<'a>(panel: usize, query: &'a str, layout: Layout) -> Element<'a, Message> {
    let body: Element<'a, Message> = if layout.compact_sidebar {
        compact(panel)
    } else {
        let field = text_input("Search", query)
            .id(SEARCH_ID)
            .on_input(Message::Search)
            .padding([7, 10])
            .style(style::field);
        let list = if query.trim().is_empty() {
            panels(panel)
        } else {
            results(panel, query)
        };
        column![
            container(text("Settings").font(style::FONT_BOLD).size(18).color(style::FG)).padding([14, 12]),
            field,
            // A thin scrollbar beside the list, not over it.
            scrollable(list.spacing(2))
                .direction(scrollable::Direction::Vertical(
                    scrollable::Scrollbar::new().width(4).scroller_width(4).spacing(4)
                ))
                .height(Length::Fill),
        ]
        .spacing(10)
        .into()
    };
    container(body)
        .width(layout.sidebar_width)
        .height(Length::Fill)
        .padding(if layout.compact_sidebar { 6 } else { 10 })
        .style(style::sidebar)
        .into()
}

fn panel_entry<'a>(i: usize, selected: bool) -> button::Button<'a, Message> {
    let p = &PANELS[i];
    button(
        row![glyph(p.glyph), text(p.title).size(14)]
            .spacing(8)
            .align_y(Alignment::Center),
    )
    .on_press(Message::SelectPanel(i))
    .width(Length::Fill)
    .padding([9, 12])
    .style(style::nav(selected))
}

fn glyph<'a>(g: &'static str) -> text::Text<'a> {
    text(g).font(style::GLYPH_FONT).size(18).width(26).center()
}

/// The panel list under group headers.
fn panels<'a>(open: usize) -> Column<'a, Message> {
    let mut list = column![];
    for (i, panel) in PANELS.iter().enumerate() {
        if i == 0 || PANELS[i - 1].group != panel.group {
            let top = if i == 0 { 0 } else { 12 };
            list = list.push(
                container(
                    text(panel.group.title().to_uppercase())
                        .font(style::FONT_BOLD)
                        .size(11)
                        .color(style::MUTED_DEEP),
                )
                .padding(iced::Padding {
                    top: top as f32,
                    right: 12.0,
                    bottom: 4.0,
                    left: 12.0,
                }),
            );
        }
        list = list.push(panel_entry(i, i == open));
    }
    list
}

fn results<'a>(open: usize, query: &str) -> Column<'a, Message> {
    let groups = search::search(query);
    if groups.is_empty() {
        return column![container(text("No results").size(13).color(style::MUTED_DEEP)).padding([8, 12])];
    }
    let mut list = column![];
    for group in groups {
        list = list.push(panel_entry(group.panel, group.panel == open));
        for setting in group.settings {
            // Indented under the panel name, past its glyph.
            let entry = button(text(setting.label).size(13))
                .on_press(Message::Reveal(group.panel, setting.file))
                .width(Length::Fill)
                .padding([6, 12])
                .style(style::nav(false));
            list = list.push(row![Space::new().width(34), entry]);
        }
    }
    list
}

/// Icons only; the search glyph widens the sidebar so the field fits.
fn compact<'a>(open: usize) -> Element<'a, Message> {
    let search = with_tooltip(
        button(glyph("󰍉"))
            .on_press(Message::FocusSearch)
            .padding([9, 12])
            .style(style::nav(false)),
        "Search (Ctrl+F)",
    );
    // Icons only: a thin line between groups instead of their headers.
    let mut entries = column![].spacing(2);
    for i in 0..PANELS.len() {
        if i > 0 && PANELS[i - 1].group != PANELS[i].group {
            entries = entries.push(
                container(
                    container(Space::new())
                        .width(Length::Fill)
                        .height(1)
                        .style(style::divider),
                )
                .padding([6, 10]),
            );
        }
        let entry = button(glyph(PANELS[i].glyph))
            .on_press(Message::SelectPanel(i))
            .padding([9, 12])
            .style(style::nav(i == open));
        entries = entries.push(with_tooltip(entry, PANELS[i].title));
    }
    column![Space::new().height(8), search, entries].spacing(10).into()
}

fn with_tooltip<'a>(content: button::Button<'a, Message>, tip: &'a str) -> Element<'a, Message> {
    tooltip(
        content,
        container(text(tip).size(13)).padding([4, 8]).style(style::card),
        tooltip::Position::Right,
    )
    .into()
}
