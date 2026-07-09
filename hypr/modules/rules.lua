-- ## WINDOW RULES ###

-- Zoom menu window
hl.window_rule({
    match = {
        class = "zoom",
        title = "(menu window)",
    },
    stay_focused = true,
})

-- Suppress maximize event for all windows
hl.window_rule({
    match = {
        class = ".*",
    },
    suppress_event = "= maximize",
})

-- Prevent focus on empty, floating, non-fullscreen, non-pinned XWayland windows
hl.window_rule({
    match = {
        class = "^$",
        title = "^$",
    },
    no_focus = true,
})

-- (slurp window rules removed — slurp runs as a wlr_layer_shell surface,

-- not a toplevel, so windowrule matchers never matched. The overlay is

-- managed by slurp itself.)

-- Picture-in-Picture: float, pin to all workspaces, don't steal focus,

-- default 16:9 480x270, no blur. Position left to Firefox / the user

-- (the move rule was overridden anyway).
hl.window_rule({
    match = {
        title = "^(Picture-in-Picture|PiP)$",
    },
    float = true,
})
hl.window_rule({
    match = {
        title = "^(Picture-in-Picture|PiP)$",
    },
    pin = true,
})
hl.window_rule({
    match = {
        title = "^(Picture-in-Picture|PiP)$",
    },
    no_initial_focus = true,
})
hl.window_rule({
    match = {
        title = "^(Picture-in-Picture|PiP)$",
    },
    size = "480 270",
})
hl.window_rule({
    match = {
        title = "^(Picture-in-Picture|PiP)$",
    },
    no_blur = true,
})

-- XWayland video bridge
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    opacity = "0.0 override",
})
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    no_anim = true,
})
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    no_initial_focus = true,
})
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    max_size = "1 1",
})
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    no_blur = true,
})
hl.window_rule({
    match = {
        class = "^(xwaylandvideobridge)$",
    },
    no_focus = true,
})

-- GNOME Calendar
hl.window_rule({
    match = {
        title = "^(Calendar)$",
    },
    float = true,
})
hl.window_rule({
    match = {
        title = "^(Calendar)$",
    },
    pin = true,
})
hl.window_rule({
    match = {
        title = "^(Calendar)$",
    },
    size = "400 400",
})
hl.window_rule({
    match = {
        title = "^(Calendar)$",
    },
    move = "39% 12%",
})

-- GNOME apps
hl.window_rule({
    match = {
        class = "^(org\\.gnome\\.)",
    },
    rounding = 12,
})
hl.window_rule({
    match = {
        class = "^(org\\.gnome\\.)",
    },
    decorate = false,
})

-- Force tiled
hl.window_rule({
    match = {
        class = "^(gnome-control-center)$",
    },
    tile = true,
})
hl.window_rule({
    match = {
        class = "^(nm-connection-editor)$",
    },
    tile = true,
})

-- Force floating
hl.window_rule({
    match = {
        class = "^(blueman-manager)$",
    },
    float = true,
})
hl.window_rule({
    match = {
        class = "^(xdg-desktop-portal)$",
    },
    float = true,
})
hl.window_rule({
    match = {
        class = "^(xdg-desktop-portal)$",
    },
    center = 1,
})
hl.window_rule({
    match = {
        class = "^(zoom)$",
    },
    float = true,
})

-- Proton/Wine desktop tools (MO2, BodySlide, xEdit/SSEEdit, Creation Kit, etc.)

-- run as native-Wayland toplevels (class = the .exe name). Under dwindle they

-- tile and squish the layout — and so do their modal dialogs/popups. Float

-- every wine ".exe" window so tools and their popups appear at natural size.

-- The actual game is class steam_app_* (fullscreen rule below), so it's not

-- matched here; the skyrim*.exe fullscreen safety covers Proton-Wayland naming.
hl.window_rule({
    match = {
        class = ".*\\.exe$",
    },
    float = true,
})
hl.window_rule({
    match = {
        class = ".*\\.exe$",
    },
    center = 1,
})

-- Some wine dialogs (e.g. BodySlide's "Batch Build" / "Processing Outfits")

-- map at a near-zero size then resize, and Hyprland keeps the tiny float size,

-- so they open as a squished sliver. Floor their size so they can't collapse.
hl.window_rule({
    match = {
        class = ".*\\.exe$",
    },
    min_size = "520 420",
})
hl.window_rule({
    match = {
        class = "^(skyrimse\\.exe|skyrimselauncher\\.exe|skyrimvr\\.exe)$",
    },
    fullscreen = true,
})

-- Decorations
hl.window_rule({
    match = {
        class = "^(zen)$",
    },
    decorate = false,
})

-- Steam games (Proton-wrapped) — force fullscreen so they don't open

-- small / windowed when the game itself doesn't apply its mode.
hl.window_rule({
    match = {
        class = "^(steam_app_.*)$",
    },
    fullscreen = true,
})

-- Gaming: lower input lag inside fullscreen apps. `immediate on` requires

-- general:allow_tearing = true (set in general.conf); tearing only happens

-- inside fullscreen apps, the desktop stays vsynced.

-- (Hyprland 0.55.1 doesn't accept `idleinhibit` as a window rule — Wayland

-- fullscreen apps that need to prevent sleep should request the

-- org.freedesktop.ScreenSaver inhibit themselves, as media-inhibit.sh does

-- for media playback.)
hl.window_rule({
    match = {
        fullscreen = 1,
    },
    immediate = true,
})
