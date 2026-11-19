//! Keyboard navigation. iced only lets text fields take focus, so
//! `focusable` wraps any control (button, switch, segment, sidebar entry)
//! in a widget that Tab and Shift+Tab can focus: it draws a ring in the
//! accent colour while focused, and Enter or Space sends the control's
//! message. A mouse click anywhere drops the focus, so the ring only shows
//! while the keyboard is in use.
//!
//! The window has two zones: the sidebar and the open panel. Tab moves
//! through the panel's controls (wrapping round inside it); Shift+Tab goes
//! back to the sidebar entry of the open panel; Up and Down move along the
//! sidebar, and Enter there opens the panel with the focus on its first
//! control. After the focus moves the panel scrolls to keep it in sight.

use iced::advanced::layout::{self, Layout};
use iced::advanced::renderer::{self, Quad};
use iced::advanced::widget::operation::{Focusable, Outcome, Scrollable};
use iced::advanced::widget::{self, Id, Operation, Tree, tree};
use iced::advanced::{Clipboard, Shell, Widget, mouse, overlay};
use iced::keyboard::{self, key};
use iced::widget::operation::scroll_to;
use iced::widget::scrollable::AbsoluteOffset;
use iced::{Border, Color, Element, Event, Length, Rectangle, Size, Task, Theme, Vector, border};

/// Room kept between a focused control and the edge of the panel.
const MARGIN: f32 = 60.0;

#[derive(Debug, Default)]
struct State {
    focused: bool,
}

impl Focusable for State {
    fn is_focused(&self) -> bool {
        self.focused
    }
    fn focus(&mut self) {
        self.focused = true;
    }
    fn unfocus(&mut self) {
        self.focused = false;
    }
}

pub struct Focus<'a, M> {
    content: Element<'a, M>,
    on_activate: Option<M>,
    radius: f32,
    id: Option<Id>,
}

/// `content` that Tab can reach; Enter or Space sends `on_activate` (a
/// disabled control passes None and is skipped).
pub fn focusable<'a, M: Clone + 'a>(content: impl Into<Element<'a, M>>, on_activate: Option<M>) -> Focus<'a, M> {
    Focus {
        content: content.into(),
        on_activate,
        radius: 6.0,
        id: None,
    }
}

impl<'a, M> Focus<'a, M> {
    /// An id, so `focus_id` can focus it (sidebar entries).
    pub fn id(mut self, id: Id) -> Self {
        self.id = Some(id);
        self
    }

    /// Corner radius of the ring, to follow the control's shape.
    pub fn radius(mut self, radius: f32) -> Self {
        self.radius = radius;
        self
    }
}

impl<M: Clone> Widget<M, Theme, iced::Renderer> for Focus<'_, M> {
    fn tag(&self) -> tree::Tag {
        tree::Tag::of::<State>()
    }

    fn state(&self) -> tree::State {
        tree::State::new(State::default())
    }

    fn children(&self) -> Vec<Tree> {
        vec![Tree::new(&self.content)]
    }

    fn diff(&self, tree: &mut Tree) {
        tree.diff_children(std::slice::from_ref(&self.content));
    }

    fn size(&self) -> Size<Length> {
        self.content.as_widget().size()
    }

    fn layout(&mut self, tree: &mut Tree, renderer: &iced::Renderer, limits: &layout::Limits) -> layout::Node {
        self.content
            .as_widget_mut()
            .layout(&mut tree.children[0], renderer, limits)
    }

    fn operate(
        &mut self,
        tree: &mut Tree,
        layout: Layout<'_>,
        renderer: &iced::Renderer,
        operation: &mut dyn Operation,
    ) {
        if self.on_activate.is_some() {
            let state = tree.state.downcast_mut::<State>();
            operation.focusable(self.id.as_ref(), layout.bounds(), state);
        }
        self.content
            .as_widget_mut()
            .operate(&mut tree.children[0], layout, renderer, operation);
    }

    fn update(
        &mut self,
        tree: &mut Tree,
        event: &Event,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        renderer: &iced::Renderer,
        clipboard: &mut dyn Clipboard,
        shell: &mut Shell<'_, M>,
        viewport: &Rectangle,
    ) {
        if let Event::Mouse(mouse::Event::ButtonPressed(_)) = event {
            tree.state.downcast_mut::<State>().focused = false;
        }
        let focused = tree.state.downcast_ref::<State>().focused;
        if let (true, Some(message), Event::Keyboard(keyboard::Event::KeyPressed { key, .. })) =
            (focused, &self.on_activate, event)
            && matches!(key, keyboard::Key::Named(key::Named::Enter | key::Named::Space))
        {
            shell.publish(message.clone());
            shell.capture_event();
            return;
        }
        self.content.as_widget_mut().update(
            &mut tree.children[0],
            event,
            layout,
            cursor,
            renderer,
            clipboard,
            shell,
            viewport,
        );
    }

    fn mouse_interaction(
        &self,
        tree: &Tree,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        viewport: &Rectangle,
        renderer: &iced::Renderer,
    ) -> mouse::Interaction {
        self.content
            .as_widget()
            .mouse_interaction(&tree.children[0], layout, cursor, viewport, renderer)
    }

    fn draw(
        &self,
        tree: &Tree,
        renderer: &mut iced::Renderer,
        theme: &Theme,
        style: &renderer::Style,
        layout: Layout<'_>,
        cursor: mouse::Cursor,
        viewport: &Rectangle,
    ) {
        self.content
            .as_widget()
            .draw(&tree.children[0], renderer, theme, style, layout, cursor, viewport);
        if tree.state.downcast_ref::<State>().focused {
            let b = layout.bounds();
            let ring = Rectangle {
                x: b.x - 3.0,
                y: b.y - 3.0,
                width: b.width + 6.0,
                height: b.height + 6.0,
            };
            <iced::Renderer as renderer::Renderer>::fill_quad(
                renderer,
                Quad {
                    bounds: ring,
                    border: Border {
                        color: theme.palette().primary,
                        width: 2.0,
                        radius: border::radius(self.radius + 3.0),
                    },
                    ..Quad::default()
                },
                Color::TRANSPARENT,
            );
        }
    }

    fn overlay<'b>(
        &'b mut self,
        tree: &'b mut Tree,
        layout: Layout<'b>,
        renderer: &iced::Renderer,
        viewport: &Rectangle,
        translation: Vector,
    ) -> Option<overlay::Element<'b, M, Theme, iced::Renderer>> {
        self.content
            .as_widget_mut()
            .overlay(&mut tree.children[0], layout, renderer, viewport, translation)
    }
}

