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
    action = "cursorZoom",
    zoom_level = 1,
    mode = "live",
})

-- gesture = 3, up, close
