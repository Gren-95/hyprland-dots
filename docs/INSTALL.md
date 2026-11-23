# Install

Dependencies and manual setup. The one-command install is in the [README](../README.md#setup).

## Dependencies

- `hyprland` + `hyprland-devel` — compositor
- `quickshell` — bar, OSD, notifications, launcher, clipboard, power menu, workspace overview
- `kitty` — terminal
- `nautilus` — file manager
- `cliphist` + `wl-clipboard` — clipboard history (Quickshell shows the picker)
- `awww` `hyprpicker` `hypridle` `hyprlock` — wallpaper, color picker, idle daemon, lock screen
- `hyprshutdown` — Logout in the power menu (closes apps before Hyprland exits)
- Iosevka Nerd Font — font and icon glyphs everywhere; not packaged, `dots.sh setup` fetches it (see below)
- `grim` `slurp` `swappy` — screenshots
- `tesseract` — OCR from screenshots
- `gpu-screen-recorder` — screen recording
- `firefox` — browser
- `brightnessctl` `playerctl` — brightness and media control (Quickshell OSD watches `/sys` for changes)
- `pulseaudio-utils` `bluez` — `pactl` and `bluetoothctl` for the Bluetooth audio recovery unit
- `ImageMagick` — OCR preprocessing and lock screen album art
- `timeshift` — pre-update snapshot in `upi` (it stops without one; `upi --no-snapshot` skips it)
- `gnome-keyring` — secrets store
- `powerprofilesctl` — power profiles
- `python3` + `python3-pillow` — avatar generation
- `jq` — JSON parsing
- `inotify-tools` — dotfile hot-reload daemon
- `fish` `fzf` — shell, fuzzy finder (the `kb` keybind search)
- `ranger` — TUI file manager
- `cargo` — builds the settings app ([`apps/settings`](../apps/settings/README.md)); `adwaita-sans-fonts` is its text font and `pipewire-utils` (`pw-dump`) feeds its Sound panel, `zenity` is its folder chooser
- `gnome-font-viewer` — font previews in Nautilus (TTF, OTF, WOFF; WOFF2 through `thumbnailers/woff2.thumbnailer`)
- `mpv` `network-manager-applet` `libnotify` `upower` — music player, tray network applet, notifications, battery
- Optional, per feature: `zoxide` (directory jumping), `wayvnc` (remote access, `Super+Ctrl+R`), `btop`
  (TUI system monitor), `hyprsunset` (night light), `tailscale`, `docker` (Windows VM, games browser),
  `evtest` (hold-Super detection for the overview and wallpaper deck), `cronie` (Immich schedule),
  `expect` (`ledvance.sh`), `unzip`, the Immich CLI, and Disktree (below)

Fish plugin files are not tracked. They are declared in [`config/fish/fish_plugins`](../config/fish/fish_plugins);
on a fresh machine run `fisher update` ([fisher](https://github.com/jorgebucaran/fisher), see
[`config/fish/README.md`](../config/fish/README.md)) to restore them; the prompt is
[tide](https://github.com/IlanCosman/tide). Its colours come from
[`config/fish/tide-stone`](../config/fish/tide-stone) — `fish_variables` is gitignored, so on a new
machine apply them with `fish ~/.config/fish/tide-stone/apply.fish`.

## Install Dependencies (Nobara 44)

### External repositories

```bash
sudo dnf copr enable lionheartp/Hyprland       # hyprland, quickshell, awww, hyprshutdown
sudo dnf copr enable errornointernet/quickshell  # only if lionheartp has no quickshell for your release
```

### Install all dependencies

`dots.sh setup` installs these for you. By hand, this is the same list as
`DEPS_DNF` in [`config/scripts/lib/deps.sh`](../config/scripts/lib/deps.sh):

```bash
sudo dnf install hyprland hyprland-devel quickshell kitty nautilus cliphist awww \
  hyprpicker hypridle hyprlock grim slurp swappy tesseract \
  tesseract-langpack-est ImageMagick wl-clipboard firefox \
  brightnessctl playerctl powerprofilesctl gpu-screen-recorder \
  network-manager-applet libnotify upower mpv bc curl gnome-keyring \
  jq inotify-tools pulseaudio-utils bluez hyprshutdown timeshift fzf \
  gnome-font-viewer squashfs-tools cargo pipewire-utils zenity fish ranger \
  python3 python3-pillow python3-numpy python3-gobject unzip liberation-sans-fonts \
  adwaita-sans-fonts
```

Optional extras are listed under [Dependencies](#dependencies) and in
`DEPS_OPTIONAL` in `deps.sh`; install the ones for features you use, e.g.
`sudo dnf install zoxide hyprsunset wayvnc btop`.

### Font

Iosevka Nerd Font is not in the Fedora repositories. `dots.sh setup` installs it; by hand:

```bash
mkdir -p ~/.local/share/fonts/IosevkaNerdFont
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Iosevka.tar.xz |
  tar -xJ -C ~/.local/share/fonts/IosevkaNerdFont --wildcards '*.ttf'
fc-cache -f
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
- Check for missing dependencies and offer to install them (COPRs + `DEPS_DNF`)
- Create symlinks for every config in `CONFIG_ITEMS` (existing ones are backed up)
- Create required user directories (`~/Pictures/Screenshots`, `~/Music`, etc.)
- Install Iosevka Nerd Font
- Set script permissions and enable the tracked git hooks
- Link the Nautilus thumbnailers (3MF, PSD, STL, GLB, OBJ, WOFF2, AppImage), and install the programs the 3D and AppImage ones run to `/usr/local/bin` (sudo)
- Build the settings app to `~/.local/bin/settings` and add its launcher entry
- Build `upi`, the updater, to `~/.local/bin/upi`
- Install and enable the systemd user units (`dots.sh units`)
- Configure the GTK theme (and the Tailscale operator when Tailscale is installed)
- Install `system/sysctl.d/90-dots-inotify.conf` to `/etc/sysctl.d` (sudo): 1024 inotify instances per user instead of 128, so the session D-Bus can always reload its config
- Optionally set up the Immich CLI, Jellyfin music sync and Gcode Viewer (skipped with `--yes`)
- Optionally generate an initials avatar for the lock screen

A step that fails is reported and setup carries on; the summary lists what did
not complete, and running setup again repeats only what is needed.

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
