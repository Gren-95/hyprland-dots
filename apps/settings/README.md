# Settings

A settings app for this Hyprland setup, written in Rust with
[iced](https://iced.rs). A sidebar of panels, like GNOME Settings: Network
and Bluetooth, and the rest over the Quickshell settings store in
`~/.config/quickshell/settings/` (one small file per setting, see
[`config/quickshell/Settings.qml`](../../config/quickshell/Settings.qml)).
Quickshell watches those files, so a change in the app shows in the shell at
once. The app reads the files again every second, so changes made in the
shell show in the app too.

## Panels

| Name | Settings |
|------|----------|
| `network` | Wi-Fi on/off, nearby networks (connect, disconnect, forget, scan), wired devices, VPN connections — through `nmcli` |
| `sound` | Output and input device, their volume and mute, and the volume of every app playing — through `pw-dump` and `wpctl` |
| `bluetooth` | Bluetooth on/off, paired devices (connect, disconnect, forget, battery), scanning and pairing — through `bluetoothctl`. Connected AirPods get battery per bud and case, noise control, conversation awareness, codec and an audio reset, through librepods and `config/scripts/airpods.sh` |
| `keyboard` | Keyboard layouts (search the XKB list, add, remove, reorder), layout switch shortcut, Caps Lock key, Num Lock at start, key repeat delay and speed — written to `config/hypr/settings.lua` (gitignored, loaded last) and applied with `hyprctl eval` |
| `shortcuts` | Every key bind with its keys (search, change with modifiers and a searchable key list, reset); moves are kept in `config/hypr/settings.lua` as `hl.unbind` + `hl.bind`, `keys.lua` is not edited |
| `mouse` | Pointer speed, acceleration, left-handed, natural scrolling and scroll speed for mice; tap to click, natural scrolling, off while typing, right-click method, middle click and scroll speed for touchpads; workspace swipe direction and distance — Hyprland options saved to `config/hypr/settings.lua` |
| `appearance` | Accent colour, font and text size, corner roundness, animation speed, wallpaper folder |
| `themes` | Icon and cursor themes with previews, recently used first; applied through `config/scripts/icon-theme.sh` and `cursor-theme.sh` (the Quick Actions tile opens this panel) |
| `bar` | Height, opacity, window title width, workspace icons, activity icons, scroll action |
| `baritems` | Where each bar module, Quick Actions item and tray app shows: on the bar, in Quick Actions or hidden (the shell's placement files); tray apps are read live over D-Bus |
| `clock` | 24-hour clock, seconds, date format; weather location and Fahrenheit (`-p weather` opens it too) |
| `calendar` | ICS feeds of the day panel (`~/.config/quickshell/calendar.url`; links shown shortened as they hold private tokens): add, switch on and off, name, colour, replace the link, move up, remove; first day of the week, feed refresh interval |
| `notifications` | Toast position, time, count and width; history; auto-dismiss; system event toasts |
| `launcher` | Results shown, calculator, clipboard thumbnails |
| `osd` | Volume and brightness steps, maximum volume, on-screen display |
| `recording` | Screenshots (folder, PNG or JPEG, cursor, clipboard, actions sheet) and screen recording (folder, file type, frame rate, quality, codec, cursor, sound) — read by `config/scripts/lib/screenshot.sh` and `screenrecord.sh` |
| `sysmon` | System monitor refresh interval and sections |
| `lock` | Idle times (dim, lock, screen off, suspend) edited in `config/hypr/hypridle.conf`, which then restarts hypridle; stay awake; what the lid does; lock screen parts |
| `power` | Critical battery level and action |

## Usage

```bash
settings                        # open on the first panel
settings -p notifications       # open on a panel (also --panel notifications)
settings -s "toast"             # open with a search (also --search toast)
settings --list-panels          # panel names and titles
settings get                    # every setting as "key value"
settings get bar-height         # one value
settings set bar-height 40      # change one, checked like the window checks it
settings --help
```

The search field at the top of the sidebar (Ctrl+F) turns the panel list
into results, like GNOME Settings: the panels whose name matches, and under
the others the settings whose label, help text or choices match. Clicking a
panel opens it; clicking a setting opens its panel, scrolls to it and
outlines it for two seconds. Escape empties the field. In a narrow window the sidebar
shows only icons and widens while you search.

Sliders write when released. Text fields write on Enter.

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
| `src/cli.rs` | `settings get` and `settings set` |
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
| `src/mouse.rs` | The Mouse & touchpad rows |
| `src/shortcuts.rs` | Keyboard shortcuts panel |
| `src/keysearch.rs` | Key-combo search, the rules of the Super+F1 viewer |
| `src/themes.rs` | Icons & cursors panel |
| `src/idle.rs` | Idle times: the variables in hypridle.conf |
| `src/placement.rs` | Bar items panel: placement files and the live tray list |
| `src/keyboard.rs` | Keyboard panel and the XKB layout list |
| `src/system.rs` | Running nmcli and bluetoothctl on a background thread |
| `src/ui.rs` | Shared pieces: section cards, list rows, action buttons |
| `src/reveal.rs` | Scrolling a panel to a setting's row (a widget operation) |
| `src/style.rs` | Colours from `config/quickshell/Theme.qml` and widget styles |

To add a setting, add its row to `_schema` in `Settings.qml` first, then a
`Setting` to a panel in `src/schema.rs`.
