hl.config({
    gestures = {
        workspace_swipe_distance = 500,
        workspace_swipe_invert = true,
        workspace_swipe_min_speed_to_force = 30,
        workspace_swipe_cancel_ratio = 0.5,
        workspace_swipe_forever = true,
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- 4-finger up = always fullscreen, down = always windowed. Using the

-- toggle `fullscreen` action caused Overwatch (and other XWayland

-- games) to go transparent / minimise when already fullscreen because

-- the gesture would un-fullscreen them. `dispatcher, fullscreenstate, N`

-- explicitly sets the state and is idempotent.
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 2, client = -1 }))
    end,
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = -1 }))
    end,
})
hl.gesture({
    fingers = 2,
    direction = "pinch",
    mods = "ALT",
    action = "cursorZoom",
    zoom_level = 1,
    mode = "live",
})

-- gesture = 3, up, close

-- 3-finger up = hyprexpo overview, 3-finger down = cancel. Plugin is a local
-- build (hyprpm headers mismatch on Fedora); rebuild from ~/.local/src/hyprexpo
-- after Hyprland updates. hl.plugin.load is declarative and must stay
-- unguarded; the loaded check only gates calls into the plugin API.
hl.plugin.load(os.getenv("HOME") .. "/.local/lib/hyprland/plugins/hyprexpo.so")

local hyprexpo_loaded = false
for _, plugin in ipairs(hl.get_loaded_plugins()) do
    if plugin.name == "hyprexpo" then
        hyprexpo_loaded = true
        break
    end
end

if hyprexpo_loaded then
    hl.plugin.hyprexpo.gesture({ fingers = 3, direction = "up", action = "expo" })
    hl.plugin.hyprexpo.gesture({ fingers = 3, direction = "down", action = "cancel" })
end
