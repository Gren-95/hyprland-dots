# Background Daemons

Long-running scripts started by `restart.sh`.


These run automatically on login via `restart.sh` and restart cleanly on each
session. The sync icon beside Quick Actions in the bar shows all of them at a
glance — plus the scheduled syncs and the on-demand services — and starts any
daemon that has died.

| Script | Purpose |
|---|---|
| `battery-notify.sh` | Notifies at 20% and 10% battery; dismisses the alert when plugged in |
| `power-auto.sh` | Sets the power profile from AC state and battery level (`performance` on AC, `balanced` ≥30%, `power-saver` below) |
| `media-inhibit.sh` | Prevents screen sleep during media playback |
| `fullscreen-inhibit.sh` | Prevents idle while a window is fullscreen |
| `dotwatch.sh` | Watches dotfiles for changes and hot-reloads affected services |

## dotwatch — hot-reload

Edits to dotfiles are picked up automatically without restarting your session:

| File changed | Action |
|---|---|
| `config/hypr/hyprland*.lua`, `config/hypr/modules/*` | `hyprctl reload` |
| `config/hypr/hypridle.conf` | Restart hypridle |
| `config/hypr/hyprlock.conf` | Notification (applies on next lock) |
| `config/gtk-3.0/gtk.css` | Notification (restart GTK apps to apply) |
| `config/quickshell/*` | Quickshell auto-reloads on file changes |
