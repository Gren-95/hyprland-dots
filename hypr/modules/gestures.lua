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

-- 4-finger up/down → set fullscreen state idempotently (2 = real fs, 0 = none).
-- HL.GestureSpec's stub only lists string `action`, but Hyprland's binary
-- ships a `CDispatcherTrackpadGesture` class — `action = "dispatcher"` is
-- valid even though undocumented in the Lua stubs, and `dispatcher`/`args`
-- fields are accepted dynamically. Falling back to plain "fullscreen"
-- regressed to a toggle, which un-fullscreened Overwatch when already
-- fullscreen.
hl.gesture({ fingers = 4, direction = "up",    action = "dispatcher", dispatcher = "fullscreenstate", args = "2" })
hl.gesture({ fingers = 4, direction = "down",  action = "dispatcher", dispatcher = "fullscreenstate", args = "0" })
hl.gesture({ fingers = 2, direction = "pinch", action = "cursorZoom", scale = 1 })
