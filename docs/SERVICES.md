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

Uploads run with [immich-rs](https://github.com/Gren-95/immich-rs), a Rust
rewrite of the Immich CLI with the same options and output, installed at
`~/.local/bin/immich-rs`.

**Setup:** run `dots.sh setup` and answer yes to the Immich step: it downloads
the newest immich-rs release for your architecture (x86_64 or aarch64), checks it
against the release's checksums, logs in, and asks for the interval. `upi` keeps
immich-rs on the newest release. By hand, install it as its
[README](https://github.com/Gren-95/immich-rs#install) shows, then:

```bash
immich-rs login https://your-immich-server/api YOUR_API_KEY
bash ~/.config/scripts/sync-toggle.sh schedule immich "0 * * * *"
bash ~/.config/scripts/sync-toggle.sh enable immich
```

Needs `crontab` (cronie); without it the Sync panel shows Immich sync as
off and explains why when toggled.

Auth is stored in `~/.config/immich/auth.yml` (gitignored).

### Jellyfin (music sync)

Syncs your Jellyfin music library to `~/Music/` once a day with
[jellyfin-music-rs](https://github.com/Gren-95/jellyfin-music-rs), installed at
`~/.local/bin/jellyfin-music-rs`. Every track is saved straight in the music
folder as `~/Music/<Track>.mp3`, with no folders, covers or playlists, so
`mpv --shuffle ~/Music/*` plays the whole library. Tracks with the same name get
`<Track> (2).mp3`. Jellyfin is the master: any audio file in `~/Music` that the
server doesn't have is deleted, including music you put there yourself, unless
that would remove more than half of them (a server with a half-mounted drive).
Keep other music in another folder. Downloads resume after a dropped connection.

It notifies when tracks were downloaded, updated, removed or failed, and when
something needs a look (a rejected key, the deletion guard). An unreachable
server, an empty library or a dropped connection skips the run quietly, with a
line in `~/.cache/jellyfin-sync.log`, which also lists every track the sync
handled.

**Setup:** run `dots.sh setup` and answer yes to the Jellyfin step: it
downloads jellyfin-music-rs, installs the timer and checks your login. By hand:

```bash
bash ~/.config/scripts/jellyfin-music-sync.sh   # in a terminal, first asks for the URL and API key
./dots.sh units   # from the repo: installs jellyfin-sync.{service,timer}
```

Then switch "Jellyfin sync" on in the settings app's Sync panel, which enables the timer.
To change the time, `sync-toggle.sh schedule jellyfin "*-*-* 04:00:00"` writes a timer drop-in.
`upi` keeps jellyfin-music-rs on the newest release.

The login is stored in `~/.config/jellyfin/sync.conf` (gitignored, mode 0600). To change it, run
`jellyfin-music-rs --config ~/.config/jellyfin/sync.conf login <url> <key>`.

### Windows VM (WinApps)

`winvm-toggle.sh` starts and stops the `dockur/windows` container that backs
WinApps, a switch on the settings app's Services panel. Stopping the container is what
actually frees the VM's 6 GB of RAM. Needs `docker` and `freerdp`.
