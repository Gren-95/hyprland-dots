//! A symbol for every store setting's row, by setting file. The test makes
//! sure no setting is left without one.

use crate::ui::Icon;
use lucide_iced::bytes as ico;

const ICONS: &[(&str, Icon)] = &[
    // Sound
    ("alert-volume", ico::BELL_RING),
    ("volume-step", ico::VOLUME_1),
    ("brightness-step", ico::SUN_MEDIUM),
    ("max-volume", ico::VOLUME_2),
    ("osd-volume", ico::PANEL_BOTTOM),
    ("osd-duration", ico::TIMER),
    ("osd-bottom-margin", ico::ARROW_UP_FROM_LINE),
    // Appearance
    ("accent-primary", ico::PALETTE),
    ("accent-everywhere", ico::PAINTBRUSH),
    ("color-scheme", ico::SUN_MOON),
    ("font-family", ico::TYPE),
    ("app-font", ico::A_LARGE_SMALL),
    ("radius-scale", ico::SQUARE_ROUND_CORNER),
    ("wallpaper-dir", ico::FOLDER_OPEN),
    ("wallpaper-random-login", ico::SHUFFLE),
    ("lock-background", ico::LOCK),
    ("lock-picture", ico::IMAGE),
    // Displays
    ("night-temperature", ico::THERMOMETER),
    ("night-schedule", ico::CALENDAR_CLOCK),
    ("night-from", ico::SUNSET),
    ("night-to", ico::SUNRISE),
    // Accessibility
    ("font-scale", ico::A_LARGE_SMALL),
    ("high-contrast", ico::CONTRAST),
    ("cursor-size", ico::MOUSE_POINTER_2),
    ("cursor-zoom", ico::ZOOM_IN),
    ("animations", ico::SPARKLES),
    ("anim-scale", ico::GAUGE),
    // Windows
    ("border-colour", ico::SQUARE),
    ("border-gradient", ico::BLEND),
    ("border-angle", ico::ROTATE_CW),
    // Bar
    ("bar-height", ico::MOVE_VERTICAL),
    ("bar-opacity", ico::BLEND),
    ("window-title-width", ico::TEXT_CURSOR_INPUT),
    ("workspace-glyphs", ico::LAYOUT_GRID),
    ("workspace-window-icons", ico::APP_WINDOW),
    ("bar-wheel-action", ico::MOUSE),
    // Date & time
    ("clock-24h", ico::CLOCK),
    ("clock-seconds", ico::TIMER),
    ("clock-date-format", ico::CALENDAR),
    ("week-start-monday", ico::CALENDAR_DAYS),
    ("calendar-fetch-interval", ico::REFRESH_CW),
    ("weather-location", ico::MAP_PIN),
    ("weather-fahrenheit", ico::THERMOMETER),
    // Notifications
    ("dnd", ico::BELL_OFF),
    ("dnd-schedule", ico::CALENDAR_CLOCK),
    ("dnd-from", ico::MOON),
    ("dnd-to", ico::SUN),
    ("toast-position", ico::LAYOUT_TEMPLATE),
    ("toast-timeout", ico::TIMER),
    ("toast-max", ico::LAYERS),
    ("toast-width", ico::MOVE_HORIZONTAL),
    ("notif-sounds", ico::VOLUME_2),
    ("notif-history-cap", ico::LIST_CLOCK),
    ("notif-group-by-app", ico::GROUP),
    ("notif-auto-expire", ico::TIMER_OFF),
    ("notif-auto-expire-rules.json", ico::LIST_FILTER),
    ("notif-auto-expire-delay", ico::HOURGLASS),
    ("event-toasts.json", ico::ZAP),
    // Launcher & clipboard
    ("spotlight-cap", ico::LIST),
    ("spotlight-calc", ico::LAYOUT_GRID),
    ("clipboard-thumbs", ico::IMAGE),
    // Screenshots & recording
    ("shot-dir", ico::FOLDER_OPEN),
    ("shot-format", ico::FILE_IMAGE),
    ("shot-cursor", ico::MOUSE_POINTER),
    ("record-dir", ico::FOLDER_OPEN),
    ("record-container", ico::FILE_VIDEO_CAMERA),
    ("record-fps", ico::GAUGE),
    ("record-quality", ico::SPARKLES),
    ("record-codec", ico::BINARY),
    ("record-cursor", ico::MOUSE_POINTER),
    ("record-audio", ico::MIC),
    // System monitor
    ("sysmon-interval", ico::TIMER),
    ("sysmon-show-cpu", ico::CPU),
    // Gaming
    ("gamemode-effects", ico::GAMEPAD_2),
    ("gamemode-performance", ico::GAUGE),
    ("gamemode-syncs", ico::REFRESH_CW_OFF),
    ("gamemode-feral", ico::ZAP),
    ("game-launcher-games", ico::LIBRARY),
    // Privacy
    ("indicator-camera", ico::CIRCLE_DOT),
    ("clipboard-max-items", ico::CLIPBOARD_LIST),
    // Sync
    ("immich-folder", ico::IMAGES),
    ("jellyfin-url", ico::SERVER),
    ("jellyfin-folder", ico::LIST_MUSIC),
    // Power & lock
    ("power-on-ac", ico::PLUG),
    ("power-on-battery", ico::BATTERY_MEDIUM),
    ("power-saver-below", ico::LEAF),
    ("battery-critical-pct", ico::BATTERY_EXCLAMATION_POINT),
    ("battery-low-pct", ico::BATTERY_LOW),
    ("battery-warn-pct", ico::BATTERY_LOW),
    ("battery-critical-action", ico::POWER),
    ("idle-stay-awake", ico::COFFEE),
    ("idle-inhibit-media", ico::EYE),
    ("lid-close-action", ico::LAPTOP),
    ("lock-show-media", ico::LAYOUT_LIST),
];

