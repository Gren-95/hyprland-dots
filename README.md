# Dotfiles for my theme of hyprland (inspired by tailwind)

[![lint](https://github.com/Gren-95/hyprland-dots/actions/workflows/lint.yml/badge.svg)](https://github.com/Gren-95/hyprland-dots/actions/workflows/lint.yml)

![Desktop Screenshot](screenshots/desktop.png)

## Gallery

The top bar (always visible):

![Bar](screenshots/gallery/bar.png)

Modals reachable from keybindings or the bar:

<table>
  <tr>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/spotlight.png" width="100%"/><br><strong>Launcher</strong><br>apps, actions, calculator<br><kbd>Super</kbd>+<kbd>R</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/clipboard.png" width="100%"/><br><strong>Clipboard</strong><br>history with thumbnails<br><kbd>Super</kbd>+<kbd>V</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/quickactions.png" width="100%"/><br><strong>Quick Actions</strong><br>microphone, screenshot, record, color picker<br><kbd>Super</kbd>+<kbd>A</kbd></td>
  </tr>
  <tr>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/network.png" width="100%"/><br><strong>Bluetooth</strong><br>paired devices, scan, pairing<br><kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>B</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/sound.png" width="100%"/><br><strong>Sound</strong><br>output, input, device dropdowns<br><kbd>Super</kbd>+<kbd>S</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/power.png" width="100%"/><br><strong>Power</strong><br>battery, profile, backlight, session<br><kbd>Super</kbd>+<kbd>Shift</kbd>+<kbd>E</kbd></td>
  </tr>
  <tr>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/systemmonitor.png" width="100%"/><br><strong>System Monitor</strong><br>btop-style graphs: CPU, GPU, memory, network, disks, processes<br><kbd>Super</kbd>+<kbd>M</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/daypanel.png" width="100%"/><br><strong>Day Panel</strong><br>calendar, events, quiet toggles, media, notifications<br><kbd>Super</kbd>+<kbd>N</kbd> / <kbd>Super</kbd>+<kbd>D</kbd></td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/keybinds.png" width="100%"/><br><strong>Key binds</strong><br>search, filter, run, rebind (settings app)<br><kbd>Super</kbd>+<kbd>F1</kbd></td>
  </tr>
  <tr>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/wallpaper.png" width="100%"/><br><strong>Wallpaper Deck</strong><br>hold <kbd>Super</kbd>, tap <kbd>W</kbd> to deal, release to apply</td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/toast.png" width="100%"/><br><strong>Notification Toast</strong><br>auto-shown on incoming notification</td>
  </tr>
</table>

### Settings app

Every option of the shell and of Hyprland in one native app (Rust, iced):
network, Bluetooth, sound, displays, appearance, accessibility, windows and
window rules, the bar, date and time, notifications, power and lock, privacy,
Flatpak app permissions, users, updates, services and syncs, with search, a
list of everything you changed and export/import. Open it from the launcher,
`settings`, or `settings -p <panel>` for one panel.

<table>
  <tr>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/settings-appearance.png" width="100%"/><br><strong>Appearance</strong><br>accent, dark or light, themes, fonts</td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/settings-displays.png" width="100%"/><br><strong>Displays</strong><br>resolution, scale, rotation, night light</td>
    <td align="center" width="33%" valign="top"><img src="screenshots/gallery/settings-accessibility.png" width="100%"/><br><strong>Accessibility</strong><br>text size, contrast, zoom, motion</td>
  </tr>
</table>

More in [`apps/settings/README.md`](apps/settings/README.md).

### Lock screen

The lock screen (<kbd>Super</kbd>+<kbd>L</kbd>): clock, now playing, weather, battery and power buttons over the blurred wallpaper:

![Lock screen](screenshots/gallery/lockscreen.png)

> [!TIP]
> Use `dots.sh setup` for automated installation, or the other `dots.sh` commands for managing symlinks.

> [!NOTE]
> Built on Nobara 44 with Hyprland 0.57.2 and Quickshell 0.3.2. The Hyprland
> config is Lua and uses the `layers` category added in 0.57, so it needs
> Hyprland 0.57+. Some commands are Fedora/Nobara specific.

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — how Hyprland, Quickshell, scripts, and cron fit together
- [`KEYBINDS.md`](KEYBINDS.md) — flat keybind reference (live viewer: `Super+F1`)
- [`docs/INSTALL.md`](docs/INSTALL.md) — dependencies and manual setup
- [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) — wallpapers, idle timeout, default apps, OSD, screen recording, wayvnc
- [`docs/DAEMONS.md`](docs/DAEMONS.md) — background daemons and dotwatch hot-reload
- [`docs/SERVICES.md`](docs/SERVICES.md) — scheduled jobs, Immich, Jellyfin, WinApps
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — lint checks and the pre-commit hook
- [`config/quickshell/DESIGN.md`](config/quickshell/DESIGN.md) — QML widget conventions and recipes
- [`config/scripts/README.md`](config/scripts/README.md) — per-script breakdown (what runs when)
- [`apps/settings/README.md`](apps/settings/README.md) — the settings app: every panel and what it changes
- [`config/hypr/MODULES.md`](config/hypr/MODULES.md) — what each `config/hypr/modules/*.lua` owns

## Setup

### One-command Install (Recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Gren-95/hyprland-dots/main/dots.sh) install
```

This will clone the repo to `~/dotfiles` and run the setup script automatically.

Dependencies, manual setup and the Firefox profile step are in [`docs/INSTALL.md`](docs/INSTALL.md).

After install, open the settings app (`settings`) for wallpapers, displays and everything else, and `Super+F1` for keybinds; [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) covers the files behind them.

## Dotfiles Manager

```bash
./dots.sh setup           # First-time install: packages, font, symlinks, units (--yes: unattended)
./dots.sh status          # Check all symlink states
./dots.sh backup          # Create symlinks (backs up existing dirs)
./dots.sh backup --dry-run  # Preview without making changes
./dots.sh fix             # Fix broken or inconsistent symlinks
./dots.sh undo            # Restore backups and remove symlinks
./dots.sh prune           # Remove dangling ~/.config symlinks into this repo
./dots.sh units           # Install the systemd user units (daemons enabled, Jellyfin timer not)
```

`./dots.sh install` is the curl one-liner above; `./dots.sh --help` lists every option.
