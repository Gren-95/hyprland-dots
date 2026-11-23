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
| `lib/shell-ipc.sh` | `shell_ipc <target> <function> [args]`: best-effort `qs ipc call` into Quickshell (silent no-op when it is not running). Used by `screenrecord.sh`, `wayvnc-toggle.sh`, `sync-toggle.sh` and `claude-activity.sh` to report state changes, so the shell never polls for them. |
| `lib/inhibit.sh` | `inhibit_start <app> <reason>` / `inhibit_stop`: holds an `org.freedesktop.ScreenSaver` inhibitor on a long-lived D-Bus connection. Used by `idle-inhibit-hold.sh`, `idle-inhibit-toggle.sh`, and `gamemode.sh`. |
| `lib/server.sh` | `server_reachable <url>`: succeeds when the server answers at all (any HTTP status), fails on refused, DNS or timeout. Used by `immich-sync.sh` and `jellyfin-music-sync.sh` to skip quietly away from home. |
| `lib/env.sh` | `load_util_env` loads `util.env` (`KEY=VALUE`) into the environment. |
| `lib/screenshot.sh` | `capture_region "X,Y WxH"`: grim, wl-copy, notify, print path. Folder, PNG or JPEG, cursor and clipboard copy come from the `shot-*` settings (settings app, Screenshots & recording panel). Shared by `screenshot.sh` and `screenshot-window.sh`. |
| `lib/settings.sh` | `setting <file> <default>`, `valid <value> <regex> <default>`, `setting_dir <file> <default>`: read the Quickshell settings store from scripts (screenshots, screen recording). |
| `lib/deps.sh` | Required/optional command lists and the dnf package list, shared by `dots.sh setup` and `doctor.sh`. |
| `paths.sh` | Canonical user-path env vars (`PICTURES_DIR`, `WALLPAPER_DIR`, `RECORDINGS_DIR`, `CACHE_DIR`, etc.). Sourced by every consumer. |

## Helpers and config

| File | Purpose |
|---|---|
| `hypr-binds.sh` | Emits `hyprctl binds -j` with the real dispatcher/arg filled in. Lua-registered binds all report `__lua`, so this re-derives each action from `hypr/**/*.lua` and merges it back, keyed on (modmask, key). Used by the settings app's key binds page (Keyboard), the `kb` fish function and `docs/gen-keybinds.sh`. |
| `extract.sh` | Unpacks every archive in the cwd (or a given path): `.zip`, `.tar.gz`, `.tar.bz2`, `.rar`, `.7z`. |
| `ledvance.sh` | Pairs a Tuya/Ledvance LED through the upstream pairing script. Reads `LEDVANCE_USER`, `LEDVANCE_PASSWORD` and `LEDVANCE_PATH` from `util.env` itself; fish deliberately does not export the password. |
| `util.env.example` | Template for the gitignored `util.env` (Ledvance credentials, `RPGMDECRYPT_PATH`). Copy to `util.env` and fill in; `fish/conf.d/util-env.fish` loads the non-secret keys into fish. |

## Daemons (autostart / restart.sh)

`battery-notify`, `power-auto` and `bt-audio-recover` run as systemd user units
(`systemd/user/*.service`, installed and enabled by `dots.sh units`); `restart.sh` restarts them with
`systemctl --user restart`. `dots.sh units` also installs `jellyfin-sync.service` and
`.timer` without enabling them; the Services panel toggle (`sync-toggle.sh`) does that.