/// Hyprland options on the Windows, Mouse and Gaming panels.
const OPTION_ICONS: &[(&str, Icon)] = &[
    ("general:gaps_in", ico::COLUMNS_2),
    ("general:gaps_out", ico::FRAME),
    ("general:border_size", ico::SQUARE),
    ("decoration:rounding", ico::SQUARE_ROUND_CORNER),
    ("animations:enabled", ico::SPARKLES),
    ("decoration:blur:enabled", ico::DROPLETS),
    ("decoration:shadow:enabled", ico::LAYERS),
    ("decoration:inactive_opacity", ico::BLEND),
    ("general:layout", ico::LAYOUT_DASHBOARD),
    ("input:follow_mouse", ico::MOUSE_POINTER_CLICK),
    ("general:resize_on_border", ico::MOVE_DIAGONAL_2),
    ("misc:focus_on_activate", ico::SCAN_EYE),
    ("input:sensitivity", ico::GAUGE),
    ("input:accel_profile", ico::TRENDING_UP),
    ("input:left_handed", ico::HAND),
    ("input:natural_scroll", ico::ARROW_DOWN_UP),
    ("input:scroll_factor", ico::MOUSE),
    ("input:touchpad:tap_to_click", ico::POINTER),
    ("input:touchpad:natural_scroll", ico::ARROW_DOWN_UP),
    ("input:touchpad:disable_while_typing", ico::KEYBOARD_OFF),
    ("input:touchpad:clickfinger_behavior", ico::MOUSE_POINTER_CLICK),
    ("input:touchpad:middle_button_emulation", ico::MOUSE),
    ("input:touchpad:scroll_factor", ico::ARROW_DOWN_UP),
    ("gestures:workspace_swipe_invert", ico::ARROW_LEFT_RIGHT),
    ("gestures:workspace_swipe_distance", ico::MOVE_HORIZONTAL),
    ("gestures:workspace_swipe_forever", ico::INFINITY),
    ("misc:vrr", ico::MONITOR_CHECK),
    ("general:allow_tearing", ico::ZAP),
    ("render:direct_scanout", ico::MONITOR_UP),
];

/// A Hyprland option row's symbol.
pub fn of_option(option: &str) -> Option<Icon> {
    OPTION_ICONS.iter().find(|(o, _)| *o == option).map(|(_, i)| *i)
}

/// A setting row's symbol.
pub fn of(file: &str) -> Option<Icon> {
    ICONS.iter().find(|(f, _)| *f == file).map(|(_, i)| *i)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_setting_has_a_symbol() {
        let missing: Vec<&str> = crate::schema::all_settings()
            .map(|s| s.file)
            .filter(|f| of(f).is_none())
            .collect();
        assert!(missing.is_empty(), "settings without a symbol: {missing:?}");
        let options: Vec<&str> = [crate::windows::SECTIONS, crate::mouse::SECTIONS, crate::gaming::DISPLAY]
            .iter()
            .flat_map(|sections| sections.iter())
            .flat_map(|s| s.rows.iter())
            .map(|r| r.option())
            .filter(|o| of_option(o).is_none())
            .collect();
        assert!(options.is_empty(), "options without a symbol: {options:?}");
    }
}
