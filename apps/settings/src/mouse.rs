//! Mouse & Touchpad panel: Hyprland input options (hyprpage.rs).

use crate::hyprpage::{Format, Row, Section};

pub const SECTIONS: &[Section] = &[
    Section {
        title: "Mouse",
        rows: &[
            Row::Slider {
                option: "input:sensitivity",
                label: "Pointer speed",
                help: "Slower or faster than the device's own speed",
                min: -1.0,
                max: 1.0,
                step: 0.05,
                format: Format::Signed,
                int: false,
            },
            Row::Choice {
                option: "input:accel_profile",
                label: "Acceleration",
                help: "Off leaves it to the device; flat moves the pointer by distance only; adaptive speeds it up with fast moves",
                options: &[("", "Off"), ("flat", "Flat"), ("adaptive", "Adaptive")],
            },
            Row::Toggle {
                option: "input:left_handed",
                label: "Left-handed",
                help: "Swap the left and right buttons",
            },
            Row::Toggle {
                option: "input:natural_scroll",
                label: "Natural scrolling",
                help: "Content moves with the wheel, like on a phone",
            },
            Row::Slider {
                option: "input:scroll_factor",
                label: "Scroll speed",
                help: "How far one wheel step scrolls",
                min: 0.2,
                max: 3.0,
                step: 0.1,
                format: Format::Times,
                int: false,
            },
        ],
    },
    Section {
        title: "Touchpad",
        rows: &[
            Row::Toggle {
                option: "input:touchpad:tap_to_click",
                label: "Tap to click",
                help: "A tap is a click",
            },
            Row::Toggle {
                option: "input:touchpad:natural_scroll",
                label: "Natural scrolling",
                help: "Content moves with your fingers",
            },
            Row::Toggle {
                option: "input:touchpad:disable_while_typing",
                label: "Off while typing",
                help: "Ignore the touchpad while keys are pressed",
            },
            Row::Binary {
                option: "input:touchpad:clickfinger_behavior",
                label: "Right click",
                help: "Click the bottom-right corner, or click with two fingers",
                off: "Corner",
                on: "Two fingers",
            },
            Row::Toggle {
                option: "input:touchpad:middle_button_emulation",
                label: "Middle click",
                help: "Clicking left and right together is a middle click",
            },
            Row::Slider {
                option: "input:touchpad:scroll_factor",
                label: "Scroll speed",
                help: "How far a two-finger swipe scrolls",
                min: 0.2,
                max: 3.0,
                step: 0.1,
                format: Format::Times,
                int: false,
            },
        ],
    },
    Section {
        title: "Gestures",
        rows: &[
            Row::Toggle {
                option: "gestures:workspace_swipe_invert",
                label: "Invert workspace swipe",
                help: "Three fingers left goes to the next workspace",
            },
            Row::Slider {
                option: "gestures:workspace_swipe_distance",
                label: "Swipe distance",
                help: "How far to swipe for one workspace",
                min: 100.0,
                max: 1500.0,
                step: 50.0,
                format: Format::Unit("px"),
                int: true,
            },
            Row::Toggle {
                option: "gestures:workspace_swipe_forever",
                label: "Swipe past several workspaces",
                help: "Keep moving while the fingers keep swiping",
            },
        ],
    },
];
