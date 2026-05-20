-- Touchpad gestures.

hl.config({
    gestures = {
        workspace_swipe_distance           = 500,
        workspace_swipe_invert             = true,
        workspace_swipe_min_speed_to_force = 30,
        workspace_swipe_cancel_ratio       = 0.5,
        workspace_swipe_forever            = true,
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- 4-finger up/down for fullscreen state. HL.GestureSpec in v0.55 doesn't
-- expose a generic `dispatcher` field the way the .conf format did, so
-- we use `action = "fullscreen"` with the appropriate `mode`. NOTE: this
-- regresses to toggle semantics, which previously caused Overwatch to
-- minimise when already fullscreen. If that comes back, revert this
-- module to the .conf via `mv hyprland.lua hyprland.lua.bak` and
-- restarting Hyprland (it'll pick the .conf back up).
hl.gesture({ fingers = 4, direction = "up",    action = "fullscreen", mode = "2" })
hl.gesture({ fingers = 4, direction = "down",  action = "fullscreen", mode = "0" })
hl.gesture({ fingers = 2, direction = "pinch", action = "cursorZoom", scale = 1 })
