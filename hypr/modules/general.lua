var_terminal = "kitty"
var_fileManager = "nautilus"
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
        col = {
            active_border = {
                colors = {"rgba(33ccffee)", "rgba(00ff99ee)"},
                angle = 45,
            },
            inactive_border = "rgba(595959aa)",
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
