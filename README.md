# Dotfiles for my theme of hyprland (inspired by tailwind)

![Desktop Screenshot](screenshots/desktop.png)

> [!TIP]
> Use `setup.sh` for automated installation, or `dotfiles-manager.sh` for managing symlinks.

> [!NOTE]
> Built on Nobara 43. Some commands are Fedora/Nobara specific.

## Dependencies

- `hyprland` + `hyprland-devel` — compositor
- `kitty` — terminal
- `nautilus` — file manager
- `cliphist` + `wl-clipboard` — clipboard history
- `hyprpaper` `hyprpicker` `hypridle` `hyprlock` — wallpaper, color picker, idle daemon, lock screen
- `swaync` — notification center
- `grim` `slurp` `swappy` — screenshots
- `tesseract` — OCR from screenshots
- `gpu-screen-recorder` — screen recording
- `swayosd` — OSD for volume/brightness
- `waybar` — status bar
- `rofi` — app launcher, menus
- `firefox` — browser
- `brightnessctl` `playerctl` — brightness and media control
- `pavucontrol` — audio mixer
- `hyprpolkitagent` — polkit agent
- `gnome-calendar` `gnome-keyring` — calendar, secrets
- `powerprofilesctl` — power profiles
- `python3` + `python3-pillow` — avatar generation
- `jq` — JSON parsing
- `inotify-tools` — dotfile hot-reload daemon

## Install Dependencies (Nobara 43)

### External repositories

```bash
sudo dnf copr enable lionheartp/Hyprland                    # hyprland
sudo dnf copr enable erikreider/SwayNotificationCenter      # swaync
sudo dnf copr enable washkinazy/wayland-wm-extras           # swayosd
```

### Install all dependencies

```bash
sudo dnf install hyprland hyprland-devel kitty nautilus cliphist \
  hyprpaper hyprpicker hypridle hyprlock swaync grim slurp swappy tesseract \
  wl-clipboard swayosd waybar firefox rofi brightnessctl playerctl \
  pavucontrol polkit-gnome gnome-calendar gnome-keyring jq \
  powerprofilesctl gpu-screen-recorder inotify-tools \
  fish neovim ranger python3 python3-pillow
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
- Configure GTK theme and SwayOSD
- Optionally generate an initials avatar for the lock screen

### Wallpapers

Put your wallpapers in `~/Pictures/wallpapers/`. They are preloaded automatically on startup — no manual config needed. The lock screen background also updates to the current wallpaper automatically.

### Idle timeout

```bash
$EDITOR hypr/hypridle.conf
```

### Keybinds

```bash
$EDITOR hypr/modules/keys.conf
```

Press `Super+F1` in session to view all active keybinds.

### OSD

```bash
sudo systemctl enable --now swayosd-libinput-backend.service
```

### Screen Recording

`Super+Ctrl+R` — toggles screen recording. Recordings are saved to `~/Videos/Recordings/`.

Requires `gpu-screen-recorder`.

### Remote Access (wayvnc)

wayvnc is an optional VNC server for remote desktop access.

**Start/stop:** `Super+Shift+R` — toggles wayvnc on/off.

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
| `battery-notify.sh` | Notifies at 20% and 10% battery; dismisses alert when plugged in |
| `dotwatch.sh` | Watches dotfiles for changes and hot-reloads affected services |
| `media-inhibit.sh` | Prevents screen sleep during media playback |
| `network-notify.sh` | Notifies on network connect/disconnect |
| `swayosd-monitor.sh` | Monitors input events for OSD triggers |

### dotwatch — hot-reload

Edits to dotfiles are picked up automatically without restarting your session:

| File changed | Action |
|---|---|
| `waybar/style*.css`, `waybar/config*` | Restart waybar |
| `swaync/style.css` | Reload swaync CSS |
| `swaync/config.json` | Reload swaync config |
| `hypr/hyprland.conf`, `hypr/modules/*` | `hyprctl reload` |
| `hypr/hypridle.conf` | Restart hypridle |
| `hypr/hyprlock.conf` | Notification (applies on next lock) |
| `swayosd/style.css` | Restart swayosd-server |
| `gtk-3.0/gtk.css` | Notification (restart GTK apps to apply) |

## Optional Services

### Immich (photo sync)

Automatically uploads `~/Pictures/` to your Immich server every hour. Notifies when new photos are uploaded.

**Setup:**

```bash
npm install -g @immich/cli --prefix ~/.npm-global
immich login https://your-immich-server/api YOUR_API_KEY
```

Auth is stored in `~/.config/immich/auth.yml` (gitignored).

### Jellyfin (music sync)

Syncs your Jellyfin music library to `~/Music/` every 2 hours. Jellyfin is the master — tracks removed from Jellyfin are deleted locally. Notifies after each sync with a download/skip/remove summary.

**Setup:**

```bash
bash ~/.config/scripts/jellyfin-music-sync.sh
```

You will be prompted for your Jellyfin server URL and API key on first run. Config is stored in `~/.config/jellyfin/sync.conf` (gitignored). To reconfigure, delete the file and run the script again.

## Dotfiles Manager

```bash
./dotfiles-manager.sh status          # Check all symlink states
./dotfiles-manager.sh backup          # Create symlinks (backs up existing dirs)
./dotfiles-manager.sh backup --dry-run  # Preview without making changes
./dotfiles-manager.sh fix             # Fix broken or inconsistent symlinks
./dotfiles-manager.sh undo            # Restore backups and remove symlinks
```
