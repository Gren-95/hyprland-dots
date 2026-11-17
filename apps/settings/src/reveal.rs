//! Scrolling a panel to one setting's row, for search results. iced has no
//! "scroll to this widget", so a widget operation finds where the row sits in
//! the panel's scrollable and the scrollable is then scrolled there.

use iced::Rectangle;
use iced::Task;
use iced::Vector;
use iced::advanced::widget::operation::{Outcome, Scrollable};
use iced::advanced::widget::{Id, Operation, operate};
use iced::widget::operation::scroll_to;
use iced::widget::scrollable::AbsoluteOffset;

/// Room left above the row, so its section header stays in sight.
const MARGIN: f32 = 48.0;

/// The widget id of a setting's row.
pub fn row_id(file: &str) -> Id {
    Id::from(format!("setting:{file}"))
}

/// Scroll the scrollable `scroll` so the row of the setting stored in `file`
/// is near its top.
pub fn reveal<T: Send + 'static>(scroll: &'static str, file: &str) -> Task<T> {
    operate(FindRow {
        scroll: Id::new(scroll),
        row: row_id(file),
        content_top: None,
        row_top: None,
    })
    .then(move |offset: Option<f32>| match offset {
        Some(y) => scroll_to(
            scroll,
            AbsoluteOffset {
                x: None,
                y: Some((y - MARGIN).max(0.0)),
            },
        ),
        None => Task::none(),
    })
}

/// Finds the row's distance from the top of the scrollable's content.
struct FindRow {
    scroll: Id,
    row: Id,
    content_top: Option<f32>,
    row_top: Option<f32>,
}

impl Operation<Option<f32>> for FindRow {
    fn traverse(&mut self, operate: &mut dyn FnMut(&mut dyn Operation<Option<f32>>)) {
        operate(self);
    }

    fn scrollable(
        &mut self,
        id: Option<&Id>,
        _bounds: Rectangle,
        content_bounds: Rectangle,
        _translation: Vector,
        _state: &mut dyn Scrollable,
    ) {
        if id == Some(&self.scroll) {
            self.content_top = Some(content_bounds.y);
        }
    }

    fn container(&mut self, id: Option<&Id>, bounds: Rectangle) {
        if id == Some(&self.row) {
            self.row_top = Some(bounds.y);
        }
    }

    fn finish(&self) -> Outcome<Option<f32>> {
        Outcome::Some(match (self.content_top, self.row_top) {
            (Some(content), Some(row)) => Some(row - content),
            _ => None,
        })
    }
}
