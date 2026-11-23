# upi

Updates everything on the machine in one go: system packages (dnf), firmware
(fwupd), Flatpak apps, AppImages (Gear Lever), npm globals, uv tools, bun and
fish plugins (fisher).

```bash
upi                       # check, list, ask once, snapshot, update
upi --check               # only list what would update
upi flatpak appimages     # only these steps
upi --skip npm,bun        # every step but these
upi --no-snapshot flatpak # a quick run without the Timeshift snapshot
upi --yes                 # do not ask
upi --last                # how the last run went
upi --list                # the steps
```

## How a run goes

1. **Guards.** One run at a time (a lock in `$XDG_RUNTIME_DIR`), at least
   10 GiB free on `/`, and a network (google.com or amazon.com answers; any
   HTTP answer counts).
2. **Check.** Every source is checked at once and nothing needs sudo:
   `dnf check-update` and the unneeded packages, `fwupdmgr get-updates`,
   `flatpak remote-ls --updates`, Gear Lever's update list, `npm outdated`,
   each uv tool against PyPI, bun against the npm registry, and each fish
   plugin's upstream commit (`git ls-remote`). Under each source comes
   everything that would change, from what to what: packages with their
   installed and new versions, firmware per device, Flatpak apps (runtimes
   without a version show as a new build of their branch), npm, uv and bun
   versions, fish plugins by commit, and the packages autoremove would take
   away. Gear Lever gives no versions, so AppImages show as "→ newer".
3. **Ask once.** "Update 17 items in 4 sources?" With nothing to update it
   stops there.
4. **Snapshot.** The sudo password is asked once (and kept fresh for the
   run), then Timeshift takes a `pre-update` snapshot. No snapshot, no
   update.
5. **Update.** Each source with work, one at a time, with a live line per
   step (spinner, time taken, result). The commands get `-y`, since the plan
   was confirmed; a failing step shows its last lines and the run goes on.
   While it runs a logind inhibitor keeps the machine awake and out of
   suspend.
6. **Summary.** What updated, what failed, whether a reboot is needed
   (`dnf needs-restarting -r`), a desktop notification, and the log path.

## GitHub API limit

Gear Lever, bun and fisher use GitHub's unauthenticated API, 60 requests an
hour per address. `upi` reads the quota first (free) and skips a step that
would run out, saying when it resets; the next run picks it up. bun's latest
version is read from the npm registry, so checking it costs nothing.

## Files

| Path | What |
|------|------|
| `~/.local/state/dots/last-update.json` | The last run: each step's result, count, time, detail and its changes from what to what; read by `upi --last` and the settings app's Updates panel |
| `~/.local/state/dots/updates/<time>.log` | The plan (every change, from what to what), then every command's full output; the newest 20 kept |
| `~/.local/state/update-all/fisher/` | The upstream commit of each fish plugin, so unchanged plugins are left alone |

## Source

| File | What |
|------|------|
| `src/main.rs` | The run: guards, check, ask, snapshot, steps, summary |
| `src/args.rs` | Command line |
| `src/steps.rs` | The steps, their names and tools |
| `src/check.rs` | Checking each source, and parsing its output |
| `src/update.rs` | Updating each source, the snapshot, the reboot check |
| `src/fisher.rs` | fish plugins against fish_plugins and their upstream commits |
| `src/github.rs` | The GitHub API quota |
| `src/record.rs` | The run record and logs |
| `src/sys.rs` | Running programs, the lock, disk and network checks, keep-awake, sudo |
| `src/ui.rs` | Spinner, result lines, the question |

Built and installed to `~/.local/bin/upi` by `dots.sh setup`; by hand:
`cargo build --release --locked && install -Dm755 target/release/upi ~/.local/bin/upi`.
