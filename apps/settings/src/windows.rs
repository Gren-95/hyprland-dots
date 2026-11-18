//! Windows panel: Hyprland's look and behaviour of windows (hyprpage.rs).
//! Saved in settings.lua, which loads after HyprMod's hyprland-gui.lua, so
//! these win over it.

use crate::hyprpage::{Format, Row, Section};

pub const SECTIONS: &[Section] = &[
    Section {
        title: "Spacing and borders",
        rows: &[
            Row::Slider {
                option: "general:gaps_in",
                label: "Gaps between windows",
                help: "Space between tiled windows",
                min: 0.0,
                max: 30.0,
                step: 1.0,
                format: Format::Unit("px"),
                int: true,
            },
            Row::Slider {
                option: "general:gaps_out",
                label: "Gaps at the screen edge",
                help: "Space between windows and the screen edge",
                min: 0.0,
                max: 40.0,
                step: 1.0,
                format: Format::Unit("px"),
                int: true,
            },
            Row::Slider {
                option: "general:border_size",
                label: "Border width",
                help: "The coloured border around windows",
                min: 0.0,
                max: 8.0,
                step: 1.0,
                format: Format::Unit("px"),
                int: true,
            },
            Row::Slider {
                option: "decoration:rounding",
                label: "Corner rounding",
                help: "Radius of window corners",
                min: 0.0,
                max: 30.0,
                step: 1.0,
                format: Format::Unit("px"),
                int: true,
            },
        ],
    },
    Section {
        title: "Effects",
        rows: &[
            Row::Toggle {
                option: "animations:enabled",
                label: "Animations",
                help: "Animate opening, closing and switching",
            },
            Row::Toggle {
                option: "decoration:blur:enabled",
                label: "Blur",
                help: "Blur behind see-through windows and panels",
            },
            Row::Toggle {
                option: "decoration:shadow:enabled",
                label: "Shadows",
                help: "A shadow under windows",
            },
            Row::Slider {
                option: "decoration:inactive_opacity",
                label: "Unfocused window opacity",
                help: "How see-through windows without focus are",
                min: 0.5,
                max: 1.0,
                step: 0.05,
                format: Format::Percent,
                int: false,
            },
        ],
    },
    Section {
        title: "Behaviour",
        rows: &[
            Row::Choice {
                option: "general:layout",
                label: "Tiling",
                help: "Dwindle splits the focused window; master keeps one big window",
                options: &[("dwindle", "Dwindle"), ("master", "Master")],
            },
            Row::IntChoice {
                option: "input:follow_mouse",
                label: "Focus follows mouse",
                help: "When moving the mouse over a window focuses it",
                options: &[(0, "Never"), (1, "Always"), (2, "Keyboard stays"), (3, "Only on click")],
            },
            Row::Toggle {
                option: "general:resize_on_border",
                label: "Resize by the border",
                help: "Drag a window's border to resize it",
            },
            Row::Toggle {
                option: "misc:focus_on_activate",
                label: "Apps can take focus",
                help: "Focus a window when its app asks for attention",
            },
        ],
    },
];
