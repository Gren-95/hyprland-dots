# Configuration

Per-feature settings and tweaks.

## Wallpapers

Put your wallpapers in `~/Pictures/wallpapers/`. `Super+W` (hold Super, tap W)
deals them as cards; releasing Super applies the one in hand. At login the last
wallpaper is restored (`awww restore`). The lock screen uses a random wallpaper
from the same folder each time it locks (`config/scripts/hyprlock-art.sh`).
The wallpaper deck reads its folder from the `wallpaper-dir` setting (below);
`Super+Shift+N` (random wallpaper) always uses `~/Pictures/wallpapers/`.

## Idle timeout

```bash
$EDITOR config/hypr/hypridle.conf
```

Two ways to keep the screen on:

- **Stay Awake** (the toggle in the day panel, `Super+N`): stops hypridle, so
  nothing dims, locks or suspends. It is remembered across shell reloads
  (`idle-stay-awake` setting). `idle-inhibit-media` and `idle-inhibit-power`
  turn it on automatically while media plays or while on AC.
- **`Super+Shift+I`** (`config/scripts/idle-inhibit-toggle.sh`): holds a
  separate idle inhibitor until pressed again; hypridle keeps running, so
  lock-before-sleep still works.

Media playing, a fullscreen window or a Claude Code session at work also hold
an inhibitor on their own while they last.

## Default apps

Open the launcher (`Super+R`) and type `default` — Browser, Terminal, Editor
and File manager each open a picker listing the apps that declare themselves
for that role. Browser and file manager also become the XDG default, so links
and folders opened from other apps follow the same choice. `Super+T` and
`Super+E` route through `config/scripts/default-app.sh`, so a pick takes effect
without touching the config.

## Hiding apps from the launcher

`Ctrl+D` on a highlighted entry drops it from the launcher. To get one back,
type `hidden` in the launcher and pick it from the list. The list is scoped to
the launcher — it does not write `NoDisplay` into the desktop entry, so other
menus are unaffected.

## Keybinds

```bash
$EDITOR config/hypr/modules/keys.lua
```

Press `Super+F1` in session to view all active keybinds.

## OSD

Volume, brightness, and keyboard-backlight OSDs are rendered by Quickshell
(`config/quickshell/Osd.qml`). It watches the brightness files under
`/sys/class/backlight` and `/sys/class/leds`, so any process changing brightness
— key, `brightnessctl`, `hypridle` — triggers the OSD automatically. No daemon
to enable.

## Screen Recording

`Super+Shift+R` — toggles screen recording. Recordings are saved to `~/Videos/Recordings/`
unless the settings app's Screenshots & recording panel (`settings -p recording`) says otherwise;
that panel also sets the screenshot folder and format, frame rate, quality, codec and audio.

