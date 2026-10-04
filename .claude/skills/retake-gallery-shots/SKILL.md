---
name: retake-gallery-shots
description: Retake the README gallery screenshots (screenshots/gallery/*.png) from the live Quickshell session with config/scripts/gallery-shots.sh. Use after UI changes to a popup, the bar theme, or when asked to refresh, retake or update the gallery pictures.
---

# Retake the README gallery shots

The script is `config/scripts/gallery-shots.sh` (also on PATH as `~/.config/scripts/gallery-shots.sh`). It writes to `screenshots/gallery/`.

## Needs

- A live Hyprland + Quickshell session. It cannot run in Docker or over SSH.
- `magick`, `grim`, `hyprctl`, `wl-copy`, `cliphist`, `notify-send`.

## Run

```bash
~/.config/scripts/gallery-shots.sh --list      # shot names
~/.config/scripts/gallery-shots.sh             # retake every popup shot
~/.config/scripts/gallery-shots.sh sound toast # retake only these
```

Run only the shots affected by the change. Each shot opens a popup through its Quickshell global shortcut, so do not touch the keyboard or mouse while it runs.

## Side effects (warn the user first)

- Switches to an empty workspace, then back to the starting one.
- Replaces the clipboard history with demo entries, then restores it.
- Strips `<Owner>'s ` from Bluetooth device names during capture, then restores them.
- Sends test notifications, so the bell badge count changes.

## After

1. Read each new PNG in `screenshots/gallery/` and check: popup fully in frame, no personal content (device names, clipboard text, notification text), no stray windows.
2. Retake any shot that fails the check. Do not commit a shot with personal content.
3. `git status` should list only the retaken PNGs. Commit them on their own.

## Not covered by the script (take by hand)

- `desktop.png`: composed scene with real windows.
- `bar.png`: the bell badge counts every test toast, so take it with no pending notifications.
- `wallpaper.png`: the deck only deals while Super is held.
