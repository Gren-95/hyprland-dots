//! Colours and widget styles, taken from config/quickshell/Theme.qml so the
//! app looks like the shell.

use iced::widget::{button, container, progress_bar, text_input};
use iced::{Background, Border, Color, Theme, border};

pub const BG: Color = rgb(0x1c1917);
pub const BG_ALT: Color = rgb(0x292524);
pub const BG_HOVER: Color = rgb(0x231f1d);
pub const BG_ACTIVE: Color = rgb(0x332e2b);
pub const BG_DEEP: Color = rgb(0x16130f);
pub const BORDER: Color = rgb(0x3a3633);
pub const BORDER_SUBTLE: Color = rgb(0x2a2624);
pub const FG: Color = rgb(0xfafaf9);
pub const FG_MUTED: Color = rgb(0xd6d3d1);
pub const MUTED_DEEP: Color = rgb(0x78716c);
pub const RED: Color = rgb(0xff4d5e);
pub const GREEN: Color = rgb(0x2ee59d);
pub const YELLOW: Color = rgb(0xffc531);

/// Text font: GNOME's interface font (adwaita-sans-fonts).
pub const FONT: iced::Font = iced::Font::with_name("Adwaita Sans");
/// Headings: the text font, bold.
pub const FONT_BOLD: iced::Font = iced::Font {
    weight: iced::font::Weight::Bold,
    ..FONT
};
pub const RADIUS: f32 = 10.0;

/// 0xrrggbb to a colour.
pub const fn from_hex(hex: u32) -> Color {
    rgb(hex)
}

const fn rgb(hex: u32) -> Color {
    Color::from_rgb(
        ((hex >> 16) & 0xff) as f32 / 255.0,
        ((hex >> 8) & 0xff) as f32 / 255.0,
        (hex & 0xff) as f32 / 255.0,
    )
}

/// The shell's accent colours by `accent-primary` name; "auto" (taken from
/// the wallpaper) uses the cached `accent-auto-hex` when there is one.
pub fn accent(name: &str, auto_hex: &str) -> Color {
    match name {
        "blue" => rgb(0x4c9aff),
        "green" => GREEN,
        "red" => RED,
        "yellow" => YELLOW,
        "purple" => rgb(0xb57bff),
        "pink" => rgb(0xff6fb5),
        "teal" => rgb(0x2ee6d6),
        "slate" => rgb(0x94a3b8),
        "auto" => parse_hex(auto_hex).unwrap_or(rgb(0xff7a1a)),
        _ => rgb(0xff7a1a),
    }
}

/// "#rrggbb" to a colour.
fn parse_hex(hex: &str) -> Option<Color> {
    let digits = hex.trim().strip_prefix('#')?;
    if digits.len() != 6 {
        return None;
    }
    u32::from_str_radix(digits, 16).ok().map(rgb)
}

pub fn theme(accent: Color) -> Theme {
    Theme::custom(
        "Dots",
        iced::theme::Palette {
            background: BG,
            text: FG,
            primary: accent,
            success: GREEN,
            warning: YELLOW,
            danger: RED,
        },
    )
}

/// The sidebar is a darker pane than the panel beside it.
pub fn sidebar(_: &Theme) -> container::Style {
    container::Style {
        background: Some(Background::Color(BG_DEEP)),
        ..container::Style::default()
    }
}

/// Text fields (search and entries): a rounded well, outlined in the accent when
/// focused.
pub fn field(theme: &Theme, status: text_input::Status) -> text_input::Style {
    field_at(Joint::Alone)(theme, status)
}

/// A text field that is part of an input group.
pub fn field_at(joint: Joint) -> impl Fn(&Theme, text_input::Status) -> text_input::Style {
    move |theme, status| field_style(theme, status, joint)
}

fn field_style(theme: &Theme, status: text_input::Status, joint: Joint) -> text_input::Style {
    let accent = theme.palette().primary;
    let outline = match status {
        text_input::Status::Focused { .. } => accent,
        text_input::Status::Hovered => BORDER,
        _ => BORDER_SUBTLE,
    };
    text_input::Style {
        background: Background::Color(BG_HOVER),
        border: Border {
            color: outline,
            width: 1.0,
            radius: joint.radius(8.0),
        },
        icon: MUTED_DEEP,
        placeholder: MUTED_DEEP,
        value: FG,
        selection: Color { a: 0.35, ..accent },
    }
}