| File | Spawned by | What it does |
|---|---|---|
| `battery-notify.sh` | systemd user unit (restarted by `restart.sh`) | Polls `/sys/class/power_supply/BAT*` every 60s. Sends critical/normal notifications at 10% / 20% (replace-key `battery`). |
| `power-auto.sh` | systemd user unit (restarted by `restart.sh`) | Listens to `upower --monitor-detail`. Sets `performance` on AC, `balanced` on battery ≥30%, `power-saver` <30% via `powerprofilesctl`. Idempotent (skips if already at target). |
| `bt-audio-recover.sh` | systemd user unit (restarted by `restart.sh`) | Watches `pactl subscribe` for card events. A connected `bluez_card.*` still on the `off` profile 5 s after the last event is set to `a2dp-sink` (AirPods can connect and stay off after a reconnect) and a notification says so. Exits non-zero if the sound server goes away so systemd restarts it. |
| `build-librepods.sh` | manual | Builds LibrePods at a pinned commit with the patches in `librepods/` (battery and controls JSON for `AirPodsBattery.qml`, a command socket for `airpods.sh`, AAC preferred over SBC-XQ) and installs it to `~/.local/bin/librepods`. |
| `airpods.sh` | Bluetooth flyout AirPods section | `mode off\|anc\|transparency\|adaptive` and `conversation on\|off` go to the patched librepods over `$XDG_RUNTIME_DIR/librepods.sock`; `codec <MAC> aac\|sbc-xq\|sbc`, `codec-status <MAC>` and `reset-audio <MAC>` (card off and back, for a bud that went silent) act on the PipeWire card. |
| `build-hyprexpo.sh` | dnf5 action (`--install-hook`) | Rebuilds the local hyprexpo plugin from `~/.local/src/hyprexpo` when the installed one does not embed the current Hyprland commit hash, and installs it to `~/.local/lib/hyprland/plugins/` with an atomic rename. Sends a notification and logs to `~/.cache/hyprexpo-build.log`. `--install-hook` (sudo, once) writes `/etc/dnf/libdnf5-plugins/actions.d/hyprexpo.actions`, which runs the script after every dnf transaction that updates `hyprland-devel`. The new build loads at the next Hyprland start. |
| `dotwatch.sh` | `restart.sh` | `inotifywait` on the dots repo. Reloads Hyprland / hypridle config in-place when their files change. Hot-reloads `gtk-3.0/gtk.css` notify and hyprlock config notify. |
| `immich-sync.sh` | cron (via `sync-toggle.sh`) | Runs once by default. `--daemon` flag for legacy loop mode (unused by current setup). Uses `immich-rs` (`~/.local/bin/immich-rs`) to upload `$PICTURES_DIR` (excluding `**/{ocr,Screenshots}/**`). |
| `jellyfin-music-sync.sh` | `jellyfin-sync.timer` user timer (daily; switched by `sync-toggle.sh`) | Same shape — single run by default, `--daemon` for the loop. Mirrors Jellyfin music library to `$MUSIC_DIR`, deleting local files no longer on the server. |

## Toggles (Hyprland keybind / Quickshell UI)

| File | Triggered by | What it does |
|---|---|---|
| `default-app.sh` | Hyprland binds (`run`), the settings app's Default apps panel (`set`) | Which app fills a role — browser, terminal, editor, filemanager. `get` prefers XDG's own answer where one exists; `set` writes `~/.config/default-apps.conf` and registers the XDG default for browser/file manager; `run` resolves the entry across the XDG application directories and launches it, falling back to kitty/nautilus when nothing is chosen. The settings app's Default apps panel sets these roles. The browser is read from the `x-scheme-handler/https` default. |
| `clipboard-watch.sh` | restart.sh, settings app (Privacy) | (Re)starts `wl-paste --watch cliphist store` with the `clipboard-max-items` history length. |
| `services-status.sh` | Settings app (Services, Sync) | One probe for the whole panel: prints `key=value` pairs on a single line — each session daemon's pgrep state, wayvnc, the WinApps container, both sync schedules, and the Jellyfin timer's next run as a unix timestamp. |
| `wayvnc-toggle.sh` | Services panel "Remote access" toggle, or `Super+Ctrl+R` | Starts wayvnc if not running (bound to the Tailscale IPv4 when available, else loopback), waits until the port listens, kills it if running. Notifies only on failure. |
| `sync-toggle.sh` | Services panel "Immich/Jellyfin sync" toggles | Immich: manages a cron entry between `# QSSYNC:immich` markers (off with a note when crontab is missing). Jellyfin: enables or disables `jellyfin-sync.timer`; `schedule jellyfin` writes a drop-in.  Commands: `status [all\|<kind>]`, `toggle <kind>`, `enable <kind>`, `disable <kind>`, `schedule <kind> '<cron-expr>'`. Self-installs commented-out lines on first call. |
| `games-browser-toggle.sh` | Services panel "Games browser" row | `toggle\|start\|stop\|status` for the games-browser docker compose service (web UI on `http://127.0.0.1:8080/`); `status` prints 1 or 0. |
| `winvm-toggle.sh` | Services panel "Windows VM" row | `toggle\|start\|stop\|status [--force]` for the WinApps Windows container. Stopping it is what frees the VM's RAM (WinApps' own pause keeps it resident); `status` prints 1 or 0. |

## New helpers

