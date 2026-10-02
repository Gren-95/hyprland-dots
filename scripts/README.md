# Scripts

Shell scripts that back the Hyprland session. Most are invoked from
`hypr/modules/autostart.lua`, Hyprland keybinds, or the Quickshell UI.

All notification calls go through `lib/notify.sh`. Daemons use `set -uo pipefail`
(no `-e`, transient failures shouldn't kill the loop); one-shots use
`set -euo pipefail`.

## Library helpers

| File | Purpose |
|---|---|
| `lib/notify.sh` | `notify <urgency> <key> <icon> <title> <body> [timeout]` wrapper around `notify-send`. Always sets `-a hyprland-dots` and `-h x-canonical-private-synchronous:<key>` so repeat notifications replace instead of stacking. |
| `lib/inhibit.sh` | `inhibit_start <app> <reason>` / `inhibit_stop`: holds an `org.freedesktop.ScreenSaver` inhibitor on a long-lived D-Bus connection. Used by `media-inhibit.sh`, `fullscreen-inhibit.sh`, `idle-inhibit-toggle.sh`. |
| `lib/env.sh` | `load_util_env` loads `util.env` (`KEY=VALUE`) into the environment. |
| `lib/screenshot.sh` | `capture_region "X,Y WxH"`: grim, wl-copy, notify, print path. Shared by both screenshot scripts. |
| `lib/deps.sh` | Required/optional command lists and the dnf package list, shared by `setup.sh` and `doctor.sh`. |
| `paths.sh` | Canonical user-path env vars (`PICTURES_DIR`, `WALLPAPER_DIR`, `RECORDINGS_DIR`, `CACHE_DIR`, etc.). Sourced by every consumer. |

## Helpers and config

| File | Purpose |
|---|---|
| `hypr-binds.sh` | Emits `hyprctl binds -j` with the real dispatcher/arg filled in. Lua-registered binds all report `__lua`, so this re-derives each action from `hypr/**/*.lua` and merges it back, keyed on (modmask, key). Used by the Quickshell keybinds viewer, the `kb` fish function and `docs/gen-keybinds.sh`. |
| `extract.sh` | Unpacks every archive in the cwd (or a given path): `.zip`, `.tar.gz`, `.tar.bz2`, `.rar`, `.7z`. |
| `ledvance.sh` | Pairs a Tuya/Ledvance LED through the upstream pairing script. Reads `LEDVANCE_USER`, `LEDVANCE_PASSWORD` and `LEDVANCE_PATH` from `util.env` itself; fish deliberately does not export the password. |
| `util.env.example` | Template for the gitignored `util.env` (Ledvance credentials, `RPGMDECRYPT_PATH`). Copy to `util.env` and fill in; `fish/conf.d/util-env.fish` loads the non-secret keys into fish. |

## Daemons (autostart / restart.sh)

`battery-notify`, `power-auto`, `media-inhibit` and `fullscreen-inhibit` run as systemd user units
(`systemd/user/*.service`, installed by `dotfiles-manager.sh units`); `restart.sh` restarts them with
`systemctl --user restart`.

| File | Spawned by | What it does |
|---|---|---|
| `battery-notify.sh` | `restart.sh` | Polls `/sys/class/power_supply/BAT*` every 60s. Sends critical/normal notifications at 10% / 20% (replace-key `battery`). |
| `media-inhibit.sh` | `restart.sh` | Polls `playerctl status` every 3s. Inhibits `org.freedesktop.ScreenSaver` while a player is `Playing` so hypridle doesn't lock during playback. |
| `fullscreen-inhibit.sh` | `restart.sh` | Polls `hyprctl workspaces` every 5s. Inhibits `org.freedesktop.ScreenSaver` while any window is fullscreen so hypridle doesn't dim/lock/suspend during controller-driven games (gamepad input doesn't reset the Wayland idle timer). |
| `power-auto.sh` | `restart.sh` + autostart | Listens to `upower --monitor-detail`. Sets `performance` on AC, `balanced` on battery ≥30%, `power-saver` <30% via `powerprofilesctl`. Idempotent (skips if already at target). |
| `dotwatch.sh` | `restart.sh` | `inotifywait` on the dots repo. Reloads Hyprland / hypridle config in-place when their files change. Hot-reloads `gtk-3.0/gtk.css` notify and hyprlock config notify. |
| `immich-sync.sh` | cron (via `sync-toggle.sh`) | Runs once by default. `--daemon` flag for legacy loop mode (unused by current setup). Uses the `immich` CLI to upload `$PICTURES_DIR` (excluding `**/ocr/**`). |
| `jellyfin-music-sync.sh` | cron (via `sync-toggle.sh`) | Same shape — single run by default, `--daemon` for the loop. Mirrors Jellyfin music library to `$MUSIC_DIR`, deleting local files no longer on the server. |

## Toggles (Hyprland keybind / Quickshell UI)

