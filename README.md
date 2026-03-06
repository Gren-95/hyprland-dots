# Dotfiles for my theme of hyprland (inspired by tailwind)

![Desktop Screenshot](screenshots/desktop.png)

> [!TIP]
> Use `setup.sh` for automated installation, or `dotfiles-manager.sh` for managing symlinks.

> [!NOTE]
> Built on Nobara 43. Some commands are Fedora/Nobara specific.

## Dependencies

- `hyprland` + `hyprland-devel` — compositor + plugin support
- `hyprshell` — Alt+Tab window switcher
- `kitty` — terminal
- `nautilus` — file manager
- `cliphist` + `wl-clipboard` — clipboard history
- `hyprpaper` `hyprpicker` `hypridle` — wallpaper, color picker, idle daemon
- `gtklock` + modules — lock screen
- `swaync` — notification center
- `grim` `slurp` `swappy` — screenshots
- `tesseract` — OCR from screenshots
- `swayosd` — OSD for volume/brightness
- `waybar` — status bar
- `rofi` — app launcher, menus
- `firefox` — browser
- `brightnessctl` `playerctl` — brightness and media control
- `pavucontrol` — audio mixer
- `polkit-gnome` — polkit agent
- `gnome-calendar` `gnome-keyring` — calendar, secrets
- `powerprofilesctl` — power profiles
- `jq` — JSON parsing (used by wallpaper script)

## Install Dependencies (Nobara 43)

### External repositories

```bash
sudo dnf copr enable lionheartp/Hyprland                    # hyprland
sudo dnf copr enable erikreider/SwayNotificationCenter      # swaync
sudo dnf copr enable washkinazy/wayland-wm-extras           # swayosd + gtklock
```

### Install all dependencies

```bash
sudo dnf install hyprland hyprland-devel hyprshell kitty nautilus cliphist \
  hyprpaper hyprpicker hypridle swaync grim slurp swappy tesseract \
  wl-clipboard swayosd waybar firefox rofi brightnessctl playerctl \
  pavucontrol polkit-gnome gnome-calendar gnome-keyring jq \
  powerprofilesctl gtklock gtklock-meta \
  gtklock-playerctl-module gtklock-userinfo-module \
  fish neovim ranger python3
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
- Set up script permissions
- Configure GTK theme and SwayOSD

### Wallpapers

Put your wallpapers in `~/Pictures/wallpapers/`. They are preloaded automatically on startup — no manual config needed.

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