| File | What it does |
|---|---|
| `doctor.sh` | Read-only health check: required commands, user units, executable bits, dots.sh symlinks. Exit 1 on failure. |
| `screenshot-window.sh` | Screenshot of the active window (`hyprctl activewindow -j`), same save/copy/notify as `screenshot.sh`. |
| `gallery-shots.sh` | Retakes the README gallery pictures: switches to an empty workspace, opens each popup via its Quickshell global shortcut (and fires a test notification for the toast), then crops to the area that differs from a baseline capture. `gallery-shots.sh [name...]` retakes only named shots, `--list` prints them. Restores your workspace. Swaps the clipboard history for demo entries and strips the owner prefix from Bluetooth names while shooting, then restores both. Skips `desktop.png`, `bar.png`, `wallpaper.png` and `lockscreen.png` (taken by hand). |
| `night.sh` | `toggle\|on\|off\|status\|resume\|apply` night light via `hyprsunset`. Temperature and an optional from/to schedule come from the `night-*` settings (settings app, Appearance); a schedule runs as hyprsunset profiles in `~/.config/hypr/hyprsunset.conf`. `resume` starts a scheduled one at login, `apply` restarts a running one with new settings. |
| `scratchpad.sh` | Toggle a drop-down kitty on the `special:scratchpad` workspace. |
| `music.sh` | `start\|stop\|toggle`: shuffle-plays every audio file under `~/Music` in a background mpv (`Super+Shift+M`, `Super+Shift+K`, `music` fish function). The player is recognised by its IPC socket in `$XDG_RUNTIME_DIR`, so stop leaves other mpv windows alone and start never runs a second copy. |
| `lid.sh` | `close\|open` handler for the lid switch binds in `hypr/modules/monitors.lua`. Close locks the session (`loginctl lock-session`) unless an external monitor is connected, then DPMS-offs `eDP-1`; open turns it back on and restores brightness. Lock, suspend or only the screen off per the `lid-close-action` setting. |
| `window-tools.sh` | `tiled-fullscreen` toggles tiled fullscreen (`Super+Ctrl+F`); `width save\|restore` remembers and re-applies a window's width per app and workspace (`Super+Alt+Home` / `Super+Home`). State in `~/.local/state/window-tools/`. |
| `disktree.sh` | Starts Disktree on `$DATA_DIR` (`/mnt/DATA`, set in `paths.sh`) when given no arguments, because Disktree's default (the home directory) is on another disk and it does not cross filesystems or follow symlinks. A path or option is passed through. The launcher entry and the `disktree` fish function both run it. |
| `disktree-theme.sh` | Writes `~/.local/state/omarchy/current/theme/colors.toml` from `quickshell/Theme.qml`, the palette file [Disktree](../../docs/INSTALL.md#optional-disktree-disk-usage-treemap) reads. Run it after installing Disktree or changing the palette. |
| `idle-inhibit-toggle.sh` | Manual idle inhibit toggle; PID in `$XDG_RUNTIME_DIR/idle-inhibit.pid`. |
| `claude-activity.sh` | Claude Code hooks | Reports working Claude Code sessions to Quickshell `IdleService` (`start`, `beat`, `stop`, `prune`), so the screen does not idle-lock mid-task. One file per session under `$XDG_RUNTIME_DIR/claude-activity/`; a session untouched for 15 minutes stops counting. Hook setup is in `docs/DAEMONS.md`. |
| `idle-inhibit-hold.sh` | Started by Quickshell `IdleService` while media plays or a window is fullscreen. Holds a ScreenSaver inhibitor until terminated; the kernel ends it if Quickshell dies. |
| `gamemode.sh` | Game mode `{toggle\|on\|off\|status}`: animations/gaps/rounding off, performance profile; Quickshell hides the bar and enables DND. Holds an idle inhibitor and pauses Immich/Jellyfin sync, night light and running Docker containers, then resumes only what it paused. State in `$XDG_RUNTIME_DIR/gamemode`, paused items in `gamemode.paused`. Each part can be switched off in the settings app (Gaming, `gamemode-*`); `feral` writes `~/.config/gamemode.ini` so Feral GameMode (`gamemoderun`) turns it on and off. |
| `autostart-apps.sh` | Starts the apps in `~/.config/autostart` once per login (restart.sh runs it; a marker in `$XDG_RUNTIME_DIR` keeps a shell restart from starting them again). Follows the XDG rules: Hidden, X-GNOME-Autostart-enabled, OnlyShowIn/NotShowIn, TryExec. The settings app's Services panel manages the entries. |
| `games.sh` | `list`: installed Steam games from every library as JSON (name, app id, cover art from Steam's cache), without Proton and runtimes. Read by the launchers' Games view (`GamesService.qml`). |

## One-shots (keybind-triggered)

| File | Keybind / invocation | What it does |
|---|---|---|
| `screenshot.sh` | Quickshell `RegionSelector` (`Super+Shift+S`) | Accepts a pre-computed `"X,Y WxH"` region as `$1` (falls back to `slurp -d` if no arg). `grim` → save to `$SCREENSHOTS_DIR` → `wl-copy` → notify → echo the saved path on stdout (RegionSelector reads it to open ScreenshotActions). |
| `screenshot-ocr.sh` | `Super+Ctrl+Shift+S` or ScreenshotActions "OCR" | Accepts a pre-captured image file as `$1` (falls back to `slurp+grim` otherwise). ImageMagick preprocess (3× upscale, optional invert, contrast stretch) → `tesseract` (eng+est) → `wl-copy` text + notify with preview. |
| `screenrecord.sh` | `Super+Shift+R` (or Quick Actions Record) | Toggles `gpu-screen-recorder` with `-w screen` (DRM capture), using the `record-*` options of the settings store (folder, container, fps, quality, codec, cursor, audio; set in the settings app's Recording panel). PID stored in `$XDG_RUNTIME_DIR/screenrecord.pid`; start failures and stops notify. Reports starts and stops to Quickshell with `qs ipc call recorder` (`lib/shell-ipc.sh`). |
| `wallpaper.sh` | `Super+Shift+N`, WallpaperDeck | Accepts an absolute path as `$1` to set a specific wallpaper; no arg picks a random one from `$WALLPAPER_DIR`. Applies via `awww img` to every output; GIFs animate. |
| `wallpaper-thumbs.sh` | WallpaperDeck | Makes 520x728 JPEG card thumbnails for the given wallpapers in `~/.cache/wallpaper-thumbs` (parallel, keyed by path, size and mtime; stale ones deleted) and prints `wallpaper<TAB>thumbnail` lines. Lets the deck show huge PNGs and WebP files that Qt could not decode in time or at all. |
| `sysfast.sh` | Quickshell `SystemMonitor` (`Super+M`) | The cheap half of the monitor's data as one JSON line, ~45 ms: cumulative CPU counters (total and per core), load, frequency, memory breakdown, network and disk byte counters with a timestamp. The UI turns differences into rates and percentages, so it can sample twice a second. |
| `sysinfo.sh` | Quickshell `SystemMonitor` (`Super+M`) | The slow half, ~0.6 s, run on its own timer: `cpu_model`, `cpu_temp`, `nvme_temp`, `fan1/2` (hwmon paths discovered by name so they survive reboot reordering), `disks[]` (one per real local FS), `uptime`, and `procs[]` (top 12 by instantaneous CPU). |
| `icon-path.sh` | Sound popup app rows | Prints the file of an app icon from the icon theme (user icons, the current theme from `icon-theme.sh get`, hicolor, then /usr/share/pixmaps), or nothing. The app rows load it with `file://` because Quickshell's icon provider drew nothing when the name arrived through a binding. |
| `icon-theme.sh` | Settings app Appearance panel (icon and cursor themes), `restart.sh`, `icon-path.sh` | `list` prints the installed icon themes as JSON with eight sample icons each, taken from the theme itself; `get` prints the current theme (from `gtk-3.0/settings.ini`); `set <id>` writes it to both GTK `settings.ini` files, `hypr/hyprqt6engine.conf` and gsettings, then restarts Quickshell, which reads its icon theme only at start. |
| `cursor-theme.sh` | Settings app Appearance panel (icon and cursor themes) | `list` runs `cursor-previews.py`; `get` prints the apps' and Hyprland's cursor theme from the `hl.env` lines in `hypr/modules/autostart.lua`; `set <id>` writes them (an XCursor theme goes to apps and Hyprland, a Hyprcursor theme to Hyprland only), sets gsettings and runs `hyprctl setcursor`; `size <px>` sets the cursor size the same ways. |
| `cursor-previews.py` | `cursor-theme.sh list` | Lists XCursor and Hyprcursor themes as JSON and renders eight sample cursors of each to `~/.cache/dots/cursor-previews` (PNG from Xcursor files, the packed image from `.hlc` archives). |
| `hyprlock-art.sh` | hypridle pre-lock hook (and direct call) | Copies the current MPRIS album art to `$LOCK_ART` so hyprlock can display it. Also points the lock background at a random wallpaper, the desktop one or a chosen picture (`lock-background`). |
| `hyprlock-status.sh` | `hypr/hyprlock.conf` labels | Prints the battery line or the current track title / artist for the lock screen. Prints nothing when there is nothing to show. |
| `hyprlock-weather.sh` | `hypr/hyprlock.conf` label | Prints the current weather for the lock screen corner, using the quickshell weather settings and open-meteo. Caches the last reading for when the network is down. |
| `restart.sh` | `Super+B` | Restarts every userspace service: xdg-desktop-portal, gnome-keyring, Quickshell, awww-daemon (restoring the saved wallpaper), hypridle, the four session units, cliphist, dotwatch. Sets GTK theme, fallback monitor. Logs OK/FAILED per step to stdout. |
| `generate-avatar.sh` | `dots.sh setup`, settings app (Users) | Python+Pillow renders a circular initials avatar from `$USER` and sets it through AccountsService (`SetIconFile` over D-Bus, no sudo), which keeps it in `/var/lib/AccountsService/icons/$USER` (used as lockscreen avatar). |
