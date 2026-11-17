# Hyprland modules

`hyprland.lua` requires each file in `modules/` (Lua config, Hyprland 0.57+),
then `hyprland-gui.lua` last — HyprMod saves there, so its settings override
the modules. Split for readability — every module is small and self-contained.

| File | Owns | Notable contents |
|---|---|---|
| `general.lua` | Program shortcut vars + Hyprland general/misc settings | `var_terminal`, `var_fileManager` (both route through `default-app.sh run`, so the runner's default-app pickers take effect without editing this file), `var_colorpicker`, `var_lockscreen`, `var_screenshotocr`, `var_externalscript1` (restart.sh), `var_externalscript2` (wallpaper.sh). Border colors and tearing. Also compositor behaviour: `misc` (session-lock restore, no BEL chime, ANR sensitivity), `cursor` (hide while typing, warp on workspace change) and `binds` (switching workspace hides the scratchpad). |
| `appearance.lua` | Look-and-feel | Rounding power, animation curves and the animation list. Rounding, inactive opacity, shadow and blur are left to HyprMod in `hyprland-gui.lua`. |
| `monitors.lua` | Per-monitor layout | `hl.monitor()` entries. Adjust here when a display is added/removed. Also the lid switch binds (`scripts/lid.sh`). The fallback `FALLBACK,1920x1080@60,auto,1` is set from `restart.sh`. |
| `input.lua` | Keyboard, mouse, touchpad | XKB layout, key repeat, follow-mouse, natural scroll. |
| `gestures.lua` | Touchpad gestures | 3-finger workspace swipe, 3-finger up/down fullscreen-state lambdas, 4-finger left/right move the window to the next/previous workspace, 4-finger up hyprexpo overview (down = cancel), ALT+pinch cursorZoom. |
| `keys.lua` | Keybindings (lid switch binds are in `monitors.lua`) | See `KEYBINDS.md` at the repo root for a flat reference. |
| `rules.lua` | Window rules | `hl.window_rule()` entries — float/tile overrides, opacity for specific apps. |
| `autostart.lua` | exec-once + env vars | Cursor theme/size, Qt platform theme, QML import path. Starts `restart.sh` (which fans out to everything else, including the nm-applet tray app). |

`hyprland-gui.lua` (not a module) is written by HyprMod and loaded after the
modules, so its values win: gaps, border size, rounding, blur, shadow and
cursor options live there.

`settings.lua` is written by the settings app (`apps/settings`, Keyboard panel
for now) and loaded last with `pcall`, so it wins over both and may be missing.
It and its source `settings.json` are gitignored: they hold this machine's
choices (keyboard layouts, repeat, Caps Lock), applied live with `hyprctl eval`.

The other `hypr/*.conf` files (hypridle, hyprlock, hyprqt6engine)
are separate tools that still use hyprlang — do not convert them to Lua.
