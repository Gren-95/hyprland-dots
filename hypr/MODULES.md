# Hyprland modules

`hyprland.lua` requires each file in `modules/` (Lua config, Hyprland 0.55+),
then `hyprland-gui.lua` last — HyprMod saves there, so its settings override
the modules. Split for readability — every module is small and self-contained.

| File | Owns | Notable contents |
|---|---|---|
| `general.lua` | Program shortcut vars + Hyprland general/decoration/animations | `var_terminal`, `var_fileManager`, `var_colorpicker`, `var_lockscreen`, `var_screenshotocr`, `var_externalscript1` (restart.sh), `var_externalscript2` (wallpaper.sh). Gaps, border colors, animation curves. |
| `appearance.lua` | Look-and-feel | Border radius, blur, shadow, opacity. Not visible by default; tweak when changing theme. |
| `monitors.lua` | Per-monitor layout | `hl.monitor()` entries. Adjust here when a display is added/removed. The fallback `FALLBACK,1920x1080@60,auto,1` is set from `restart.sh`. |
| `input.lua` | Keyboard, mouse, touchpad | XKB layout, key repeat, follow-mouse, natural scroll. |
| `gestures.lua` | Touchpad gestures | 3-finger workspace swipe, 4-finger fullscreen-state lambdas, pinch cursorZoom. |
| `keys.lua` | All keybindings | See `KEYBINDS.md` at the repo root for a flat reference. |
| `rules.lua` | Window rules | `hl.window_rule()` entries — float/tile overrides, opacity for specific apps. |
| `autostart.lua` | exec-once + env vars | Cursor theme/size, Qt platform theme, QML import path. Starts `restart.sh` (which fans out to everything else) and `nm-applet`. |

The other `hypr/*.conf` files (hypridle, hyprlock, hyprpaper, hyprqt6engine)
are separate tools that still use hyprlang — do not convert them to Lua.
