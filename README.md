# Dotfiles for my theme of hyprland (inspired by tailwind)

[![lint](https://github.com/Gren-95/hyprland-dots/actions/workflows/lint.yml/badge.svg)](https://github.com/Gren-95/hyprland-dots/actions/workflows/lint.yml)

![Desktop Screenshot](screenshots/desktop.png)

## Gallery

The top bar (always visible):

![Bar](screenshots/gallery/bar.png)

Modals reachable from keybindings or the bar:

<table>
  <tr>
    <td align="center" width="33%"><img src="screenshots/gallery/spotlight.png" width="100%"/><br><strong>Spotlight</strong><br><kbd>Super</kbd>+<kbd>R</kbd></td>
    <td align="center" width="33%"><img src="screenshots/gallery/clipboard.png" width="100%"/><br><strong>Clipboard</strong><br><kbd>Super</kbd>+<kbd>V</kbd></td>
    <td align="center" width="33%"><img src="screenshots/gallery/quickactions.png" width="100%"/><br><strong>Quick Actions</strong><br><kbd>Super</kbd>+<kbd>A</kbd></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/gallery/network.png" width="100%"/><br><strong>Connectivity</strong><br>Wi-Fi + Bluetooth tabs<br><kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd></td>
    <td align="center"><img src="screenshots/gallery/audiopower.png" width="100%"/><br><strong>Audio &amp; Power</strong><br><kbd>Super</kbd>+<kbd>S</kbd></td>
    <td align="center"><img src="screenshots/gallery/systemmonitor.png" width="100%"/><br><strong>System Monitor</strong><br><kbd>Super</kbd>+<kbd>M</kbd></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/gallery/daypanel.png" width="100%"/><br><strong>Day Panel</strong><br>calendar + notifications<br><kbd>Super</kbd>+<kbd>N</kbd> / <kbd>Super</kbd>+<kbd>D</kbd></td>
    <td align="center"><img src="screenshots/gallery/powermenu.png" width="100%"/><br><strong>Power Menu</strong><br><kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd></td>
    <td align="center"><img src="screenshots/gallery/keybinds.png" width="100%"/><br><strong>Keybinds Viewer</strong><br><kbd>Super</kbd>+<kbd>F1</kbd></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/gallery/wallpaper.png" width="100%"/><br><strong>Wallpaper Picker</strong><br><kbd>Super</kbd>+<kbd>W</kbd></td>
    <td align="center"><img src="screenshots/gallery/toast.png" width="100%"/><br><strong>Notification Toast</strong><br>auto-shown on incoming notification</td>
    <td></td>
  </tr>
</table>

> [!TIP]
> Use `setup.sh` for automated installation, or `dotfiles-manager.sh` for managing symlinks.

> [!NOTE]
> Built on Nobara 44 with Hyprland 0.56.2 and Quickshell 0.3.1. The Hyprland
> config is Lua, which needs Hyprland 0.55+. Some commands are Fedora/Nobara
> specific.

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how Hyprland, Quickshell, scripts, and cron fit together
- [`KEYBINDS.md`](KEYBINDS.md) — flat keybind reference (live viewer: `Super+F1`)
- [`quickshell/DESIGN.md`](quickshell/DESIGN.md) — QML widget conventions and recipes
- [`scripts/README.md`](scripts/README.md) — per-script breakdown (what runs when)
- [`hypr/MODULES.md`](hypr/MODULES.md) — what each `hypr/modules/*.lua` owns

## Dependencies

- `hyprland` + `hyprland-devel` — compositor
- `quickshell` — bar, OSD, notifications, launcher, clipboard, power menu, keybinds viewer, workspace overview
- `kitty` — terminal
- `nautilus` — file manager
- `cliphist` + `wl-clipboard` — clipboard history (Quickshell shows the picker)
- `hyprpaper` `hyprpicker` `hypridle` `hyprlock` — wallpaper, color picker, idle daemon, lock screen
- `grim` `slurp` `swappy` — screenshots
- `tesseract` — OCR from screenshots
- `gpu-screen-recorder` — screen recording
- `firefox` — browser
- `brightnessctl` `playerctl` — brightness and media control (Quickshell OSD watches `/sys` for changes)
- `gnome-keyring` — secrets store
- `powerprofilesctl` — power profiles
- `python3` + `python3-pillow` — avatar generation
- `jq` — JSON parsing
- `inotify-tools` — dotfile hot-reload daemon
- `fish` `fzf` `zoxide` — shell, fuzzy finder, directory jumping
- `wayvnc` — optional VNC server (`Super+Ctrl+R`)
- `ranger` — optional TUI file manager

Fish plugins are declared in [`fish/fish_plugins`](fish/fish_plugins) and restored by
[fisher](https://github.com/jorgebucaran/fisher); the prompt is
[tide](https://github.com/IlanCosman/tide).

## Install Dependencies (Nobara 44)

### External repositories

```bash
sudo dnf copr enable lionheartp/Hyprland       # hyprland
sudo dnf copr enable errornointernet/quickshell  # quickshell (or build from source)
```

### Install all dependencies

```bash
sudo dnf install hyprland hyprland-devel quickshell kitty nautilus cliphist \
  hyprpaper hyprpicker hypridle hyprlock grim slurp swappy tesseract \
  wl-clipboard firefox brightnessctl playerctl \
  gnome-keyring jq \
  powerprofilesctl gpu-screen-recorder inotify-tools \
  fish fzf zoxide ranger python3 python3-pillow
```

## Setup

### One-command Install (Recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Gren-95/hyprland-dots/main/install.sh)
```

This will clone the repo to `~/dotfiles` and run the setup script automatically.

### Manual Setup

```bash
git clone https://github.com/Gren-95/hyprland-dots.git ~/dotfiles
cd ~/dotfiles
chmod +x setup.sh
./setup.sh
```

The setup script will:
- Check for missing dependencies and offer to install them
- Create symlinks for all config directories
- Create required user directories (`~/Pictures/Screenshots`, `~/Music`, etc.)
- Set up script permissions
- Configure GTK theme
- Optionally generate an initials avatar for the lock screen

### Wallpapers

Put your wallpapers in `~/Pictures/wallpapers/`. They are preloaded automatically on startup — no manual config needed. The lock screen background also updates to the current wallpaper automatically.

### Idle timeout

```bash
$EDITOR hypr/hypridle.conf
```

### Keybinds

```bash
$EDITOR hypr/modules/keys.lua
```

Press `Super+F1` in session to view all active keybinds.

### OSD

Volume, brightness, and keyboard-backlight OSDs are rendered by Quickshell
(`quickshell/Osd.qml`). It polls `/sys/class/backlight` and `/sys/class/leds`
so any process changing brightness — key, `brightnessctl`, `hypridle` —
triggers the OSD automatically. No daemon to enable.

### Screen Recording

`Super+Shift+R` — toggles screen recording. Recordings are saved to `~/Videos/Recordings/`.

Requires `gpu-screen-recorder`. A brief toast appears top-right on start/stop
(it auto-hides during recording so it doesn't appear in the captured video).

### Remote Access (wayvnc)

wayvnc is an optional VNC server for remote desktop access.

**Start/stop:** `Super+Ctrl+R` — toggles wayvnc on/off.

**Connect:** Use any VNC viewer and connect to `<local-ip>:5900`.

**Security:** Default config binds to `0.0.0.0` with no auth — suitable for trusted LAN only. For remote access, use [Tailscale](https://tailscale.com).

To add password auth, edit `wayvnc/config`:

```ini
enable_auth=true
username=user
password=yourpassword
```

## Background Daemons

These run automatically on login via `restart.sh` and restart cleanly on each session.

| Script | Purpose |
|---|---|
| `battery-notify.sh` | Notifies at 20% and 10% battery; dismisses the alert when plugged in |
| `power-auto.sh` | Sets the power profile from AC state and battery level (`performance` on AC, `balanced` ≥30%, `power-saver` below) |
| `media-inhibit.sh` | Prevents screen sleep during media playback |
| `fullscreen-inhibit.sh` | Prevents idle while a window is fullscreen |
| `dotwatch.sh` | Watches dotfiles for changes and hot-reloads affected services |

### dotwatch — hot-reload

Edits to dotfiles are picked up automatically without restarting your session:

| File changed | Action |
|---|---|
| `hypr/hyprland*.lua`, `hypr/modules/*` | `hyprctl reload` |
| `hypr/hypridle.conf` | Restart hypridle |
| `hypr/hyprlock.conf` | Notification (applies on next lock) |
| `gtk-3.0/gtk.css` | Notification (restart GTK apps to apply) |
| `quickshell/*` | Quickshell auto-reloads on file changes |

## Scheduled Jobs

| Job | Schedule | Mechanism |
|---|---|---|
| Immich photo sync | Hourly, when enabled | crontab entry between `# QSSYNC:immich` markers |
| Jellyfin music sync | Daily | `jellyfin-sync.timer` (user timer, `Persistent=true`) |
| Battery charge cap | Daily at 00:05 | `battery-charge-schedule.timer` (system timer, `Persistent=true`) |

Both sync jobs are toggled from Quick Actions (`Super+A`), which calls
`sync-toggle.sh`. It comments or uncomments the cron line for Immich and
enables or disables the user timer for Jellyfin, so a disabled job leaves its
schedule in place rather than losing it.

`Persistent=true` matters on a laptop: a timer that fires while the machine is
asleep runs on the next boot instead of being skipped.

The battery cap runs uncapped Friday through Sunday and applies a 75–80% cap on
weekdays, so the cell ages slower without getting in the way at the weekend. Its
script is deployed as a **copy** to `/usr/local/bin` — systemd runs it as root,
so `ExecStart` must not point into a user-writable path.

## Optional Services

### Immich (photo sync)

Uploads `~/Pictures/` to your Immich server every hour while enabled. Notifies when new photos are uploaded.

**Setup:**

```bash
npm install -g @immich/cli --prefix ~/.npm-global
immich login https://your-immich-server/api YOUR_API_KEY
```

Auth is stored in `~/.config/immich/auth.yml` (gitignored).

### Jellyfin (music sync)

Syncs your Jellyfin music library to `~/Music/` once a day. Jellyfin is the master — tracks removed from Jellyfin are deleted locally. Notifies after each sync with a download/skip/remove summary.

**Setup:**

```bash
bash ~/.config/scripts/jellyfin-music-sync.sh
```

You will be prompted for your Jellyfin server URL and API key on first run. Config is stored in `~/.config/jellyfin/sync.conf` (gitignored). To reconfigure, delete the file and run the script again.

### Windows VM (WinApps)

`winvm-toggle.sh` starts and stops the `dockur/windows` container that backs
WinApps, exposed as a Quick Actions toggle. Stopping the container is what
actually frees the VM's 6 GB of RAM. Needs `docker` and `freerdp`.

## Dotfiles Manager

```bash
./dotfiles-manager.sh status          # Check all symlink states
./dotfiles-manager.sh backup          # Create symlinks (backs up existing dirs)
./dotfiles-manager.sh backup --dry-run  # Preview without making changes
./dotfiles-manager.sh fix             # Fix broken or inconsistent symlinks
./dotfiles-manager.sh undo            # Restore backups and remove symlinks
```

## Development

[`.github/workflows/lint.yml`](.github/workflows/lint.yml) runs on every push and
pull request. [`.githooks/pre-commit`](.githooks/pre-commit) runs the same checks
against the index at commit time — `setup.sh` enables it, or turn it on by hand:

```bash
git config core.hooksPath .githooks
```

Each check is skipped with a note when its tool is missing, so the hook still
works on a machine without Hyprland. Bypass it with `git commit --no-verify`.

The checks by hand:

```bash
shellcheck -S warning $(git ls-files '*.sh' | grep -v '^ranger/scope.sh$')
luac -p $(git ls-files '*.lua')
Hyprland --verify-config -c "$PWD/hypr/hyprland.lua"
./dotfiles-manager.sh status
```

`--verify-config` catches unknown config keys as well as Lua syntax errors, so
it is worth running before a reload rather than finding out from a live session.
