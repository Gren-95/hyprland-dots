-- Keyboard, mouse, touchpad, xwayland.

hl.config({
    input = {
        kb_layout    = "ee",
        kb_variant   = "nodeadkeys",
        kb_model     = "latitude",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        repeat_rate  = 25,
        repeat_delay = 300,
        touchpad = {
            natural_scroll          = true,
            tap_to_click            = true,
            clickfinger_behavior    = true,
            middle_button_emulation = true,
        },
    },
    xwayland = {
        enabled            = true,
        force_zero_scaling = true,
    },
})

-- Disable left+right = middle-click chord on real mice. Without this,
-- games like Overwatch see L+R as MMB (libinput defaults emulate middle
-- when no physical MMB is detected). Touchpad keeps the chord on
-- purpose — it's the only way to middle-click without a third finger.
for _, name in ipairs({
    "dell-mouse-ms5320w-mouse",
    "dell-computer-corp-dell-universal-receiver-mouse",
    "ven_06cb:00-06cb:ceef-mouse",
    "ps/2-generic-mouse",
}) do
    hl.device({ name = name, middle_button_emulation = false })
end
