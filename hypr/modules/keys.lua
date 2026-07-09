-- ## KEYBINDINGS ###

-- Application launchers and system actions
hl.bind(var_mainMod .. " + T", hl.dsp.exec_cmd(var_terminal))
hl.bind(var_mainMod .. " + Q", hl.dsp.window.close())
hl.bind(var_mainMod .. " + L", hl.dsp.exec_cmd(var_lockscreen))
hl.bind(var_mainMod .. " + E", hl.dsp.exec_cmd(var_fileManager))
hl.bind(var_mainMod .. " + G", hl.dsp.window.float({ action = "toggle" }))
hl.bind(var_mainMod .. " + R", hl.dsp.global("quickshell:spotlight"))
hl.bind("ALT + space", hl.dsp.global("quickshell:spotlight"))
hl.bind(var_mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(var_mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(var_mainMod .. " + N", hl.dsp.global("quickshell:notifications"))
hl.bind(var_mainMod .. " + V", hl.dsp.global("quickshell:clipboard"))
hl.bind(var_mainMod .. " + C", hl.dsp.exec_cmd(var_colorpicker))
hl.bind(var_mainMod .. " + SHIFT + N", hl.dsp.exec_cmd(var_externalscript2))
hl.bind(var_mainMod .. " + SHIFT + S", hl.dsp.global("quickshell:screenshot-region"))
hl.bind(var_mainMod .. " + CTRL + SHIFT + S", hl.dsp.exec_cmd(var_screenshotocr))

-- Super+Shift+A (edit-on-the-fly via slurp|swappy) removed — click the

-- Screenshot notification's thumbnail to open the saved image in swappy.
hl.bind(var_mainMod .. " + CTRL + R", hl.dsp.exec_cmd("bash ~/.config/scripts/wayvnc-toggle.sh"))
hl.bind(var_mainMod .. " + B", hl.dsp.exec_cmd(var_externalscript1))
hl.bind(var_mainMod .. " + SHIFT + E", hl.dsp.global("quickshell:powermenu"))
hl.bind(var_mainMod .. " + F1", hl.dsp.global("quickshell:keybinds"))
hl.bind(var_mainMod .. " + comma", hl.dsp.global("quickshell:settings"))
hl.bind(var_mainMod .. " + M", hl.dsp.global("quickshell:sysmon"))
hl.bind(var_mainMod .. " + A", hl.dsp.global("quickshell:quickactions"))
hl.bind(var_mainMod .. " + S", hl.dsp.global("quickshell:audiopower"))
hl.bind(var_mainMod .. " + D", hl.dsp.global("quickshell:calendar"))
hl.bind(var_mainMod .. " + W", hl.dsp.global("quickshell:wallpaper"))

-- Utility
hl.bind(var_mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("bash ~/.config/scripts/screenrecord.sh"))
hl.bind(var_mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("bash -c 'mpv --no-video --shuffle ~/Music/*'"))
hl.bind(var_mainMod .. " + SHIFT + K", hl.dsp.exec_cmd("pkill mpv"))
hl.bind(var_mainMod .. " + SHIFT + B", hl.dsp.global("quickshell:bluetooth"))

-- Focus movement
hl.bind(var_mainMod .. " + CTRL + left", hl.dsp.focus({ direction = "left" }))
hl.bind(var_mainMod .. " + CTRL + right", hl.dsp.focus({ direction = "right" }))
hl.bind(var_mainMod .. " + CTRL + down", hl.dsp.focus({ direction = "down" }))
hl.bind(var_mainMod .. " + CTRL + up", hl.dsp.focus({ direction = "up" }))
hl.bind(var_mainMod .. " + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(var_mainMod .. " + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(var_mainMod .. " + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(var_mainMod .. " + down", hl.dsp.window.move({ direction = "down" }))

-- Workspace switching
hl.bind(var_mainMod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(var_mainMod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(var_mainMod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(var_mainMod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(var_mainMod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(var_mainMod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(var_mainMod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(var_mainMod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(var_mainMod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(var_mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Multi-monitor workspace navigation
hl.bind(var_mainMod .. " + bracketleft", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(var_mainMod .. " + bracketright", hl.dsp.focus({ workspace = "m+1" }))

-- Alt+Tab keeps muscle memory via native cyclenext (no overlay).
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next())

-- Super+Tab opens the workspace overview and cycles on each press.

-- bindi = Super, Super_L tracks Super press/release so the overlay commits

-- the highlighted workspace when Super is finally released.
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overview-cycle"))
hl.bind("SUPER + SHIFT + Tab", hl.dsp.global("quickshell:overview-cycle-prev"))
hl.bind("SUPER + Super_L", hl.dsp.global("quickshell:supertap"), {
    ignore_mods = true,
})
hl.bind(var_mainMod .. " + grave", hl.dsp.focus({ monitor = "+1" }))

-- Move window to workspace
hl.bind(var_mainMod .. " + SHIFT + 1", hl.dsp.window.move({ workspace = 1 }))
hl.bind(var_mainMod .. " + SHIFT + 2", hl.dsp.window.move({ workspace = 2 }))
hl.bind(var_mainMod .. " + SHIFT + 3", hl.dsp.window.move({ workspace = 3 }))
hl.bind(var_mainMod .. " + SHIFT + 4", hl.dsp.window.move({ workspace = 4 }))
hl.bind(var_mainMod .. " + SHIFT + 5", hl.dsp.window.move({ workspace = 5 }))
hl.bind(var_mainMod .. " + SHIFT + 6", hl.dsp.window.move({ workspace = 6 }))
hl.bind(var_mainMod .. " + SHIFT + 7", hl.dsp.window.move({ workspace = 7 }))
hl.bind(var_mainMod .. " + SHIFT + 8", hl.dsp.window.move({ workspace = 8 }))
hl.bind(var_mainMod .. " + SHIFT + 9", hl.dsp.window.move({ workspace = 9 }))
hl.bind(var_mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))

-- Move window to adjacent workspace on current monitor
hl.bind(var_mainMod .. " + SHIFT + bracketleft", hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(var_mainMod .. " + SHIFT + bracketright", hl.dsp.window.move({ workspace = "m+1" }))

-- Move window to next monitor
hl.bind(var_mainMod .. " + SHIFT + grave", hl.dsp.workspace.move({ monitor = "+1" }))

-- Mouse bindings
hl.bind(var_mainMod .. " + mouse:272", hl.dsp.window.drag(), {
    mouse = true,
})
hl.bind(var_mainMod .. " + mouse:273", hl.dsp.window.resize(), {
    mouse = true,
})

-- Mouse workspace cycling (monitor-aware)
hl.bind(var_mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "m+1" }))
hl.bind(var_mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "m-1" }))
hl.bind(var_mainMod .. " + CTRL + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(var_mainMod .. " + CTRL + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Media and hardware keys
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 5%+"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86KbdBrightnessUp", hl.dsp.exec_cmd("brightnessctl -d dell::kbd_backlight s +1"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d dell::kbd_backlight s 1-"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86KbdLightOnOff", hl.dsp.exec_cmd("brightnessctl -d dell::kbd_backlight s +1"), {
    repeating = true,
    locked = true,
})
hl.bind(var_mainMod .. " + CTRL + K", hl.dsp.exec_cmd("sh -c 'cur=$(brightnessctl -d dell::kbd_backlight g); max=$(brightnessctl -d dell::kbd_backlight m); next=$(( cur + 1 > max ? 0 : cur + 1 )); brightnessctl -d dell::kbd_backlight s \"$next\"'"), {
    repeating = true,
    locked = true,
})
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), {
    locked = true,
})
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), {
    locked = true,
})
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), {
    locked = true,
})
hl.bind("XF86PowerOff", hl.dsp.exec_cmd("systemctl suspend"), {
    repeating = true,
    locked = true,
})

-- Window resizing
hl.bind(var_mainMod .. " + KP_Add", hl.dsp.window.resize({ x = 20, y = 20, relative = true }))
hl.bind(var_mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. " + KP_Subtract", hl.dsp.window.resize({ x = -20, y = -20, relative = true }))
hl.bind(var_mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), {
    repeating = true,
})
hl.bind(var_mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), {
    repeating = true,
})

-- Maximize (moved off Super+Shift+Up, clashed with resizeactive above)
hl.bind(var_mainMod .. " + F", hl.dsp.window.fullscreen_state({ internal = 1, client = -1 }))
