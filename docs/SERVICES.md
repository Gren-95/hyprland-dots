# Scheduled Jobs and Optional Services

Sync jobs, timers and opt-in services.

## Scheduled Jobs

| Job | Schedule | Mechanism |
|---|---|---|
| Immich photo sync | Hourly, when enabled | crontab entry between `# QSSYNC:immich` markers |
| Jellyfin music sync | Daily | `jellyfin-sync.timer` (user timer, `Persistent=true`) |
| Battery charge cap | Daily at 00:05 | `battery-charge-schedule.timer` (system timer, `Persistent=true`) |

Both sync jobs are toggled from Quick Actions (`Super+A`), which calls
`sync-toggle.sh`. It comments or uncomments the cron line for Immich and
enables or disables the user timer for Jellyfin, so a disabled job leaves its
schedule in place rather than losing it.

`Persistent=true` matters on a laptop: a timer that fires while the machine is
asleep runs on the next boot instead of being skipped.

The battery cap runs uncapped Friday through Sunday and applies a 75–80% cap on
weekdays, so the cell ages slower without getting in the way at the weekend. Its
script is deployed as a **copy** to `/usr/local/bin` — systemd runs it as root,
so `ExecStart` must not point into a user-writable path.

## Optional Services

### Immich (photo sync)

Uploads `~/Pictures/` to your Immich server every hour while enabled. Notifies when new photos are uploaded.

**Setup:**

```bash
npm install -g @immich/cli --prefix ~/.npm-global
immich login https://your-immich-server/api YOUR_API_KEY
```

Auth is stored in `~/.config/immich/auth.yml` (gitignored).

### Jellyfin (music sync)

Syncs your Jellyfin music library to `~/Music/` once a day. Jellyfin is the master — tracks removed from Jellyfin are deleted locally. Notifies after each sync with a download/skip/remove summary.

**Setup:**

```bash
bash ~/.config/scripts/jellyfin-music-sync.sh
```

You will be prompted for your Jellyfin server URL and API key on first run. Config is stored in `~/.config/jellyfin/sync.conf` (gitignored). To reconfigure, delete the file and run the script again.

### Windows VM (WinApps)

`winvm-toggle.sh` starts and stops the `dockur/windows` container that backs
WinApps, exposed in the Services panel. Stopping the container is what
actually frees the VM's 6 GB of RAM. Needs `docker` and `freerdp`.