impl<'a, M: Clone + 'a> From<Focus<'a, M>> for Element<'a, M> {
    fn from(focus: Focus<'a, M>) -> Self {
        Element::new(focus)
    }
}

/// The id of a sidebar entry.
pub fn nav_id(panel: &str) -> Id {
    Id::from(format!("nav:{panel}"))
}

/// Focus the widget with `id` (a sidebar entry), nothing else.
pub fn focus_id<T: Send + 'static>(id: Id) -> Task<T> {
    iced::widget::operation::focus(id)
}

/// Tab: the next control inside the panel `scroll`, round to its first
/// after the last (and the first when the focus is elsewhere).
pub fn next<T: Send + 'static>(scroll: &'static str) -> Task<T> {
    step(scroll, true)
}

/// The first control inside the panel `scroll`.
pub fn first<T: Send + 'static>(scroll: &'static str) -> Task<T> {
    step(scroll, false)
}

fn step<T: Send + 'static>(scroll: &'static str, onward: bool) -> Task<T> {
    widget::operate(Count {
        scroll: Id::new(scroll),
        view: None,
        inside: 0,
        current: None,
        onward,
    })
    .discard()
    .chain(reveal(scroll))
}

/// Whether `bounds` lie in the panel's scrollable (not the sidebar).
fn inside(view: Option<Rectangle>, bounds: Rectangle) -> bool {
    view.is_some_and(|v| bounds.x >= v.x && bounds.x < v.x + v.width)
}

/// First pass: how many focusable controls the panel has and which one has
/// the focus; then `Pick` focuses the one to move to.
struct Count {
    scroll: Id,
    view: Option<Rectangle>,
    inside: usize,
    current: Option<usize>,
    onward: bool,
}

impl Operation for Count {
    fn traverse(&mut self, operate: &mut dyn FnMut(&mut dyn Operation)) {
        operate(self);
    }

    fn scrollable(
        &mut self,
        id: Option<&Id>,
        bounds: Rectangle,
        _content_bounds: Rectangle,
        _translation: Vector,
        _state: &mut dyn Scrollable,
    ) {
        if id == Some(&self.scroll) {
            self.view = Some(bounds);
        }
    }

