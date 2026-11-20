# Scheduled Jobs and Optional Services

Sync jobs, timers and opt-in services.

## Scheduled Jobs

| Job | Schedule | Mechanism |
|---|---|---|
| Immich photo sync | Hourly by default (30 min to 6 h, chosen at setup), when enabled | crontab entry between `# QSSYNC:immich` markers |
| Jellyfin music sync | Daily | `jellyfin-sync.timer` (user timer, `Persistent=true`) |

Both sync jobs are toggled from the settings app's Sync panel (`settings -p
sync`, also in the launcher), which calls `sync-toggle.sh`. It comments or uncomments the cron line for Immich and
enables or disables the user timer for Jellyfin, so a disabled job leaves its
schedule in place rather than losing it.

`Persistent=true` matters on a laptop: a timer that fires while the machine is
asleep runs on the next boot instead of being skipped.

## Optional Services

### Immich (photo sync)

Uploads `~/Pictures/` to your Immich server on its schedule while enabled,
leaving out `Screenshots/` and `ocr/` folders. Notifies when new photos are uploaded. When the server is unreachable (for example away from home) the run is skipped quietly with a line in `~/.cache/immich-sync.log`, and the next run tries again.

**Setup:** run `dots.sh setup` and answer yes to the Immich step: it installs
the CLI (bun or npm), logs in, and asks for the interval. By hand:

```bash
npm install -g @immich/cli --prefix ~/.npm-global   # or: bun install -g @immich/cli
immich login https://your-immich-server/api YOUR_API_KEY
bash ~/.config/scripts/sync-toggle.sh schedule immich "0 * * * *"
bash ~/.config/scripts/sync-toggle.sh enable immich
```

Needs `crontab` (cronie); without it the Sync panel shows Immich sync as
off and explains why when toggled.

Auth is stored in `~/.config/immich/auth.yml` (gitignored).

### Jellyfin (music sync)

Syncs your Jellyfin music library to `~/Music/` once a day. Jellyfin is the master — tracks removed from Jellyfin are deleted locally. Notifies after each sync with a download/skip/remove summary. When the server is unreachable the sync is skipped quietly (logged in `~/.cache/jellyfin-sync.log`); a connection lost mid-sync stops the run without deleting anything, and a server that reports zero tracks never empties `~/Music`.

**Setup:** run `dots.sh setup` and answer yes to the Jellyfin step, or by hand:

```bash
bash ~/.config/scripts/jellyfin-music-sync.sh   # first run asks for the URL and API key
./dots.sh units   # from the repo: installs jellyfin-sync.{service,timer}
```

Then switch "Jellyfin sync" on in the settings app's Sync panel, which enables the timer.
Tracks are saved as `~/Music/<Artist>/<Album>/<Track>`. To change the time,
`sync-toggle.sh schedule jellyfin "*-*-* 04:00:00"` writes a timer drop-in.

Config is stored in `~/.config/jellyfin/sync.conf` (gitignored). To reconfigure, delete the file and run the script again.

### Windows VM (WinApps)

`winvm-toggle.sh` starts and stops the `dockur/windows` container that backs
WinApps, a switch on the settings app's Services panel. Stopping the container is what
actually frees the VM's 6 GB of RAM. Needs `docker` and `freerdp`.
