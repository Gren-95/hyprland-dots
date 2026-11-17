//! Colours and widget styles, taken from config/quickshell/Theme.qml so the
//! app looks like the shell.

use iced::widget::{button, container, text_input};
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
/// Sidebar glyphs come from the shell's Nerd Font.
pub const GLYPH_FONT: iced::Font = iced::Font::with_name("Iosevka Nerd Font");
pub const RADIUS: f32 = 10.0;

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
            radius: border::radius(8.0),
        },
        icon: MUTED_DEEP,
        placeholder: MUTED_DEEP,
        value: FG,
        selection: Color { a: 0.35, ..accent },
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