    fn focusable(&mut self, _id: Option<&Id>, bounds: Rectangle, state: &mut dyn Focusable) {
        if inside(self.view, bounds) {
            if state.is_focused() {
                self.current = Some(self.inside);
            }
            self.inside += 1;
        }
    }

    fn finish(&self) -> Outcome<()> {
        if self.inside == 0 {
            return Outcome::None;
        }
        let target = match (self.onward, self.current) {
            (true, Some(i)) => (i + 1) % self.inside,
            _ => 0,
        };
        Outcome::Chain(Box::new(Pick {
            scroll: self.scroll.clone(),
            view: None,
            seen: 0,
            target,
        }))
    }
}

/// Second pass: focus the `target`-th control of the panel, nothing else.
struct Pick {
    scroll: Id,
    view: Option<Rectangle>,
    seen: usize,
    target: usize,
}

impl Operation for Pick {
    fn traverse(&mut self, operate: &mut dyn FnMut(&mut dyn Operation)) {
        operate(self);
    }

    fn scrollable(
        &mut self,
        id: Option<&Id>,
        bounds: Rectangle,
        _content_bounds: Rectangle,
        _translation: Vector,
        _state: &mut dyn Scrollable,
    ) {
        if id == Some(&self.scroll) {
            self.view = Some(bounds);
        }
    }

    fn focusable(&mut self, _id: Option<&Id>, bounds: Rectangle, state: &mut dyn Focusable) {
        if inside(self.view, bounds) && self.seen == self.target {
            state.focus();
        } else {
            state.unfocus();
        }
        if inside(self.view, bounds) {
            self.seen += 1;
        }
    }
}

/// Scroll `scroll` so the focused control is in sight, when it is inside it
/// and out of sight.
fn reveal<T: Send + 'static>(scroll: &'static str) -> Task<T> {
    widget::operate(FindFocused {
        scroll: Id::new(scroll),
        view: None,
        focused: None,
    })
    .then(move |offset: Option<f32>| match offset {
        Some(y) => scroll_to(scroll, AbsoluteOffset { x: None, y: Some(y) }),
        None => Task::none(),
    })
}

/// The scroll offset that puts the focused control in sight, if it is not.
pub fn offset_for(focused: Rectangle, content_top: f32, viewport_height: f32, scrolled: f32) -> Option<f32> {
    let top = focused.y - content_top;
    let bottom = top + focused.height;
    if top < scrolled + MARGIN {
        Some((top - MARGIN).max(0.0))
    } else if bottom > scrolled + viewport_height - MARGIN {
        Some(bottom - viewport_height + MARGIN)
    } else {
        None
    }
}

struct FindFocused {
    scroll: Id,
    /// The scrollable: its bounds, content top and how far it is scrolled.
    view: Option<(Rectangle, f32, f32)>,
    focused: Option<Rectangle>,
}

impl Operation<Option<f32>> for FindFocused {
    fn traverse(&mut self, operate: &mut dyn FnMut(&mut dyn Operation<Option<f32>>)) {
        operate(self);
    }

    fn scrollable(
        &mut self,
        id: Option<&Id>,
        bounds: Rectangle,
        content_bounds: Rectangle,
        translation: Vector,
        _state: &mut dyn Scrollable,
    ) {
        if id == Some(&self.scroll) {
            self.view = Some((bounds, content_bounds.y, translation.y));
        }
    }

    fn focusable(&mut self, _id: Option<&Id>, bounds: Rectangle, state: &mut dyn Focusable) {
        if state.is_focused() {
            self.focused = Some(bounds);
        }
    }

    fn finish(&self) -> Outcome<Option<f32>> {
        Outcome::Some(match (self.view, self.focused) {
            // Only controls inside the panel (not the sidebar) scroll it.
            (Some((view, content_top, scrolled)), Some(f)) if f.x >= view.x && f.x < view.x + view.width => {
                offset_for(f, content_top, view.height, scrolled)
            }
            _ => None,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(y: f32) -> Rectangle {
        Rectangle {
            x: 0.0,
            y,
            width: 100.0,
            height: 30.0,
        }
    }

    #[test]
    fn scrolls_only_when_out_of_sight() {
        // Content starts at 0, a 600 high view scrolled by 0.
        assert_eq!(offset_for(at(200.0), 0.0, 600.0, 0.0), None);
        assert_eq!(offset_for(at(900.0), 0.0, 600.0, 0.0), Some(390.0));
        assert_eq!(offset_for(at(100.0), 0.0, 600.0, 400.0), Some(40.0));
    }
}
