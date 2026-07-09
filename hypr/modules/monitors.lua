-- ## MONITORS ###

-- Use preferred settings for built-in display, and auto-detect for others
hl.monitor({
    output = "eDP-1",
    disabled = false,
    mode = "preferred",
    position = "0x0",
    scale = 1,
})
hl.monitor({
    output = "",
    disabled = false,
    mode = "preferred",
    position = "auto",
    scale = 1,
})

-- monitor = DP-4, preferred, auto, 1, transform, 1

-- Laptop lid switch handler.

-- Use DPMS (panel power off/on) instead of "monitor disable", which tears down the

-- output and leaves the i915 atomic page-flip wedged ("Device or resource busy"),

-- producing an unrecoverable black screen on lid open. Targets eDP-1 only so a

-- docked external monitor is unaffected.

-- logind has HandleLidSwitch=ignore, so closing the lid does NOT suspend - it only

-- DPMS-offs the panel. The open handler therefore only needs a single DPMS on; the

-- old off->on->off->on dance raced hypridle's after_sleep_cmd when a lid open

-- coincided with a resume, helping wedge the page-flip. Resume recovery (the

-- VT-switch modeset) lives in after_sleep_cmd, not here.
hl.bind("switch:on:Lid Switch", hl.dsp.dpms("off eDP-1"), {
    locked = true,
})
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("hyprctl dispatch dpms on eDP-1 && brightnessctl -r"), {
    locked = true,
})

-- ## WORKSPACE ASSIGNMENTS ###
hl.workspace_rule({
    workspace = "1",
    monitor = "eDP-1",
    default = true,
})
hl.workspace_rule({
    workspace = "2",
    monitor = "eDP-1",
})
hl.workspace_rule({
    workspace = "3",
    monitor = "eDP-1",
})
hl.workspace_rule({
    workspace = "4",
    monitor = "eDP-1",
})
hl.workspace_rule({
    workspace = "5",
    monitor = "eDP-1",
})
hl.workspace_rule({
    workspace = "6",
    monitor = "DP-4",
})
hl.workspace_rule({
    workspace = "7",
    monitor = "DP-4",
})
hl.workspace_rule({
    workspace = "8",
    monitor = "DP-4",
})
hl.workspace_rule({
    workspace = "9",
    monitor = "DP-4",
})
hl.workspace_rule({
    workspace = "10",
    monitor = "DP-4",
})
