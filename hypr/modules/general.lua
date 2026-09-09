-- Both run through default-app.sh, so the "Default terminal" / "Default file
-- manager" pickers in the runner take effect without editing this file. The
-- script falls back to kitty and nautilus when nothing has been chosen.
local scripts = os.getenv("HOME") .. "/.config/scripts"
var_terminal = "bash " .. scripts .. "/default-app.sh run terminal"
var_fileManager = "bash " .. scripts .. "/default-app.sh run filemanager"
var_colorpicker = "hyprpicker -a"
var_mainMod = "SUPER"
var_lockscreen = "bash -c 'bash ~/.config/scripts/hyprlock-art.sh; hyprlock'"
var_screenshotocr = "bash ~/.config/scripts/screenshot-ocr.sh"
var_externalscript1 = "bash ~/.config/scripts/restart.sh"
var_externalscript2 = "bash ~/.config/scripts/wallpaper.sh"

-- ## PROGRAM SHORTCUTS ###
hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 4,
        border_size = 4,
        -- Palette from quickshell/Theme.qml: the focused window carries
        -- accentPrimary (blue -> blueBright), unfocused ones fade back to
        -- Theme.borderStrong so focus is the only thing that draws the eye.
        col = {
            active_border = {
                colors = {"rgba(3b82f6ee)", "rgba(60a5faee)"},
                angle = 45,
            },
            inactive_border = "rgba(44403caa)",
        },
        allow_tearing = true,
        resize_on_border = true,
        layout = "dwindle",
    },
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        disable_autoreload = false,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        always_follow_on_dnd = true,
        layers_hog_keyboard_focus = true,
        animate_manual_resizes = false,
        disable_splash_rendering = true,
        focus_on_activate = false,
    },
})

-- Variable refresh rate. 2 = fullscreen-only so the desktop stays at

-- the monitor's native rate; G-Sync/FreeSync kicks in only inside games.
hl.config({
    misc = {
        vrr = 2,
        -- Frame rate for windows carrying the `render_unfocused` rule (see
        -- rules.lua). Only needs to be high enough to keep frame callbacks
        -- flowing to a hidden game so it can't block in Present().
        render_unfocused_fps = 30,
    },
    cursor = {
        no_hardware_cursors = false,
    },
    dwindle = {
        preserve_split = true,
    },
    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles = true,
    },
})
