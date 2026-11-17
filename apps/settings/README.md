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
| `appearance` | Accent colour, font and text size, corner roundness, animation speed, wallpaper folder |
| `bar` | Height, opacity, window title width, workspace icons, activity icons, scroll action |
| `clock` | 24-hour clock, seconds, date format |
| `calendar` | ICS feeds of the day panel (`~/.config/quickshell/calendar.url`, shown shortened as the links hold private tokens): add, remove; first day of the week, feed refresh interval |
| `notifications` | Toast position, time, count and width; history; auto-dismiss; system event toasts |
| `launcher` | Results shown, calculator, clipboard thumbnails |
| `osd` | Volume and brightness steps, maximum volume, on-screen display |
| `recording` | Screenshots (folder, PNG or JPEG, cursor, clipboard, actions sheet) and screen recording (folder, file type, frame rate, quality, codec, cursor, sound) — read by `config/scripts/lib/screenshot.sh` and `screenrecord.sh` |
| `sysmon` | System monitor refresh interval and sections |
| `weather` | Location, Fahrenheit |
| `power` | Critical battery level and action, stay awake rules |

## Usage

```bash
settings                        # open on the first panel
settings -p notifications       # open on a panel (also --panel notifications)
settings -s "toast"             # open with a search (also --search toast)
settings --list-panels          # panel names and titles
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

## Build

`dots.sh setup` builds it and installs `~/.local/bin/settings` plus the
`dots-settings.desktop` launcher entry. By hand:

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
| `src/calendar.rs` | Calendar feeds: reading, adding and removing lines of calendar.url |
| `src/system.rs` | Running nmcli and bluetoothctl on a background thread |
| `src/ui.rs` | Shared pieces: section cards, list rows, action buttons |
| `src/reveal.rs` | Scrolling a panel to a setting's row (a widget operation) |
| `src/style.rs` | Colours from `config/quickshell/Theme.qml` and widget styles |

To add a setting, add its row to `_schema` in `Settings.qml` first, then a
`Setting` to a panel in `src/schema.rs`.
