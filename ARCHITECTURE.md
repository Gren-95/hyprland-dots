# Architecture

Bird's-eye view of how the pieces fit together. For widget-level detail see
`quickshell/DESIGN.md`; for keybinds see `KEYBINDS.md`; for scripts see
`scripts/README.md`.

## The stack

```
┌─────────────────────────────────────────────────────────────┐
│                       Hyprland                              │
│  (Wayland compositor — owns windows, workspaces, keybinds)  │
└────┬─────────────────┬──────────────────┬───────────────────┘
     │ exec-once       │ keybinds         │ wl-* protocols
     │                 │ (global)         │
     ▼                 ▼                  ▼
┌──────────┐    ┌──────────────┐    ┌─────────────────────────┐
│ scripts  │    │  Quickshell  │    │  System services        │
│ (daemons │◄───┤  (bar, OSD,  │◄───┤  PipeWire, NetworkMgr,  │
│  & one-  │    │   notifs,    │    │  UPower, Bluetooth,     │
│  shots)  │    │   modals)    │    │  polkit, DBus           │
└────┬─────┘    └──────────────┘    └─────────────────────────┘
     │                  ▲
     │                  │ DBus / IPC
     └──────────────────┘
       notify-send,
       cron schedules
```

## Boot sequence

1. User logs into Hyprland.
2. Hyprland loads `hyprland.lua`, which requires the `modules/*.lua` files (and `hyprland-gui.lua` last for HyprMod overrides).
3. `autostart.lua` `exec-once` fires:
   - `scripts/restart.sh` — orchestrates every userspace service
   - `nm-applet --indicator` — system-tray NetworkManager applet (still used
     for Wi-Fi password prompts)
4. `restart.sh` starts in sequence: xdg-desktop-portal, gnome-keyring,
   Quickshell, hyprpaper, hypridle, battery-notify, media-inhibit, cliphist,
   network-notify, dotwatch. Logs OK/FAILED per step.
5. Quickshell loads `~/.config/quickshell/shell.qml` (a symlink into the dots
   repo) and renders the bar + every modal as hidden overlays.

## What lives where

| Layer | What it owns |
|---|---|
| **Hyprland compositor** | Window layout, workspaces, keyboard input, layer-shell protocol. |
| **`scripts/`** | Long-running background daemons (battery/network/media-inhibit/dotwatch) + one-shot actions (screenshot/record/wallpaper). All notifications go through `scripts/lib/notify.sh`. |
| **Quickshell** | Bar, popups, OSDs, notification daemon (replaces swaync), launcher (replaces rofi), polkit agent (replaces hyprpolkitagent). State for the bar's interactive bits (audio, brightness, BT, Wi-Fi, VPN) comes from `Quickshell.Services.*` modules talking directly to PipeWire / NetworkManager / UPower / etc. |
| **`cron`** | Periodic Immich and Jellyfin syncs. Managed by `scripts/sync-toggle.sh` (Quick Actions toggle UI). No persistent daemon; cron just fires the script on schedule. |

## Dotfiles plumbing

`~/.config/<dir>` is a symlink into this repo for every managed directory
(hypr, kitty, quickshell, swappy, scripts, wayvnc, fish, ranger,
gtk-3.0, immich, jellyfin). Two entry points:

- `setup.sh` — first-time install on a fresh machine. Installs Fedora
  packages, creates symlinks (delegates to `dotfiles-manager.sh`), prompts
  for Immich/Jellyfin credentials and cron schedule.
- `dotfiles-manager.sh` — symlink management with `backup` / `undo` /
  `status` / `fix` commands. Single source of truth for which configs get
  symlinked.

## Hot reload

`dotwatch.sh` runs `inotifywait` on the dots repo and, on file change:

- `hypr/hyprland*.lua` or `hypr/modules/*` → `hyprctl reload`
- `hypr/hypridle.conf` → restart hypridle
- `hypr/hyprlock.conf` → notify (changes apply next lock)
- `gtk-3.0/gtk.css` → notify (changes apply next GTK app launch)

Quickshell auto-watches its own QML files — edits to `quickshell/*.qml` are
picked up automatically (sometimes a SIGTERM + restart is needed if the file
watcher missed an atomic write).

## Cross-app communication

| From | To | Mechanism |
|---|---|---|
| Hyprland keybind | Quickshell modal | `global, quickshell:<name>` dispatcher → `GlobalShortcut { name: "<name>" }` in shell.qml |
| Scripts | User | `lib/notify.sh notify` → notify-send → notification daemon (Quickshell) |
| Quickshell | Scripts | `Process { command: ["bash", "~/.config/scripts/<x>.sh"] }` + `startDetached()` |
| Quickshell | Hyprland | `Hypr.dispatch("<cmd>")` singleton (wraps `hyprctl dispatch`) |
| Cron | Sync | Hourly `bash ~/.config/scripts/immich-sync.sh` / 2-hourly jellyfin |
| Quickshell ↔ cron state | — | `sync-toggle.sh status all` polled by `daemonCheckProc` in QuickActions |

## See also

- `quickshell/DESIGN.md` — QML widget conventions, primitives, recipes
- `scripts/README.md` — per-script breakdown
- `KEYBINDS.md` — flat keybind reference
- `hypr/MODULES.md` — what each `hypr/modules/*.lua` does
- `README.md` — install, dependencies, screenshots
