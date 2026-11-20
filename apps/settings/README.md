# Settings

A settings app for this Hyprland setup, written in Rust with
[iced](https://iced.rs). A sidebar of panels, like GNOME Settings: Network
and Bluetooth, and the rest over the Quickshell settings store in
`~/.config/quickshell/settings/` (one small file per setting, see
[`config/quickshell/Settings.qml`](../../config/quickshell/Settings.qml)).
Quickshell watches those files, so a change in the app shows in the shell at
once. The app reads the files again every second, so changes made in the
shell show in the app too.

Open it with Super+I, the Settings tile in Quick Actions, `settings` from a
terminal, or `settings -p <panel>` for one panel; several shell flyouts
(Bluetooth, Services) and the launcher open their panel here too.

## Panels

| Name | Settings |
|------|----------|
| `network` | Wi-Fi on/off, nearby networks (connect, disconnect, forget, scan), wired devices, VPN connections (on/off, Details with type, server, address, DNS and Delete; import a WireGuard .conf or OpenVPN .ovpn file; set up WireGuard by hand); Tailscale, when installed, as one VPN row whose Details hold its address to copy, exit node, options (Tailscale DNS, subnet routes, shields up, offer exit node, LAN access), devices with their address and Taildrop send, receive files into ~/Downloads — through `nmcli`; Details on the connected Wi-Fi network or wired device shows its addresses, gateway, DNS, hardware address and interface |
| `sound` | Output and input: a dropdown of devices (plain text when there is one) the volume with a mute button and the card's mode (profile, e.g. high quality or headset on Bluetooth); every app playing with its volume and mute — through `pw-dump` and `wpctl`; the alert (toast sound) volume; volume and brightness steps, maximum volume, on-screen display |
| `bluetooth` | Bluetooth on/off, visible to other devices for 3 minutes, paired devices (connect, disconnect, rename, trust, block, forget, battery), scanning and pairing — through `bluetoothctl`. Connected AirPods get, behind Details on their row, battery per bud and case, noise control, conversation awareness, codec and an audio reset, through librepods and `config/scripts/airpods.sh` |
| `keyboard` | Keyboard layouts (search the XKB list, add, remove, reorder), layout switch shortcut, Caps Lock key, Num Lock at start, key repeat delay and speed — written to `config/hypr/settings.lua` (gitignored, loaded last) and applied with `hyprctl eval`; Open under Shortcuts shows every key bind with its keys (search, change with modifiers and a searchable key list, reset) on its own page; moves are kept in `config/hypr/settings.lua` as `hl.unbind` + `hl.bind`, `keys.lua` is not edited (`-p shortcuts` opens that page) |
| `mouse` | Pointer speed, acceleration, left-handed, natural scrolling and scroll speed for mice; tap to click, natural scrolling, off while typing, right-click method, middle click and scroll speed for touchpads; workspace swipe direction and distance — Hyprland options saved to `config/hypr/settings.lua` |
| `appearance` | Accent colour, dark or light apps (gsettings color-scheme; adw-gtk3 follows), the GTK 3 theme, icon and cursor themes (each a row with the one in use that opens to the installed themes with previews, recently used first, applied through `config/scripts/icon-theme.sh` and `cursor-theme.sh`, with Open folder), shell font, app font (gsettings font-name) and text size, cursor size (`cursor-theme.sh size`), corner roundness, animations on or off (shell, Hyprland and GTK together) and their speed, wallpaper folder and a wallpaper picker (a grid of the folder from `wallpaper-thumbs.sh`, applied with `wallpaper.sh`); `themes` opens it too |
| `windows` | Gaps, border width, corner rounding, animations, blur, shadows, unfocused opacity, tiling layout, focus follows mouse, resize by border — Hyprland options in `config/hypr/settings.lua` (they win over HyprMod's `hyprland-gui.lua`); the focused window's border colour (the accent or a fixed colour), gradient and its angle, applied by the shell (`HyprBorder.qml`); window rules for apps with a window open: float (at a size), opacity, the workspace they open on, kept in `~/.config/hypr/settings.json` and written to `settings.lua` as `hl.window_rule` calls (the tracked `rules.lua` is not edited), then Hyprland reloads |
| `bar` | Height, opacity, window title width, workspace icons, activity icons, scroll action; where each bar module, Quick Actions item and tray app shows: on the bar, in Quick Actions or hidden (the shell's placement files); tray apps are read live over D-Bus |
| `datetime` | Time zone (search picker over `timedatectl list-timezones`) and network time, through `timedatectl`, which asks for the password through polkit; 24-hour clock, seconds; the bar's date format typed or picked from presets shown as today's date, first day of the week; ICS feeds of the day panel (`~/.config/quickshell/calendar.url`; links shown shortened as they hold private tokens): add, switch on and off, name, colour, replace the link, move up, remove, and the refresh interval; weather location and Fahrenheit (`-p weather` opens it too) |
| `notifications` | Do not disturb, by hand or every day between two times; toast position, time, count, width and sound; history; auto-dismiss; system event toasts; per app: show, no toasts or mute |
| `launcher` | Results shown; calculator and quick actions among the results; clipboard thumbnails; apps hidden from the launcher (Ctrl+D there), each with Show again |
| `apps` | Default apps: browser, mail, terminal, text editor, files, images, video, music, PDF — the first four through `config/scripts/default-app.sh`, the rest as XDG mime defaults (`xdg-mime`); choices are the installed apps that handle each |
| `recording` | Screenshots (folder, PNG or JPEG, cursor, clipboard, actions sheet) and screen recording (folder, file type, frame rate, quality, codec, cursor, sound), and the installed Tesseract languages text recognition reads (`ocr.rs`) — read by `config/scripts/lib/screenshot.sh`, `screenrecord.sh` and `screenshot-ocr.sh` |
| `sysmon` | System monitor refresh interval and sections |
| `about` | Header with the distro logo, system, computer, host name and uptime; processor, memory (size, type, speed, modules, use) and graphics tiles; disk usage meters; kernel, Hyprland, Quickshell, package counts, app version; the dots repository with Open on GitHub and what is not pushed; Copy as text for bug reports (battery and network included); Backup: export every setting to one file, or import one after a list of what it changes |
| `gaming` | Game mode switch; connected controllers with their battery and a Connect button to Bluetooth; the game mode launcher opening on games; Proton versions (collapsed): installed GE-Proton and Valve Proton, the default, games per version, missing versions, the newest GE-Proton release, ProtonPlus; what it does (effects off, hide the bar, Do not disturb, performance profile, keep the screen awake, pause syncs, night light, Docker, Tailscale); turn on with Feral GameMode (`gamemoderun`); variable refresh rate, tearing, direct scanout |
| `services` | Apps at login (`~/.config/autostart`: switch, remove, add an installed app; started by `autostart-apps.sh`); background services: your systemd user units (switch enables and starts or disables and stops, Restart) and Dotwatch; system services (root-level units): the ones changed from the distribution's default and all enabled ones, in collapsed lists with a switch each (`systemctl enable/disable --now`, which asks for the password through polkit; the core ones are read-only), plus the system's user units for the session, read-only; from `config/scripts/services-status.sh`: the on-demand services (Windows VM, games browser) with a switch each, through their toggle scripts |
| `sync` | The Immich and Jellyfin syncs: on/off (`sync-toggle.sh`), schedule, Sync now; the folder each uses and the Jellyfin server address — read by `immich-sync.sh` and `jellyfin-music-sync.sh`. Shows the Immich server from the immich CLI login and whether a Jellyfin API key is set (environment or `sync.conf`); keys are never shown or saved by the app |
| `sharing` | Remote access (WayVNC) with a switch and Details: address to connect to, login (show, copy, new password), listen on (tailnet only, this computer only, local network), port, frame rate, view only, drawing the cursor — read by `wayvnc-toggle.sh`; remote login (sshd, switched with `systemctl enable/disable --now`, which asks for the password through polkit); whether Tailscale makes this computer reachable, with a link to the Network panel |
| `power` | Battery charge, health, cycles, charge limit, power, temperature, model and age; Limit charging (UPower's charge threshold, through polkit) when the battery supports it; the power profile on the charger and on battery and the level below which it saves power — read by `power-auto.sh`; low battery levels and action; idle times (dim, lock, screen off, suspend) edited in `config/hypr/hypridle.conf`, which then restarts hypridle; stay awake; what the lid does; lock screen parts (`-p idle` opens it too) |

## Usage

```bash
settings                        # open on the first panel
settings -p notifications       # open on a panel (also --panel notifications)
settings -s "toast"             # open with a search (also --search toast)
settings --list-panels          # panel names and titles
settings get                    # every setting as "key value"
settings get bar-height         # one value
settings set bar-height 40      # change one, checked like the window checks it
settings export backup.json     # every setting (shell store, Hyprland choices, default apps) in one file
settings import backup.json     # lists what it changes, then asks before writing
settings --help
```

The search field at the top of the sidebar (Ctrl+F) turns the panel list
into results, like GNOME Settings: the panels whose name matches, and under
the others the settings whose label, help text or choices match. Clicking a
panel opens it; clicking a setting opens its panel, scrolls to it and
outlines it for two seconds. Escape empties the field. In a narrow window the sidebar
shows only icons and widens while you search.

Sliders write when released. Text fields write on Enter.

Keyboard: the sidebar and the open panel are two zones. Tab moves through
the panel's controls (buttons, switches, dropdowns, text fields), round to
the first after the last, with a ring around the one in focus, and the
panel scrolls to keep it in sight; Enter or Space presses it (a dropdown
steps to its next choice, a switch flips). Shift+Tab goes back to the
sidebar, where Up and Down move between panels and Enter opens one with the
focus on its first control. Alt+Down and Alt+Up open the next and previous
panel; Page Down, Page Up, Home and End scroll the panel; Escape closes a
dialog or empties the search. Sliders are mouse only.

The Network, Sound and Bluetooth panels ask the system again every three
seconds while open. Volume sliders stop at the maximum volume set in Volume &
OSD. A Wi-Fi password is handed to `nmcli --ask` on
stdin, so it never appears in the process list.

## UI rules

[`UI.md`](UI.md) has the rules every panel follows: which control to use
for which kind of option, button and input groups, confirmations, wording,
states and layout.

## Build

`dots.sh setup` builds it and installs `~/.local/bin/settings` plus the
`dots-settings.desktop` launcher entry. A clean build needs network access:
the `lucide-iced` crate downloads the newest Lucide icon set from GitHub in
its build script (the icons are not pinned to a Lucide version). By hand:

```bash
cd apps/settings
cargo test
cargo build --release
install -Dm755 target/release/settings ~/.local/bin/settings
```

## Code

| File | What it does |
|------|--------------|
| `src/main.rs` | Command line, window |
| `src/args.rs` | Argument parsing |
| `src/cli.rs` | `settings get`, `settings set` and the `settings import` prompt |
| `src/backup.rs` | Export and import of every setting; the Backup section on About |
| `src/region.rs` | Time zone, network time and date presets on the Date & time panel |
| `src/schema.rs` | The panels and their settings: file, label, control, default. A test checks every file and type against `Settings.qml` |
| `src/store.rs` | Reading and writing the setting files in the format `Settings.qml` uses |
| `src/app.rs` | The iced app: state, messages, the open panel, window-width layout |
| `src/sidebar.rs` | Panel list and search results |
| `src/search.rs` | Which panels and settings match a search |
| `src/controls.rs` | A setting as a row: label, help and its control |
| `src/network.rs` | Network panel: nmcli output parsing, actions, view |
| `src/bluetooth.rs` | Bluetooth panel: bluetoothctl output parsing, actions, view |
| `src/audio.rs` | Sound panel: pw-dump parsing, wpctl actions, view |
| `src/airpods.rs` | AirPods section of the Bluetooth panel: librepods state, airpods.sh actions |
| `src/calendar.rs` | Calendar feeds: the calendar.url line format, editing it |
| `src/hypr.rs` | Hyprland settings the app owns: settings.json, the generated settings.lua, `hyprctl eval` |
| `src/hyprpage.rs` | Panels of plain Hyprland options declared as rows (Mouse & touchpad) |
| `src/about.rs` | About panel |
| `src/services.rs` | Services panel |
| `src/sync.rs` | Where the syncs connect, on the Sync panel |
| `src/startup.rs` | Apps at login (XDG autostart) on the Services panel |
| `src/units.rs` | Systemd user units on the Services panel |
| `src/sysunits.rs` | System services (root-level units) on the Services panel |
| `src/sharing.rs` | Sharing panel: remote access, SSH, tailnet |
| `src/vnc.rs` | Remote access (WayVNC) Details on the Sharing panel |
| `src/proton.rs` | Proton versions on the Gaming panel |
| `src/gaming.rs` | Game mode switch and the Display rows on the Gaming panel |
| `src/hiddenapps.rs` | Hidden apps on the Launcher panel |
| `src/focus.rs` | Keyboard focus: the focusable wrapper, Tab and scrolling to the focused control |
| `src/tailscale.rs` | Tailscale row and its Details in the VPN list |
| `src/vpn.rs` | VPN section of the Network panel: list, details, import, WireGuard setup |
| `src/notifapps.rs` | Per-app notification rules on the Notifications panel |
| `src/power.rs` | Battery block on the Power & lock panel |
| `src/memory.rs` | Memory modules (udev), use (/proc/meminfo) and swap |
| `src/infocache.rs` | Disk cache for slow About facts (~/.cache/dots-settings) |
| `src/infoview.rs` | Fact rows, tiles, battery and network blocks shared by About, Power and Network |
| `src/sysinfo.rs` | What the system is, for About: hardware, battery, network, packages, repository |
| `src/windows.rs` | The Windows rows |
| `src/windowrules.rs` | Window rules on the Windows panel |
| `src/mouse.rs` | The Mouse & touchpad rows |
| `src/defaultapps.rs` | Default apps panel: desktop entries, roles |
| `src/shortcuts.rs` | Key binds page of the Keyboard panel |
| `src/keysearch.rs` | Key-combo search, the rules of the Super+F1 viewer |
| `src/themes.rs` | Icon and cursor themes on the Appearance panel |
| `src/appearance.rs` | GTK theme and wallpaper picker on the Appearance panel |
| `src/idle.rs` | Idle times: the variables in hypridle.conf |
| `src/placement.rs` | Item placement on the Bar panel: placement files and the live tray list |
| `src/keyboard.rs` | Keyboard panel and the XKB layout list |
| `src/system.rs` | Running nmcli and bluetoothctl on a background thread |
| `src/ui.rs` | Shared pieces: section cards, list rows, action buttons |
| `src/reveal.rs` | Scrolling a panel to a setting's row (a widget operation) |
| `src/style.rs` | Colours from `config/quickshell/Theme.qml` and widget styles |

To add a setting, add its row to `_schema` in `Settings.qml` first, then a
`Setting` to a panel in `src/schema.rs`.

## Checking the UI

`scripts/screenshot.sh <panel> <out.png> [height] [scroll]` starts the debug
build on a panel, floats it, saves the panel part as a picture and closes
it again; `scroll` moves the window up so the lower part of a long panel
shows. Pages that read system state every few seconds say so in
`Page::polls` (schema.rs); nothing else needs wiring for that.

