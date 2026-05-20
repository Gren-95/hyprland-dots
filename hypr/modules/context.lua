-- Shared constants used by other modules. Equivalent to the $-variables
-- in the old .conf format.

return {
    mainMod = "SUPER",
    programs = {
        terminal      = "kitty",
        fileManager   = "nautilus",
        browser       = "firefox",
        colorpicker   = "hyprpicker -a",
        lockscreen    = "bash -c 'bash ~/.config/scripts/hyprlock-art.sh; hyprlock'",
        screenshot    = "bash ~/.config/scripts/screenshot.sh",
        screenshotocr = "bash ~/.config/scripts/screenshot-ocr.sh",
        restart       = "bash ~/.config/scripts/restart.sh",
        wallpaper     = "bash ~/.config/scripts/wallpaper.sh",
    },
}