Requires `gpu-screen-recorder`. A brief toast appears top-right on start/stop
(it auto-hides during recording so it doesn't appear in the captured video).

## Remote Access (wayvnc)

wayvnc is an optional VNC server for remote desktop access.

**Start/stop:** `Super+Ctrl+R` — toggles wayvnc on/off.

**Connect:** Use any VNC viewer and connect to `127.0.0.1:5900`, or `<tailscale-ip>:5900` from another device (`wayvnc-toggle.sh` binds the Tailscale address when Tailscale is up).

**Login:** the server asks for a username and password over TLS. The user is your login name; the password is a random string created on first start and kept in `~/.config/wayvnc/password` (gitignored, mode 600), next to a self-signed certificate and key. Print or replace it with:

```bash
~/.config/scripts/wayvnc-toggle.sh password   # show user and password
~/.config/scripts/wayvnc-toggle.sh rotate     # new password; restart remote access after
```

Super+Ctrl+R and the Services panel toggle run the same script, so both start the server with the login. Viewers show a certificate warning on first connect because the certificate is self-signed.

**Security:** wayvnc binds `127.0.0.1`, or the Tailscale address while Tailscale is up (only the interface is checked, so a stopped Tailscale never leaves a stale bind). There is no LAN listener unless you change `config/wayvnc/config`. Never put the password into `config/wayvnc/config`, which is tracked.

## Shell settings

Quickshell keeps its settings as one small file per setting in
`~/.config/quickshell/settings/` (gitignored). Edit a file and the shell picks
the change up at once; delete it to go back to the default. A file that does
not parse is ignored with a warning in the shell log and left as it is. The
full list, with defaults, is the `_schema` in `config/quickshell/Settings.qml`.
The ones most worth knowing:

| File | Default | What it does |
|---|---|---|
| `weather-location` | empty (weather off) | City for the day panel weather card and the lock screen corner |
| `weather-fahrenheit` | `0` | `1` for °F and mph |
| `wallpaper-dir` | `~/Pictures/wallpapers` | Folder the wallpaper deck deals from |
| `accent-primary` | `orange` | Highlight colour: `orange`, `blue`, `green`, `red`, `yellow`, `purple`, `pink`, `teal`, `slate`, or `auto` (taken from the wallpaper) |
| `accent-everywhere` | `1` | The accent colour replaces the other decorative accents (blue, purple, teal, pink, slate, orange); red, green and yellow keep their colour |
| `idle-stay-awake` | `0` | The Stay Awake toggle (written by the day panel switch) |
| `idle-inhibit-media`, `idle-inhibit-power` | `0` | Stay Awake while media plays / while on AC |
| `battery-critical-pct`, `battery-critical-action` | `5`, `suspend` | At this level a 15 s countdown suspends unless you plug in; `none` or `0` turns it off |
| `max-volume` | `100` | Volume ceiling for every volume control, in % |
| `clock-24h`, `clock-seconds`, `clock-date-format` | `1`, `0`, `ddd, dd MMM` | Bar clock |
| `font-family`, `font-scale` | `Iosevka Nerd Font`, `1.0` | Shell font and size multiplier |
| `toast-position`, `toast-timeout`, `toast-max` | `center`, 10000 ms, 5 | Notification toasts |
| `event-toasts.json` | charger and VPN on | Which system events show a toast (`charger`, `vpn`, `audio`, `layout`) |
| `bar-placement.json`, `tray-placement.json`, `qa-placement.json` | empty | Per item `"bar"`, `"overflow"` or `"hidden"` for bar modules, tray apps and Quick Actions items |
| `flyout-sizes.json` | empty | Per flyout `{ "w": …, "h": … }` size overrides |
| `hidden-apps.json` | empty | Apps hidden from the launcher (managed with `Ctrl+D` there) |
| `battery-low-pct`, `battery-warn-pct` | `20`, `10` | Battery warning levels, read by `scripts/battery-notify.sh` |
| `night-temperature`, `night-schedule`, `night-from`, `night-to` | `4000`, `0`, `21:00`, `07:00` | Night light colour and optional schedule, read by `scripts/night.sh` |
| `lid-close-action` | `lock` | What closing the lid does when no external display is connected: `lock`, `suspend` or `nothing` (screen off only); read by `scripts/lid.sh` |
| `lock-show-media`, `lock-show-weather`, `lock-show-battery` | `1` | Parts of the lock screen; read by the `hyprlock-*.sh` scripts |
| `shot-dir`, `shot-format`, `shot-cursor`, `shot-clipboard`, `shot-actions` | `~/Pictures/Screenshots`, `png`, `0`, `1`, `1` | Screenshot folder, `png` or `jpg`, capture the cursor, copy to the clipboard, open the actions sheet after a region shot (read by `scripts/lib/screenshot.sh` and RegionSelector) |
| `record-dir`, `record-container`, `record-fps`, `record-quality`, `record-codec`, `record-cursor`, `record-audio` | `~/Videos/Recordings`, `mp4`, `60`, `very_high`, `auto`, `1`, `none` | Screen recording options, read by `scripts/screenrecord.sh` (audio: `none`, `output`, `input`, `both`) |
| `icon-theme-recents.json`, `cursor-theme-recents.json` | empty | Recently applied themes, listed first in the settings app's Icons & cursors panel |

### Calendar feeds

The day panel calendar reads ICS feed URLs from
`~/.config/quickshell/calendar.url`, one per line:
`[#off ]<url>[ #color=<colour>][ #name=<name>]`. A feed switched off is written
as a `#off` comment and not fetched; `#color` is one of blue, orange, red, green,
purple, pink, teal (without it a feed gets a colour by its position); `#name` is
shown in the settings app. Other `#` comments and blank lines are ignored. The
settings app's Calendar panel (`settings -p calendar`) edits all of this. Feeds are fetched every
`calendar-fetch-interval` minutes (default 10); a feed that fails to fetch keeps
its last events. The file is gitignored because feed URLs often carry a private
token.
