-- Window rules.

-- Zoom menu window: keep focused
hl.window_rule({
    name  = "zoom-menu-stays-focused",
    match = { class = "zoom", title = "(menu window)" },
    stay_focused = true,
})

-- Suppress maximize events for everything
hl.window_rule({
    name  = "suppress-maximize",
    match = { class = ".*" },
    suppress_event = "maximize",
})

-- Prevent focus on empty floating non-fullscreen non-pinned XWayland windows
hl.window_rule({
    name  = "no-focus-empty-xwayland",
    match = { class = "^$", title = "^$" },
    no_focus = true,
})

-- Picture-in-Picture: float, pin to all workspaces, don't steal focus,
-- default 16:9 480x270, no blur.
local pipMatch = { title = "^(Picture-in-Picture|PiP)$" }
hl.window_rule({ name = "pip-float",        match = pipMatch, float = true })
hl.window_rule({ name = "pip-pin",          match = pipMatch, pin = true })
hl.window_rule({ name = "pip-no-focus",     match = pipMatch, no_initial_focus = true })
hl.window_rule({ name = "pip-size",         match = pipMatch, size = "480 270" })
hl.window_rule({ name = "pip-no-blur",      match = pipMatch, no_blur = true })

-- XWayland video bridge
local xvbMatch = { class = "^(xwaylandvideobridge)$" }
hl.window_rule({ name = "xvb-opacity",      match = xvbMatch, opacity = { value = 0.0, override = true } })
hl.window_rule({ name = "xvb-no-anim",      match = xvbMatch, no_anim = true })
hl.window_rule({ name = "xvb-no-focus",     match = xvbMatch, no_initial_focus = true })
hl.window_rule({ name = "xvb-max-size",     match = xvbMatch, max_size = "1 1" })
hl.window_rule({ name = "xvb-no-blur",      match = xvbMatch, no_blur = true })
hl.window_rule({ name = "xvb-no-focus2",    match = xvbMatch, no_focus = true })

-- GNOME Calendar — small floating pinned window
local calMatch = { title = "^(Calendar)$" }
hl.window_rule({ name = "cal-float", match = calMatch, float = true })
hl.window_rule({ name = "cal-pin",   match = calMatch, pin = true })
hl.window_rule({ name = "cal-size",  match = calMatch, size = "400 400" })
hl.window_rule({ name = "cal-move",  match = calMatch, move = "39% 12%" })

-- GNOME apps: rounder corners, no client-side decorations
hl.window_rule({ name = "gnome-round",    match = { class = "^(org\\.gnome\\." }, rounding = 12 })
hl.window_rule({ name = "gnome-no-deco",  match = { class = "^(org\\.gnome\\." }, decorate = false })

-- Force tiled
hl.window_rule({ name = "gcc-tile",        match = { class = "^(gnome-control-center)$" },  tile = true })
hl.window_rule({ name = "nm-tile",         match = { class = "^(nm-connection-editor)$" },  tile = true })

-- Force floating
hl.window_rule({ name = "blueman-float",   match = { class = "^(blueman-manager)$" },       float = true })
hl.window_rule({ name = "portal-float",    match = { class = "^(xdg-desktop-portal)$" },    float = true })
hl.window_rule({ name = "portal-center",   match = { class = "^(xdg-desktop-portal)$" },    center = true })
hl.window_rule({ name = "zoom-float",      match = { class = "^(zoom)$" },                  float = true })

-- Decorations
hl.window_rule({ name = "zen-no-deco",     match = { class = "^(zen)$" },                   decorate = false })

-- Steam games (Proton-wrapped) — force fullscreen so they don't open
-- small / windowed when the game itself doesn't apply its mode.
hl.window_rule({ name = "steam-fullscreen", match = { class = "^(steam_app_.*)$" },         fullscreen = true })

-- Gaming: lower input lag inside fullscreen apps. `immediate on` requires
-- general:allow_tearing = true (set in general.lua); tearing only happens
-- inside fullscreen apps, the desktop stays vsynced.
hl.window_rule({ name = "fullscreen-immediate", match = { fullscreen = 1 },                 immediate = true })
