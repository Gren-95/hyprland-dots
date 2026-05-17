# Hyprland modules

`hyprland.conf` sources each file in `modules/`. Split for readability — every
module is small and self-contained.

| File | Owns | Notable contents |
|---|---|---|
| `general.conf` | Program shortcut vars + Hyprland general/decoration/animations | `$terminal`, `$browser`, `$fileManager`, `$lockscreen`, `$screenshot`, `$externalscript1` (restart.sh), `$externalscript2` (wallpaper.sh). Gaps, border colors, animation curves. |
| `appearance.conf` | Look-and-feel | Border radius, blur, shadow, opacity. Not visible by default; tweak when changing theme. |
| `monitors.conf` | Per-monitor layout | `monitor =` lines. Adjust here when a display is added/removed. The fallback `FALLBACK,1920x1080@60,auto,1` is set from `restart.sh`. |
| `input.conf` | Keyboard, mouse, touchpad | XKB layout, key repeat, follow-mouse, natural scroll. |
| `gestures.conf` | Touchpad gestures | 3-finger workspace swipe, 4-finger overview-trigger. |
| `keys.conf` | All keybindings | See `KEYBINDS.md` at the repo root for a flat reference. |
| `rules.conf` | Window rules | `windowrule` / `windowrulev2` entries — float/tile overrides, opacity for specific apps. |
| `autostart.conf` | exec-once + env vars | Cursor size, Qt platform theme, QML import path. Starts `restart.sh` (which fans out to everything else) and `nm-applet`. |