/// A setting row a search result pointed at: accent outline and tint.
pub fn highlight(theme: &Theme) -> container::Style {
    let accent = theme.palette().primary;
    container::Style {
        background: Some(Background::Color(Color { a: 0.12, ..accent })),
        border: Border {
            color: accent,
            width: 1.5,
            radius: border::radius(8.0),
        },
        ..container::Style::default()
    }
}

/// What a small action button does, for its colour.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Normal,
    /// The main thing to do (connect, pair): accent.
    Primary,
    /// Removes something (forget): red text.
    Danger,
}

pub fn action(kind: Action) -> impl Fn(&Theme, button::Status) -> button::Style {
    action_at(kind, Joint::Alone)
}

/// Where a control sits in a group of joined controls (Bootstrap's button
/// and input groups): only the group's outer corners are rounded.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Joint {
    Alone,
    First,
    Middle,
    Last,
}

impl Joint {
    /// The joint of item `index` in a group of `count`.
    pub fn of(index: usize, count: usize) -> Joint {
        match (index, count) {
            (_, 0 | 1) => Joint::Alone,
            (0, _) => Joint::First,
            (i, n) if i + 1 == n => Joint::Last,
            _ => Joint::Middle,
        }
    }

    pub fn radius(self, r: f32) -> border::Radius {
        let (left, right) = match self {
            Joint::Alone => (r, r),
            Joint::First => (r, 0.0),
            Joint::Middle => (0.0, 0.0),
            Joint::Last => (0.0, r),
        };
        border::Radius {
            top_left: left,
            bottom_left: left,
            top_right: right,
            bottom_right: right,
        }
    }
}

/// An action button that is part of a group.
pub fn action_at(kind: Action, joint: Joint) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |theme, status| {
        let accent = theme.palette().primary;
        let hovered = matches!(status, button::Status::Hovered | button::Status::Pressed);
        let (background, text_color) = match (kind, status) {
            (_, button::Status::Disabled) => (BG_HOVER, MUTED_DEEP),
            (Action::Primary, _) => (
                if hovered { Color { a: 0.85, ..accent } } else { accent },
                rgb(0x0c0a09),
            ),
            (Action::Danger, _) => (if hovered { BG_ACTIVE } else { BG_HOVER }, RED),
            (Action::Normal, _) => (if hovered { BG_ACTIVE } else { BG_HOVER }, FG_MUTED),
        };
        button::Style {
            background: Some(Background::Color(background)),
            text_color,
            border: Border {
                color: BORDER_SUBTLE,
                width: 1.0,
                radius: joint.radius(7.0),
            },
            ..button::Style::default()
        }
    }
}

/// One option of a segmented control: the selected one filled with the
/// accent, the others like a plain button.
pub fn segment(selected: bool, joint: Joint) -> impl Fn(&Theme, button::Status) -> button::Style {
    action_at(if selected { Action::Primary } else { Action::Normal }, joint)
}

/// A pill: one item of a list setting, with its remove button inside.
pub fn pill(theme: &Theme) -> container::Style {
    let accent = theme.palette().primary;
    container::Style {
        background: Some(Background::Color(Color { a: 0.14, ..accent })),
        border: Border {
            color: Color { a: 0.5, ..accent },
            width: 1.0,
            radius: border::radius(12.0),
        },
        text_color: Some(FG),
        ..container::Style::default()
    }
}

/// A filter pill: the picked one filled with the accent.
pub fn filter_pill(picked: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |theme, status| {
        let accent = theme.palette().primary;
        let hovered = matches!(status, button::Status::Hovered | button::Status::Pressed);
        let (background, text_color, outline) = if picked {
            (accent, rgb(0x0c0a09), accent)
        } else {
            (if hovered { BG_ACTIVE } else { BG_HOVER }, FG_MUTED, BORDER_SUBTLE)
        };
        button::Style {
            background: Some(Background::Color(background)),
            text_color,
            border: Border {
                color: outline,
                width: 1.0,
                radius: border::radius(12.0),
            },
            ..button::Style::default()
        }
    }
}

