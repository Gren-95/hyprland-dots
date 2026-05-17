# Keybinds

`Super+F1` opens the live, searchable Keybinds viewer (parses `hyprctl binds`
at runtime — that's always the source of truth). This file is a flat reference
for setup time.

`$mainMod` = `Super`.

## Apps & system actions

| Key | Action |
|---|---|
| `Super+T` | Open terminal (kitty) |
| `Super+E` | Open file manager (nautilus) |
| `Super+C` | Color picker (hyprpicker) |
| `Super+L` | Lock screen (hyprlock + album art) |
| `Super+B` | Restart all userspace services (`scripts/restart.sh`) |
| `Super+Shift+E` | Power menu (Lock / Suspend / Logout / Reboot / Shutdown) |

## Quickshell modals

| Key | Action |
|---|---|
| `Super+R` / `Alt+Space` | App launcher (Spotlight) |
| `Super+V` | Clipboard history |
| `Super+N` | Toggle notification center |
| `Super+A` | Quick actions panel |
| `Super+Shift+B` | Bluetooth menu (Network modal, BT tab) |
| `Super+F1` | This keybinds viewer |
| `Super+M` | System monitor (CPU / RAM / temps / fans / uptime) |
| `Super+S` | Audio & Power panel (Sound tab) |
| `Super+D` | Calendar (with ICS sync) |
| `Super+W` | Wallpaper picker |
| `Super+Tab` | Workspace overview (cycle next while held) |
| `Super+Shift+Tab` | Workspace overview (cycle previous) |

## Capture

| Key | Action |
|---|---|
| `Super+Shift+S` | Screenshot region → file + clipboard |
| `Super+Ctrl+Shift+S` | Screenshot region → OCR → clipboard text |
| `Super+Shift+A` | Region screenshot piped straight to swappy |
| `Super+Shift+R` | Toggle screen recording (gpu-screen-recorder) |
| `Super+Shift+N` | Random wallpaper |
| `Super+Ctrl+R` | Toggle WayVNC remote access |

## Window management

| Key | Action |
|---|---|
| `Super+Q` | Close active window |
| `Super+G` | Toggle floating |
| `Super+J` | Toggle split direction |
| `Super+P` | Pseudo-tile |
| `Super+Shift+Up` | Toggle fullscreen |
| `Super+Ctrl+arrow` | Focus window in direction |
| `Super+arrow` | Move window in direction |
| `Super+Shift+arrow` | Resize active window |
| `Super+KP_Add` / `KP_Subtract` | Grow / shrink active window |
| `Super+drag` (LMB) | Move window |
| `Super+drag` (RMB) | Resize window |
| `Alt+Tab` / `Alt+Shift+Tab` | Native cycle next/previous (no overlay) |

## Workspaces

| Key | Action |
|---|---|
| `Super+1..9,0` | Switch to workspace N |
| `Super+Shift+1..9,0` | Move window to workspace N |
| `Super+[` / `Super+]` | Previous / next workspace on current monitor |
| `Super+Shift+[` / `Super+Shift+]` | Move window to previous / next workspace on monitor |
| `Super+grave` (`` ` ``) | Focus next monitor |
| `Super+Shift+grave` | Move current workspace to next monitor |
| `Super+wheel` | Cycle workspace on current monitor |
| `Super+Ctrl+wheel` | Cycle workspace across all monitors |

## Hardware keys

| Key | Action |
|---|---|
| `XF86AudioRaiseVolume` / `LowerVolume` | Sink volume ±5% |
| `XF86AudioMute` | Toggle sink mute |
| `XF86AudioMicMute` | Toggle source mute |
| `XF86AudioPlay` / `Pause` / `Next` / `Prev` | playerctl controls |
| `XF86MonBrightnessUp` / `Down` | Screen brightness ±5% |
| `XF86KbdBrightnessUp` / `Down` | Keyboard backlight ±1 step |
| `XF86KbdLightOnOff` / `Super+Ctrl+K` | Cycle keyboard backlight (off / half / full) |
| `XF86PowerOff` | Suspend |

## Personal

| Key | Action |
|---|---|
| `Super+Shift+M` / `Super+Shift+K` | mpv shuffle `~/Music` start / stop |
