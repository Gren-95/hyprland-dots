-- Keybindings. Every bind carries a `description` so `hyprctl binds -j`
-- (consumed by quickshell/Keybinds.qml) shows a friendly label instead of
-- the internal "__lua <callback id>".

local ctx = require("modules.context")
local mod = ctx.mainMod
local p   = ctx.programs

-- Helpers
local function exec(cmd) return hl.dsp.exec_cmd(cmd) end
local function global(target) return hl.dsp.global(target) end

local function bind(keys, dispatcher, description)
    return hl.bind(keys, dispatcher, { description = description })
end
local function bindo(keys, dispatcher, description, opts)
    opts.description = description
    return hl.bind(keys, dispatcher, opts)
end

------------------------------------------------------------
-- Application launchers and system actions
------------------------------------------------------------
bind(mod .. " + T",                exec(p.terminal),              "Open terminal")
bind(mod .. " + Q",                hl.dsp.window.close(),         "Close window")
bind(mod .. " + L",                exec(p.lockscreen),            "Lock screen")
bind(mod .. " + E",                exec(p.fileManager),           "Open file manager")
bind(mod .. " + G",                exec("hyprctl dispatch togglefloating"), "Toggle floating")
bind(mod .. " + R",                global("quickshell:spotlight"),"Spotlight launcher")
bind("ALT + space",                global("quickshell:spotlight"),"Spotlight launcher")
bind(mod .. " + P",                hl.dsp.window.pseudo(),        "Pseudo-tile window")
bind(mod .. " + J",                hl.dsp.layout("togglesplit"),  "Toggle split direction")
bind(mod .. " + N",                global("quickshell:notifications"), "Notifications")
bind(mod .. " + V",                global("quickshell:clipboard"),"Clipboard history")
bind(mod .. " + C",                exec(p.colorpicker),           "Color picker")
bind(mod .. " + F",                hl.dsp.window.fullscreen_state({ internal = 1, client = 1 }), "Fullscreen")
bind(mod .. " + SHIFT + N",        exec(p.wallpaper),             "Cycle wallpaper")
bind(mod .. " + SHIFT + S",        global("quickshell:screenshot-region"), "Screenshot region")
bind(mod .. " + CTRL + SHIFT + S", exec(p.screenshotocr),         "Screenshot OCR")
bind(mod .. " + CTRL + R",         exec("bash ~/.config/scripts/wayvnc-toggle.sh"), "Toggle wayvnc")
bind(mod .. " + B",                exec(p.restart),               "Restart shell services")
bind(mod .. " + SHIFT + E",        global("quickshell:powermenu"),"Power menu")
bind(mod .. " + F1",               global("quickshell:keybinds"), "Keybinds viewer")
bind(mod .. " + M",                global("quickshell:sysmon"),   "System monitor")
bind(mod .. " + A",                global("quickshell:quickactions"), "Quick actions")
bind(mod .. " + S",                global("quickshell:audiopower"),"Audio & power")
bind(mod .. " + D",                global("quickshell:calendar"), "Calendar")
bind(mod .. " + W",                global("quickshell:wallpaper"),"Wallpaper picker")

------------------------------------------------------------
-- Utility
------------------------------------------------------------
bind(mod .. " + SHIFT + R",        exec("bash ~/.config/scripts/screenrecord.sh"), "Screen record")
bind(mod .. " + SHIFT + M",        exec("bash -c 'mpv --no-video --shuffle ~/Music/*'"), "Music start")
bind(mod .. " + SHIFT + K",        exec("pkill mpv"),             "Music stop")
bind(mod .. " + SHIFT + B",        global("quickshell:bluetooth"),"Bluetooth")

------------------------------------------------------------
-- Focus movement
------------------------------------------------------------
bind(mod .. " + CTRL + left",      hl.dsp.focus({ direction = "left"  }), "Focus window left")
bind(mod .. " + CTRL + right",     hl.dsp.focus({ direction = "right" }), "Focus window right")
bind(mod .. " + CTRL + down",      hl.dsp.focus({ direction = "down"  }), "Focus window down")
bind(mod .. " + CTRL + up",        hl.dsp.focus({ direction = "up"    }), "Focus window up")
bind(mod .. " + left",             hl.dsp.window.move({ direction = "left"  }), "Move window left")
bind(mod .. " + right",            hl.dsp.window.move({ direction = "right" }), "Move window right")
bind(mod .. " + up",               hl.dsp.window.move({ direction = "up"    }), "Move window up")
bind(mod .. " + down",             hl.dsp.window.move({ direction = "down"  }), "Move window down")

------------------------------------------------------------
-- Workspace switching + window moves (1–10, 0 = workspace 10)
------------------------------------------------------------
for i = 1, 10 do
    local key = i % 10
    bind(mod .. " + " .. key,             hl.dsp.focus({ workspace = i }),       "Workspace " .. i)
    bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }), "Move window to workspace " .. i)
end

-- Per-monitor workspace navigation
bind(mod .. " + bracketleft",          hl.dsp.focus({ workspace = "m-1" }),         "Previous workspace on monitor")
bind(mod .. " + bracketright",         hl.dsp.focus({ workspace = "m+1" }),         "Next workspace on monitor")
bind(mod .. " + SHIFT + bracketleft",  hl.dsp.window.move({ workspace = "m-1" }),   "Move window to previous workspace")
bind(mod .. " + SHIFT + bracketright", hl.dsp.window.move({ workspace = "m+1" }),   "Move window to next workspace")