/// The × inside a pill.
pub fn pill_close(_: &Theme, status: button::Status) -> button::Style {
    let hovered = matches!(status, button::Status::Hovered | button::Status::Pressed);
    button::Style {
        background: None,
        text_color: if hovered { RED } else { FG_MUTED },
        ..button::Style::default()
    }
}

/// A key drawn as a keycap in a shortcut.
pub fn keycap(_: &Theme) -> container::Style {
    container::Style {
        background: Some(Background::Color(BG_ACTIVE)),
        border: Border {
            color: BORDER,
            width: 1.0,
            radius: border::radius(5.0),
        },
        ..container::Style::default()
    }
}

/// A round colour swatch.
pub fn dot(color: Color) -> container::Style {
    container::Style {
        background: Some(Background::Color(color)),
        border: Border {
            radius: border::radius(6.0),
            ..Border::default()
        },
        ..container::Style::default()
    }
}

/// The line between the sidebar and the panel.
pub fn divider(_: &Theme) -> container::Style {
    container::Style {
        background: Some(Background::Color(BORDER)),
        ..container::Style::default()
    }
}

pub fn card(_: &Theme) -> container::Style {
    container::Style {
        background: Some(Background::Color(BG_ALT)),
        border: Border {
            color: BORDER_SUBTLE,
            width: 1.0,
            radius: border::radius(RADIUS),
        },
        ..container::Style::default()
    }
}

/// The About header: a card washed with the accent from the left.
pub fn hero(theme: &Theme) -> container::Style {
    let accent = theme.palette().primary;
    let wash = iced::gradient::Linear::new(iced::Degrees(90.0))
        .add_stop(0.0, Color { a: 0.22, ..accent })
        .add_stop(1.0, BG_ALT);
    container::Style {
        background: Some(Background::Gradient(wash.into())),
        border: Border {
            color: Color { a: 0.35, ..accent },
            width: 1.0,
            radius: border::radius(RADIUS + 4.0),
        },
        ..container::Style::default()
    }
}

/// A usage meter: accent, yellow past 80 %, red past 90 %.
pub fn meter(share: f32) -> impl Fn(&Theme) -> progress_bar::Style {
    move |theme| {
        let bar = if share >= 0.9 {
            RED
        } else if share >= 0.8 {
            YELLOW
        } else {
            theme.palette().primary
        };
        progress_bar::Style {
            background: Background::Color(BG_ACTIVE),
            bar: Background::Color(bar),
            border: Border {
                radius: border::radius(3.0),
                ..Border::default()
            },
        }
    }
}

/// A sidebar entry; the selected one gets the accent rail colour as text.
pub fn nav(selected: bool) -> impl Fn(&Theme, button::Status) -> button::Style {
    move |theme, status| {
        let accent = theme.palette().primary;
        let background = match (selected, status) {
            (true, _) => BG_ACTIVE,
            (false, button::Status::Hovered | button::Status::Pressed) => BG_HOVER,
            _ => Color::TRANSPARENT,
        };
        button::Style {
            background: Some(Background::Color(background)),
            text_color: if selected { accent } else { FG_MUTED },
            border: Border {
                radius: border::radius(8.0),
                ..Border::default()
            },
            ..button::Style::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accent_follows_the_shell() {
        assert_eq!(accent("orange", ""), rgb(0xff7a1a));
        assert_eq!(accent("auto", "#4c9aff"), rgb(0x4c9aff));
        assert_eq!(accent("auto", "nonsense"), rgb(0xff7a1a));
    }
}

#[cfg(test)]
mod joint_tests {
    use super::*;

    #[test]
    fn rounds_only_outer_corners() {
        assert_eq!(Joint::of(0, 1), Joint::Alone);
        assert_eq!(Joint::of(0, 3), Joint::First);
        assert_eq!(Joint::of(1, 3), Joint::Middle);
        assert_eq!(Joint::of(2, 3), Joint::Last);
        let first = Joint::First.radius(8.0);
        assert_eq!((first.top_left, first.top_right), (8.0, 0.0));
        let last = Joint::Last.radius(8.0);
        assert_eq!((last.bottom_left, last.bottom_right), (0.0, 8.0));
    }
}
