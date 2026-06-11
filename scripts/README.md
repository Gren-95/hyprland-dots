# Scripts

Shell scripts that back the Hyprland session. Most are invoked from
`hypr/modules/autostart.conf`, Hyprland keybinds, or the Quickshell UI.

All notification calls go through `lib/notify.sh`. Daemons use `set -uo pipefail`
(no `-e`, transient failures shouldn't kill the loop); one-shots use
`set -euo pipefail`.

## Library helpers

| File | Purpose |
|---|---|
| `lib/notify.sh` | `notify <urgency> <key> <icon> <title> <body> [timeout]` wrapper around `notify-send`. Always sets `-a hyprland-dots` and `-h x-canonical-private-synchronous:<key>` so repeat notifications replace instead of stacking. |
| `paths.sh` | Canonical user-path env vars (`PICTURES_DIR`, `WALLPAPER_DIR`, `RECORDINGS_DIR`, `CACHE_DIR`, etc.). Sourced by every consumer. |

## Daemons (autostart / restart.sh)

| File | Spawned by | What it does |
|---|---|---|
| `battery-notify.sh` | `restart.sh` | Polls `/sys/class/power_supply/BAT*` every 60s. Sends critical/normal notifications at 10% / 20% (replace-key `battery`). |
| `network-notify.sh` | `restart.sh` | `nmcli monitor` pipe. Emits a notification on connect/disconnect (replace-key `network`). |
| `media-inhibit.sh` | `restart.sh` | Polls `playerctl status` every 3s. Inhibits `org.freedesktop.ScreenSaver` while a player is `Playing` so hypridle doesn't lock during playback. |
| `fullscreen-inhibit.sh` | `restart.sh` | Polls `hyprctl workspaces` every 5s. Inhibits `org.freedesktop.ScreenSaver` while any window is fullscreen so hypridle doesn't dim/lock/suspend during controller-driven games (gamepad input doesn't reset the Wayland idle timer). |
| `power-auto.sh` | `restart.sh` + autostart | Listens to `upower --monitor-detail`. Sets `performance` on AC, `balanced` on battery ≥30%, `power-saver` <30% via `powerprofilesctl`. Idempotent (skips if already at target). |
| `dotwatch.sh` | `restart.sh` | `inotifywait` on the dots repo. Reloads Hyprland / hypridle config in-place when their files change. Hot-reloads `gtk-3.0/gtk.css` notify and hyprlock config notify. |
| `immich-sync.sh` | cron (via `sync-toggle.sh`) | Runs once by default. `--daemon` flag for legacy loop mode (unused by current setup). Uses the `immich` CLI to upload `$PICTURES_DIR` (excluding `**/ocr/**`). |
| `jellyfin-music-sync.sh` | cron (via `sync-toggle.sh`) | Same shape — single run by default, `--daemon` for the loop. Mirrors Jellyfin music library to `$MUSIC_DIR`, deleting local files no longer on the server. |

## Toggles (Hyprland keybind / Quickshell UI)

| File | Triggered by | What it does |
|---|---|---|
| `wayvnc-toggle.sh` | Quick Actions "Remote access" toggle, or `Super+Ctrl+R` | Starts wayvnc if not running, kills it if it is. Notifies with the local IP on start. |
| `sync-toggle.sh` | Quick Actions "Immich/Jellyfin sync" toggles | Manages cron entries between `# QSSYNC:<kind>` markers. Commands: `status [all\|<kind>]`, `toggle <kind>`, `enable <kind>`, `disable <kind>`, `schedule <kind> '<cron-expr>'`. Self-installs commented-out lines on first call. |

## One-shots (keybind-triggered)

| File | Keybind / invocation | What it does |
|---|---|---|
| `screenshot.sh` | Quickshell `RegionSelector` (`Super+Shift+S`) | Accepts a pre-computed `"X,Y WxH"` region as `$1` (falls back to `slurp -d` if no arg). `grim` → save to `$SCREENSHOTS_DIR` → `wl-copy` → notify → echo the saved path on stdout (RegionSelector reads it to open ScreenshotActions). |
| `screenshot-ocr.sh` | `Super+Ctrl+Shift+S` or ScreenshotActions "OCR" | Accepts a pre-captured image file as `$1` (falls back to `slurp+grim` otherwise). ImageMagick preprocess (3× upscale, optional invert, contrast stretch) → `tesseract` (eng+est) → `wl-copy` text + notify with preview. |
| `screenrecord.sh` | `Super+Shift+R` (or Quick Actions Record) | Toggles `gpu-screen-recorder` with `-w screen` (DRM capture). PID stored in `/tmp/screenrecord.pid`. |
| `wallpaper.sh` | `Super+Shift+N`, WallpaperPicker tile | Accepts an absolute path as `$1` to set a specific wallpaper; no arg picks a random one from `$WALLPAPER_DIR`. Applies via `hyprctl hyprpaper` to every monitor. |
| `sysinfo.sh` | Quickshell `SystemMonitor` (`Super+M`) | Emits a single JSON line: `cpu_pct`, per-core `cpu_cores[]`, `cpu_temp`, `ram_*`, `nvme_temp`, `fan1/2`, `disks[]` (one per real local FS), `uptime`. CPU uses a 200 ms `/proc/stat` sampling window; hwmon paths discovered by name so they survive reboot reordering. |
| `hyprlock-art.sh` | hypridle pre-lock hook (and direct call) | Copies the current MPRIS album art to `$LOCK_ART` so hyprlock can display it. Also picks a random wallpaper for the lock background. |
| `restart.sh` | `Super+B` | Sequentially restarts every userspace service: xdg-desktop-portal, gnome-keyring, Quickshell, hyprpaper, hypridle, battery-notify, media-inhibit, cliphist, nm-applet, network-notify, dotwatch. Sets GTK theme, fallback monitor. Logs OK/FAILED per step to stdout. |
| `generate-avatar.sh` | `setup.sh` | Python+Pillow renders a circular initials avatar from `$USER`, installs to `/var/lib/AccountsService/icons/$USER` (used as lockscreen avatar). |
