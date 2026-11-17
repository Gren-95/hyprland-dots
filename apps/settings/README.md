# Settings

A settings app for this Hyprland setup, written in Rust with
[iced](https://iced.rs). A sidebar of panels, like GNOME Settings, over the
Quickshell settings store in `~/.config/quickshell/settings/` (one small file
per setting, see [`config/quickshell/Settings.qml`](../../config/quickshell/Settings.qml)).
Quickshell watches those files, so a change in the app shows in the shell at
once. The app reads the files again every second, so changes made in the
shell show in the app too.

## Panels

| Name | Settings |
|------|----------|
| `appearance` | Accent colour, font and text size, corner roundness, animation speed, wallpaper folder |
| `bar` | Height, opacity, window title width, workspace icons, activity icons, scroll action |
| `clock` | 24-hour clock, seconds, date format, first day of the week, calendar feed refresh |
| `notifications` | Toast position, time, count and width; history; auto-dismiss; system event toasts |
| `launcher` | Results shown, calculator, clipboard thumbnails |
| `sound` | Volume and brightness steps, maximum volume, on-screen display |
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
the others the settings whose label, help text or choices match. Click one
to open its panel; Escape empties the field. In a narrow window the sidebar
shows only icons and widens while you search.

Sliders write when released. Text fields write on Enter.

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
| `src/style.rs` | Colours from `config/quickshell/Theme.qml` and widget styles |

To add a setting, add its row to `_schema` in `Settings.qml` first, then a
`Setting` to a panel in `src/schema.rs`.
