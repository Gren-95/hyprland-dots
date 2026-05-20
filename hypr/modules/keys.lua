-- Keybindings.

local ctx = require("modules.context")
local mod = ctx.mainMod
local p   = ctx.programs

-- Helpers
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
local function global(target) return hl.dsp.global(target) end

------------------------------------------------------------
-- Application launchers and system actions
------------------------------------------------------------
hl.bind(mod .. " + T",            exec(p.terminal))
hl.bind(mod .. " + Q",            hl.dsp.window.close())
hl.bind(mod .. " + L",            exec(p.lockscreen))
hl.bind(mod .. " + E",            exec(p.fileManager))
-- togglefloating: hl.dsp.window.float({action="toggle"}) is documented in
-- the v0.55 example but rejected at runtime; fall back to hyprctl.
hl.bind(mod .. " + G",            exec("hyprctl dispatch togglefloating"))
hl.bind(mod .. " + R",            global("quickshell:spotlight"))
hl.bind("ALT + space",            global("quickshell:spotlight"))
hl.bind(mod .. " + P",            hl.dsp.window.pseudo())
hl.bind(mod .. " + J",            hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + N",            global("quickshell:notifications"))
hl.bind(mod .. " + V",            global("quickshell:clipboard"))
hl.bind(mod .. " + C",            exec(p.colorpicker))
-- moved off Super+Shift+UP (clashed with resizeactive below)
hl.bind(mod .. " + F",            hl.dsp.window.fullscreen_state({ internal = 1, client = 1 }))
hl.bind(mod .. " + SHIFT + N",    exec(p.wallpaper))
hl.bind(mod .. " + SHIFT + S",    global("quickshell:screenshot-region"))
hl.bind(mod .. " + CTRL + SHIFT + S", exec(p.screenshotocr))
hl.bind(mod .. " + CTRL + R",     exec("bash ~/.config/scripts/wayvnc-toggle.sh"))
hl.bind(mod .. " + B",            exec(p.restart))
hl.bind(mod .. " + SHIFT + E",    global("quickshell:powermenu"))
hl.bind(mod .. " + F1",           global("quickshell:keybinds"))
hl.bind(mod .. " + M",            global("quickshell:sysmon"))
hl.bind(mod .. " + A",            global("quickshell:quickactions"))
hl.bind(mod .. " + S",            global("quickshell:audiopower"))
hl.bind(mod .. " + D",            global("quickshell:calendar"))
hl.bind(mod .. " + W",            global("quickshell:wallpaper"))

------------------------------------------------------------
-- Utility
------------------------------------------------------------
hl.bind(mod .. " + SHIFT + R",    exec("bash ~/.config/scripts/screenrecord.sh"))
hl.bind(mod .. " + SHIFT + M",    exec("bash -c 'mpv --no-video --shuffle ~/Music/*'"))
hl.bind(mod .. " + SHIFT + K",    exec("pkill mpv"))
hl.bind(mod .. " + SHIFT + B",    global("quickshell:bluetooth"))

------------------------------------------------------------
-- Focus movement
------------------------------------------------------------
hl.bind(mod .. " + CTRL + left",  hl.dsp.focus({ direction = "left"  }))
hl.bind(mod .. " + CTRL + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + CTRL + down",  hl.dsp.focus({ direction = "down"  }))
hl.bind(mod .. " + CTRL + up",    hl.dsp.focus({ direction = "up"    }))
hl.bind(mod .. " + left",         hl.dsp.window.move({ direction = "left"  }))
hl.bind(mod .. " + right",        hl.dsp.window.move({ direction = "right" }))
hl.bind(mod .. " + up",           hl.dsp.window.move({ direction = "up"    }))
hl.bind(mod .. " + down",         hl.dsp.window.move({ direction = "down"  }))

------------------------------------------------------------
-- Workspace switching + window moves (1–10, 0 = workspace 10)
------------------------------------------------------------
for i = 1, 10 do
    local key = i % 10
    hl.bind(mod .. " + " .. key,             hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Per-monitor workspace navigation
hl.bind(mod .. " + bracketleft",         hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mod .. " + bracketright",        hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mod .. " + SHIFT + bracketleft", hl.dsp.window.move({ workspace = "m-1" }))
hl.bind(mod .. " + SHIFT + bracketright",hl.dsp.window.move({ workspace = "m+1" }))

-- Alt+Tab keeps muscle memory via native cyclenext (no overlay).
hl.bind("ALT + Tab",         exec("hyprctl dispatch cyclenext"))
hl.bind("ALT + SHIFT + Tab", exec("hyprctl dispatch cyclenext prev"))

-- Super+Tab opens the workspace overview and cycles on each press.
-- bindi (ignore_mods) on Super_L tracks Super press/release so the
-- overlay commits the highlighted workspace when Super is released.
hl.bind("SUPER + Tab",         global("quickshell:overview-cycle"))
hl.bind("SUPER + SHIFT + Tab", global("quickshell:overview-cycle-prev"))
hl.bind("SUPER + Super_L",     global("quickshell:supertap"), { ignore_mods = true })

-- Monitor focus + move workspace to next monitor
hl.bind(mod .. " + grave",          hl.dsp.focus({ monitor = "+1" }))
hl.bind(mod .. " + SHIFT + grave",  hl.dsp.workspace.move({ monitor = "+1" }))

------------------------------------------------------------
-- Mouse
------------------------------------------------------------
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Mouse workspace cycling (monitor-aware)
hl.bind(mod .. " + mouse_down",        hl.dsp.focus({ workspace = "m+1" }))
hl.bind(mod .. " + mouse_up",          hl.dsp.focus({ workspace = "m-1" }))
hl.bind(mod .. " + CTRL + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + CTRL + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

------------------------------------------------------------
-- Media and hardware keys (bindel = locked + repeating)
------------------------------------------------------------
local lockedRepeat = { locked = true, repeating = true }
local lockedOnly   = { locked = true }

hl.bind("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), lockedRepeat)
hl.bind("XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),       lockedRepeat)
hl.bind("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       lockedRepeat)
hl.bind("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     lockedRepeat)
hl.bind("XF86MonBrightnessUp",   exec("brightnessctl s 5%+"),                              lockedRepeat)
hl.bind("XF86MonBrightnessDown", exec("brightnessctl s 5%-"),                              lockedRepeat)
hl.bind("XF86KbdBrightnessUp",   exec("brightnessctl -d dell::kbd_backlight s +1"),        lockedRepeat)
hl.bind("XF86KbdBrightnessDown", exec("brightnessctl -d dell::kbd_backlight s 1-"),        lockedRepeat)
hl.bind("XF86KbdLightOnOff",     exec("brightnessctl -d dell::kbd_backlight s +1"),        lockedRepeat)
hl.bind(mod .. " + CTRL + K",
        exec([[sh -c 'cur=$(brightnessctl -d dell::kbd_backlight g); max=$(brightnessctl -d dell::kbd_backlight m); next=$(( cur + 1 > max ? 0 : cur + 1 )); brightnessctl -d dell::kbd_backlight s "$next"']]),
        lockedRepeat)

hl.bind("XF86AudioNext",  exec("playerctl next"),       lockedOnly)
hl.bind("XF86AudioPause", exec("playerctl play-pause"), lockedOnly)
hl.bind("XF86AudioPlay",  exec("playerctl play-pause"), lockedOnly)
hl.bind("XF86AudioPrev",  exec("playerctl previous"),   lockedOnly)
hl.bind("XF86PowerOff",   exec("systemctl suspend"),    lockedRepeat)

------------------------------------------------------------
-- Window resizing (binde = repeating)
------------------------------------------------------------
hl.bind(mod .. " + KP_Add",         hl.dsp.window.resize({ x = 20,  y = 20,  relative = true }))
hl.bind(mod .. " + SHIFT + right",  hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + down",   hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }), { repeating = true })
hl.bind(mod .. " + KP_Subtract",    hl.dsp.window.resize({ x = -20, y = -20, relative = true }))
hl.bind(mod .. " + SHIFT + left",   hl.dsp.window.resize({ x = -20, y = 0,   relative = true }), { repeating = true })
hl.bind(mod .. " + SHIFT + up",     hl.dsp.window.resize({ x = 0,   y = -20, relative = true }), { repeating = true })
