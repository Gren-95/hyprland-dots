# Install

Dependencies and manual setup. The one-command install is in the [README](../README.md#setup).

## Dependencies

- `hyprland` + `hyprland-devel` — compositor
- `quickshell` — bar, OSD, notifications, launcher, clipboard, power menu, keybinds viewer, workspace overview
- `kitty` — terminal
- `nautilus` — file manager
- `cliphist` + `wl-clipboard` — clipboard history (Quickshell shows the picker)
- `awww` `hyprpicker` `hypridle` `hyprlock` — wallpaper, color picker, idle daemon, lock screen
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
- `btop` — optional TUI system monitor

Fish plugin files are not tracked. They are declared in [`config/fish/fish_plugins`](../config/fish/fish_plugins);
on a fresh machine run `fisher update` ([fisher](https://github.com/jorgebucaran/fisher), see
[`config/fish/README.md`](../config/fish/README.md)) to restore them; the prompt is
[tide](https://github.com/IlanCosman/tide). Its colours come from
[`config/fish/tide-stone`](../config/fish/tide-stone) — `fish_variables` is gitignored, so on a new
machine apply them with `fish ~/.config/fish/tide-stone/apply.fish`.

## Install Dependencies (Nobara 44)

### External repositories

```bash
sudo dnf copr enable lionheartp/Hyprland       # hyprland
sudo dnf copr enable errornointernet/quickshell  # quickshell (or build from source)
```

### Install all dependencies

```bash
sudo dnf install hyprland hyprland-devel quickshell kitty nautilus cliphist \
  awww hyprpicker hypridle hyprlock grim slurp swappy tesseract \
  wl-clipboard firefox brightnessctl playerctl \
  gnome-keyring jq \
  powerprofilesctl gpu-screen-recorder inotify-tools \
  fish fzf zoxide ranger python3 python3-pillow
```

### Optional: Disktree (disk usage treemap)

[Disktree](https://github.com/tobi/disktree) draws a treemap of what fills a disk and lets you mark
and review what to remove before anything is deleted. It is not in the Fedora repositories, so
install the prebuilt release into `~/.local` (no root; needs a Vulkan-capable GPU). It then shows up
in the launcher, and `disktree --disk` scans the whole disk.

```bash
v=0.11.0   # newest: https://github.com/tobi/disktree/releases/latest
cd "$(mktemp -d)"
curl -fsSLO "https://github.com/tobi/disktree/releases/download/v$v/disktree-$v-x86_64-linux.tar.gz"{,.sha256}
sha256sum -c "disktree-$v-x86_64-linux.tar.gz.sha256"
tar -xzf "disktree-$v-x86_64-linux.tar.gz" && "./disktree-$v-x86_64-linux/install.sh"
bash ~/.config/scripts/disktree-theme.sh   # match the shell palette
# Launch it through disktree.sh, which scans /mnt/DATA by default:
sed -i "s|^Exec=.*disktree %f|Exec=bash $HOME/.config/scripts/disktree.sh %f|" ~/.local/share/applications/disktree.desktop
```

Disktree scans the home directory by default and neither crosses filesystems nor follows symlinks, so
a second disk such as `/mnt/DATA` (where `~/Documents` points) is invisible. `scripts/disktree.sh`
(and the `disktree` fish function) scan `$DATA_DIR` from `scripts/paths.sh` unless given a path or
option. The `sed` line points the launcher entry at it; run it again after upgrading Disktree, whose
installer rewrites the entry.

`disktree-theme.sh` writes `~/.local/state/omarchy/current/theme/colors.toml` from
`config/quickshell/Theme.qml`, the file Disktree reads its colours from. Run it again after
changing the palette; a running Disktree picks the change up.

## Manual Setup

```bash
git clone https://github.com/Gren-95/hyprland-dots.git ~/dotfiles
cd ~/dotfiles
chmod +x dots.sh
./dots.sh setup
```

The setup script will:
- Check for missing dependencies and offer to install them
- Create symlinks for all config directories
- Create required user directories (`~/Pictures/Screenshots`, `~/Music`, etc.)
- Set up script permissions
- Configure GTK theme
- Optionally generate an initials avatar for the lock screen

Firefox is the one config the setup script cannot link for you: its
chrome directory lives inside a profile whose name is generated at
install time. Point it at the repo by hand, then restart Firefox:

```bash
cd ~/.config/mozilla/firefox
profile=$(awk -F= '/^\[Install/{i=1} i && /^Default=/{print $2; exit}' profiles.ini)
ln -s ~/dotfiles/firefox/chrome "$profile/chrome"
```

`toolkit.legacyUserProfileCustomizations.stylesheets` must be `true`
in `about:config` for the stylesheets to load.
