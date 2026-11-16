# Background Daemons

Long-running scripts that run for the whole session.

battery-notify, power-auto and bt-audio-recover are systemd user units
(`systemd/user/*.service`, installed and enabled by `dots.sh units`); they start
with the graphical session, and `restart.sh` (`Super+B`) restarts them.
librepods is a user unit too, installed by `build-librepods.sh` when you build
it. dotwatch is started by `restart.sh` itself.

The Services panel (the sync icon beside Quick Actions in the bar) shows
battery-notify, power-auto and dotwatch, starts any of those three that has
died, and lists the scheduled syncs and the on-demand services.

| Script | Purpose |
|---|---|
| `battery-notify.sh` | Notifies at 20% and 10% battery, once per discharge; re-arms whenever the battery is not discharging. The shell dismisses the alerts when power comes back (`Notifications.qml`) |
| `bt-audio-recover.sh` | Switches a connected Bluetooth headset from the `off` card profile to A2DP when WirePlumber leaves it there (connected in `bluetoothctl`, but no audio output). Waits 5 s after each card event, notifies when it acts |
| `power-auto.sh` | Sets the power profile from AC state and battery level (`performance` on AC, `balanced` ≥30%, `power-saver` below) |
| `dotwatch.sh` | Watches dotfiles for changes and hot-reloads affected services |
| `librepods` (optional) | AirPods daemon built by `build-librepods.sh`; writes the AirPods battery level the bar shows (`$XDG_RUNTIME_DIR/librepods-battery.json`) |

## dotwatch — hot-reload

Edits to dotfiles are picked up automatically without restarting your session:

| File changed | Action |
|---|---|
| `config/hypr/hyprland*.lua`, `config/hypr/modules/*` | `hyprctl reload` |
| `config/hypr/hypridle.conf` | Restart hypridle |
| `config/hypr/hyprlock.conf` | Notification (applies on next lock) |
| `config/gtk-3.0/gtk.css` | Notification (restart GTK apps to apply) |
| `config/quickshell/*` | Quickshell auto-reloads on file changes |

## Claude Code activity (keeps the screen from idle-locking mid-task)

`IdleService` holds an idle inhibitor while any Claude Code session is working
(hypridle keeps running, so lock-before-sleep still works). Claude Code reports
its sessions through hooks in `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR`),
which are not part of this repo. Add them alongside any existing hooks:

```json
"hooks": {
  "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash $HOME/.config/scripts/claude-activity.sh start", "async": true, "timeout": 10 }] }],
  "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "bash $HOME/.config/scripts/claude-activity.sh beat",  "async": true, "timeout": 10 }] }],
  "Stop":             [{ "hooks": [{ "type": "command", "command": "bash $HOME/.config/scripts/claude-activity.sh stop",  "async": true, "timeout": 10 }] }],
  "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "bash $HOME/.config/scripts/claude-activity.sh stop",  "async": true, "timeout": 10 }] }]
}
```

Open `/hooks` once (or restart Claude Code) after editing so the hooks load. The
Stay Awake switch in the day panel (`Super+N`) notes "Claude working" while a
session is active.
