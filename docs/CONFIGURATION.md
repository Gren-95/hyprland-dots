# Configuration

Per-feature settings and tweaks.

## Wallpapers

Put your wallpapers in `~/Pictures/wallpapers/`. They are preloaded automatically on startup — no manual config needed. The lock screen background also updates to the current wallpaper automatically.

## Idle timeout

```bash
$EDITOR config/hypr/hypridle.conf
```

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
(`config/quickshell/Osd.qml`). It polls `/sys/class/backlight` and `/sys/class/leds`
so any process changing brightness — key, `brightnessctl`, `hypridle` —
triggers the OSD automatically. No daemon to enable.

## Screen Recording

`Super+Shift+R` — toggles screen recording. Recordings are saved to `~/Videos/Recordings/`.

Requires `gpu-screen-recorder`. A brief toast appears top-right on start/stop
(it auto-hides during recording so it doesn't appear in the captured video).

## Remote Access (wayvnc)

wayvnc is an optional VNC server for remote desktop access.

**Start/stop:** `Super+Ctrl+R` — toggles wayvnc on/off.

**Connect:** Use any VNC viewer and connect to `127.0.0.1:5900`, or `<tailscale-ip>:5900` from another device (`wayvnc-toggle.sh` binds the Tailscale address when Tailscale is up).

**Security:** The default config binds to `127.0.0.1` with no auth. Remote access goes through [Tailscale](https://tailscale.com); there is no LAN listener unless you change `config/wayvnc/config`.

To add password auth, edit `config/wayvnc/config`:

```ini
enable_auth=true
username=user
password=yourpassword
```