-- Alt+Tab keeps muscle memory via native cyclenext (no overlay).
bind("ALT + Tab",         exec("hyprctl dispatch cyclenext"),       "Cycle window")
bind("ALT + SHIFT + Tab", exec("hyprctl dispatch cyclenext prev"),  "Cycle window backward")

-- Super+Tab opens the workspace overview and cycles on each press.
bind("SUPER + Tab",       global("quickshell:overview-cycle"),      "Overview cycle")
bind("SUPER + SHIFT + Tab", global("quickshell:overview-cycle-prev"), "Overview cycle backward")
bindo("SUPER + Super_L",  global("quickshell:supertap"),            "Overview commit", { ignore_mods = true })

-- Monitor focus + move workspace to next monitor
bind(mod .. " + grave",            hl.dsp.focus({ monitor = "+1" }),            "Focus next monitor")
bind(mod .. " + SHIFT + grave",    hl.dsp.workspace.move({ monitor = "+1" }),   "Move workspace to next monitor")

------------------------------------------------------------
-- Mouse
------------------------------------------------------------
bindo(mod .. " + mouse:272", hl.dsp.window.drag(),   "Drag window",   { mouse = true })
bindo(mod .. " + mouse:273", hl.dsp.window.resize(), "Resize window", { mouse = true })

-- Mouse workspace cycling (monitor-aware)
bind(mod .. " + mouse_down",         hl.dsp.focus({ workspace = "m+1" }),  "Next workspace (scroll)")
bind(mod .. " + mouse_up",           hl.dsp.focus({ workspace = "m-1" }),  "Previous workspace (scroll)")
bind(mod .. " + CTRL + mouse_down",  hl.dsp.focus({ workspace = "e+1" }),  "Next existing workspace (scroll)")
bind(mod .. " + CTRL + mouse_up",    hl.dsp.focus({ workspace = "e-1" }),  "Previous existing workspace (scroll)")

------------------------------------------------------------
-- Media and hardware keys (bindel = locked + repeating)
------------------------------------------------------------
local lockedRepeat = { locked = true, repeating = true }
local lockedOnly   = { locked = true }

bindo("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"), "Volume up",         lockedRepeat)
bindo("XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),        "Volume down",       lockedRepeat)
bindo("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),       "Mute speakers",     lockedRepeat)
bindo("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),     "Mute microphone",   lockedRepeat)
bindo("XF86MonBrightnessUp",   exec("brightnessctl s 5%+"),                              "Brightness up",     lockedRepeat)
bindo("XF86MonBrightnessDown", exec("brightnessctl s 5%-"),                              "Brightness down",   lockedRepeat)
bindo("XF86KbdBrightnessUp",   exec("brightnessctl -d dell::kbd_backlight s +1"),        "Keyboard light up", lockedRepeat)
bindo("XF86KbdBrightnessDown", exec("brightnessctl -d dell::kbd_backlight s 1-"),        "Keyboard light down", lockedRepeat)
bindo("XF86KbdLightOnOff",     exec("brightnessctl -d dell::kbd_backlight s +1"),        "Keyboard light cycle", lockedRepeat)
bindo(mod .. " + CTRL + K",
      exec([[sh -c 'cur=$(brightnessctl -d dell::kbd_backlight g); max=$(brightnessctl -d dell::kbd_backlight m); next=$(( cur + 1 > max ? 0 : cur + 1 )); brightnessctl -d dell::kbd_backlight s "$next"']]),
      "Keyboard light cycle", lockedRepeat)

bindo("XF86AudioNext",  exec("playerctl next"),       "Next track",     lockedOnly)
bindo("XF86AudioPause", exec("playerctl play-pause"), "Play / pause",   lockedOnly)
bindo("XF86AudioPlay",  exec("playerctl play-pause"), "Play / pause",   lockedOnly)
bindo("XF86AudioPrev",  exec("playerctl previous"),   "Previous track", lockedOnly)
bindo("XF86PowerOff",   exec("systemctl suspend"),    "Suspend",        lockedRepeat)

------------------------------------------------------------
-- Window resizing (binde = repeating)
------------------------------------------------------------
bind(mod .. " + KP_Add",          hl.dsp.window.resize({ x = 20,  y = 20,  relative = true }), "Resize window bigger")
bindo(mod .. " + SHIFT + right",  hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }), "Resize window right",  { repeating = true })
bindo(mod .. " + SHIFT + down",   hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }), "Resize window down",   { repeating = true })
bind(mod .. " + KP_Subtract",     hl.dsp.window.resize({ x = -20, y = -20, relative = true }), "Resize window smaller")
bindo(mod .. " + SHIFT + left",   hl.dsp.window.resize({ x = -20, y = 0,   relative = true }), "Resize window left",   { repeating = true })
bindo(mod .. " + SHIFT + up",     hl.dsp.window.resize({ x = 0,   y = -20, relative = true }), "Resize window up",     { repeating = true })