| File | Triggered by | What it does |
|---|---|---|
| `default-app.sh` | Hyprland binds (`run`), Spotlight's default-app pickers (`set`) | Which app fills a role — browser, terminal, editor, filemanager. `get` prefers XDG's own answer where one exists; `set` writes `~/.config/default-apps.conf` and registers the XDG default for browser/file manager; `run` resolves the entry across the XDG application directories and launches it, falling back to kitty/nautilus when nothing is chosen. |
| `services-status.sh` | Quickshell Services panel | One probe for the whole panel: prints `key=value` pairs on a single line — each session daemon's pgrep state, wayvnc, the WinApps container, both sync schedules, and the Jellyfin timer's next run as a unix timestamp. |
| `wayvnc-toggle.sh` | Services panel "Remote access" toggle, or `Super+Ctrl+R` | Starts wayvnc if not running (bound to the Tailscale IPv4 when available, else loopback), waits until the port listens, kills it if running. Notifies only on failure. |
| `sync-toggle.sh` | Services panel "Immich/Jellyfin sync" toggles | Manages cron entries between `# QSSYNC:<kind>` markers. Commands: `status [all\|<kind>]`, `toggle <kind>`, `enable <kind>`, `disable <kind>`, `schedule <kind> '<cron-expr>'`. Self-installs commented-out lines on first call. |

## New helpers

| File | What it does |
|---|---|
| `doctor.sh` | Read-only health check: required commands, user units, executable bits, dotfiles-manager symlinks, battery timer. Exit 1 on failure. |
| `screenshot-window.sh` | Screenshot of the active window (`hyprctl activewindow -j`), same save/copy/notify as `screenshot.sh`. |
| `night.sh` | `toggle\|on\|off\|status` night light via `hyprsunset`; `NIGHT_TEMPERATURE` in `util.env`. |
| `scratchpad.sh` | Toggle a drop-down kitty on the `special:scratchpad` workspace. |
| `idle-inhibit-toggle.sh` | Manual idle inhibit toggle; PID in `$XDG_RUNTIME_DIR/idle-inhibit.pid`. |

## One-shots (keybind-triggered)

| File | Keybind / invocation | What it does |
|---|---|---|
| `screenshot.sh` | Quickshell `RegionSelector` (`Super+Shift+S`) | Accepts a pre-computed `"X,Y WxH"` region as `$1` (falls back to `slurp -d` if no arg). `grim` → save to `$SCREENSHOTS_DIR` → `wl-copy` → notify → echo the saved path on stdout (RegionSelector reads it to open ScreenshotActions). |
| `screenshot-ocr.sh` | `Super+Ctrl+Shift+S` or ScreenshotActions "OCR" | Accepts a pre-captured image file as `$1` (falls back to `slurp+grim` otherwise). ImageMagick preprocess (3× upscale, optional invert, contrast stretch) → `tesseract` (eng+est) → `wl-copy` text + notify with preview. |
| `screenrecord.sh` | `Super+Shift+R` (or Quick Actions Record) | Toggles `gpu-screen-recorder` with `-w screen` (DRM capture). PID stored in `$XDG_RUNTIME_DIR/screenrecord.pid`; start failures and stops notify. |
| `wallpaper.sh` | `Super+Shift+N`, WallpaperDeck | Accepts an absolute path as `$1` to set a specific wallpaper; no arg picks a random one from `$WALLPAPER_DIR`. Applies via `awww img` to every output; GIFs animate. |
| `sysfast.sh` | Quickshell `SystemMonitor` (`Super+M`) | The cheap half of the monitor's data as one JSON line, ~45 ms: cumulative CPU counters (total and per core), load, frequency, memory breakdown, network and disk byte counters with a timestamp. The UI turns differences into rates and percentages, so it can sample twice a second. |
| `sysinfo.sh` | Quickshell `SystemMonitor` (`Super+M`) | The slow half, ~0.6 s, run on its own timer: `cpu_model`, `cpu_temp`, `nvme_temp`, `fan1/2` (hwmon paths discovered by name so they survive reboot reordering), `disks[]` (one per real local FS), `uptime`, and `procs[]` (top 12 by instantaneous CPU). |
| `hyprlock-art.sh` | hypridle pre-lock hook (and direct call) | Copies the current MPRIS album art to `$LOCK_ART` so hyprlock can display it. Also picks a random wallpaper for the lock background. |
| `restart.sh` | `Super+B` | Restarts every userspace service: xdg-desktop-portal, gnome-keyring, Quickshell, awww-daemon (restoring the saved wallpaper), hypridle, the four session units, cliphist, dotwatch. Sets GTK theme, fallback monitor. Logs OK/FAILED per step to stdout. |
| `update-all.sh` | `upi` fish function | Timeshift snapshot (aborts on failure), then dnf clean metadata/makecache --refresh, dnf update/autoremove, flatpak update/cleanup, `npm update -g`, `uv tool upgrade --all`, `bun upgrade`, `fisher update`. Continues past failed steps and prints a summary; warns if `dnf needs-restarting -r` says a reboot is needed. |
| `generate-avatar.sh` | `setup.sh` | Python+Pillow renders a circular initials avatar from `$USER`, installs to `/var/lib/AccountsService/icons/$USER` (used as lockscreen avatar). |
