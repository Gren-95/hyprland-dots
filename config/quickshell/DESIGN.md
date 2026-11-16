# Quickshell widget design

Reference for the QML components that make up this shell. Aimed at "I want to
add a new modal" or "where do I change X" — not a tutorial.

## Layers

| Layer | Lives in | Examples |
|---|---|---|
| **Singletons** | `Theme.qml`, `Paths.qml`, `Backlight.qml`, `Cmd.qml`, `Hypr.qml`, `TailscaleService.qml`, `AirPodsBattery.qml` | Design tokens (with user-tunable knobs), script directory, backlight device discovery, run-a-command-and-report-failure helper, hyprctl dispatch helper, Tailscale CLI wrapper, AirPods battery from librepods |
| **Root stores** | `Settings.qml` (`settingsStore`), `PopupManager.qml` (`popupManager`) | Persisted user settings + single-open flyout policy. Instantiated FIRST in shell.qml and resolved via the id scope chain — NOT singletons (see warning below) |
| **Primitives** | `BarFlyout.qml`, `PopupCard.qml`, `SproutBg.qml` | The flyout envelope, the top-drawer envelope, the speech-bubble shape |
| **Bar items** | `BarIcon.qml`, `BarSep.qml`, `BarHover.qml`, `BarTooltip.qml`, `WorkspaceStrip.qml`, `StatusIndicators.qml`, `QuickActionIcon.qml`, `TrayItem.qml` | Leaf widgets that sit on the top bar (hover highlight, tooltip, activity dots, promoted Quick Actions items, tray icons) |
| **Bar modules** | `ConnectivityModule.qml`, `SoundModule.qml`, `PowerModule.qml`, `NotifBell.qml`, `QuickActions.qml`, `ServicesModule.qml` | Bar entry points that open their own flyout |
| **Flyout modals** | `Spotlight.qml`, `Clipboard.qml`, `Keybinds.qml`, `DayPanel.qml`, `SystemMonitor.qml`, `GameLauncher.qml` | Scope-level services whose UI opens as a centred flyout |
| **Services (headless)** | `IcsCalendar.qml`, `Notifications.qml`, `WeatherService.qml`, `IdleService.qml`, `AccentService.qml`, `SuperWatch.qml`, `GameModeService.qml`, `RemoteSyncStatus.qml`, `EventToasts.qml` | State and system plumbing with no surface of their own; panes read them (EventToasts turns charger/VPN/audio/layout changes into toasts) |
| **JavaScript helpers** | `IcsParse.js`, `KeybindSearch.js` | Pure logic with no QML types (ICS parsing and recurrence, keybind combo search); unit-tested under node in `tests/` |
| **Panes** | `CalendarPane.qml`, `EventsPane.qml`, `NotifPane.qml`, `MediaCard.qml`, `WeatherCard.qml`, `BatteryCard.qml`, `AudioSection.qml`, `AudioAppsSection.qml`, `DayCard.qml`, `DayCell.qml`, `DayScroll.qml` | Views over a service, composed into a flyout |
| **Drawers & overlays** | `WorkspaceOverview.qml` (top drawer strip), `WallpaperDeck.qml` (card fan), `PolkitPrompt.qml` (top-center drawer), `ScreenshotActions.qml` (top-right sheet), `ScreenRecorder.qml`, `Osd.qml`, `RegionSelector.qml` | Everything not anchored to a specific bar icon |
| **Reusable widgets** | `PinButton`, `VolumeSlider`, `BrightnessRow`, `ProfileSelector`, `QaTile`, `SysGauge`, `SysGraph`, `Spinner`, `ThinScrollBar`, `LazyView`, `Launcher*` (Spotlight parts), `*Row` files | Pieces composed into modules; `LazyView` builds a modal's window only while it is open |

**WARNING — config singletons don't reliably instantiate on cold start.**
A `pragma Singleton` file referenced only from component files (not from
shell.qml itself) may never instantiate: consumer binding reads just return
undefined until a change notification happens to heal them, and
`required property` Instantiator delegates abort construction silently.
Shared state therefore lives in **root-scope instances** (`settingsStore`,
`popupManager`) declared first in shell.qml — guaranteed creation order,
resolved everywhere via the id scope chain (same pattern as `notifService`).
Theme survives as a singleton only because shell.qml reads it directly;
`Paths`, `Backlight` and `Cmd` are kept alive by `_singletons` in shell.qml.

**Unified-shell rule:** every surface is one of three kinds: a `BarFlyout`
(centred on the screen of the bar that opened it, one at a time), a drop from
the bar edge (`PopupCard` top drawer, WorkspaceOverview strip), or inherently
fullscreen (RegionSelector). The power menu is PowerModule's popup (session buttons on the bottom row);
`quickshell:powermenu` toggles it.

Entry point is `shell.qml`. It instantiates every modal and the per-screen bar
via `Variants { model: Quickshell.screens }`.

## Singletons

`qmldir` lists every type in this directory. Quickshell does not need it —
it resolves file-local types itself — but qmllint cannot resolve them without
it, so add an entry when you add a file.


### `Theme.qml`
All design tokens. Read these instead of hard-coding values.

- `Theme.fg / fgMuted / fgDim / mutedDeep / muted` — text colors, light → dark
- `Theme.bg / bgAlt / bgDeep / bgHover` — surface colors
- `Theme.accent.{blue,green,red,orange,yellow,purple,pink,teal,slate}` — semantic accents; `blueBright`, `redSoft` (glyphs on dark surfaces) and `redDeep`, `blueDeep`, `purpleDeep` (filled controls)
- `Theme.border / borderStrong / borderSubtle` — separator/border lines
- `Theme.alpha(color, a)` / `Theme.scrim` — a colour at opacity `a`; `scrim` is the base for dimming layers and shadows (`Theme.alpha(Theme.scrim, 0.5)`)
- `Theme.fontSize.{xs,sm,base,md,lg,xl,xxl,hero,huge}` — type scale
- `Theme.spacing.{xs,sm,md,lg,xl,xxl}` — gaps and margins
- `Theme.height.{chip,control,row,rowSm,tile,card}` — vertical sizes
- `Theme.radius.{sm,md,lg,xl}` — corner radii
- `Theme.duration.{fast=120, normal=180, slow=240}` — animation durations (ms)
- `Theme.easing.{standard=OutCubic, emphasized=OutBack, decelerated=OutQuad}`
- `Theme.font` — primary font family

### `Hypr.qml`
Hyprland dispatch wrapper. Takes a Lua dispatcher expression, as Hyprland's
Lua config requires: `Hypr.dispatch("hl.dsp.focus({ workspace = 3 })")`, or
`Hypr.focusWorkspace(3)`, instead of spawning `hyprctl dispatch …` by hand.

### `TailscaleService.qml`
Read-only `tailscale status` poll (every 15s) behind the "VPN up/down" event
toasts. Properties: `state`, `tailnet`, `running`. Method: `refresh()`.
Control (on/off) is nm-applet's job in the tray, through the NetworkManager
Tailscale VPN plugin.

### `Settings.qml` (instantiated as `settingsStore`)
Typed schema-driven settings engine. One tiny file per setting under
`~/.config/quickshell/settings/` (gitignored), written via `FileView.setText` (atomic, watched).
To add a setting: declare a typed property with its default + one `_schema`
row (`{ name, file, type }`, type ∈ bool/int/real/string/json). External
edits load into the property; property writes persist. Absent file = QML
default. Maps (`json` type) must be REASSIGNED, never mutated.
Also owns read-only lookups over the JSON settings: `placement(id)`,
`trayPlacementOf(tid)` and `qaPlacementOf(key)` with results in
`"bar" | "overflow" | "hidden"`, `flyoutSize(id, dim, def)` for per-flyout
geometry, and `isAppHidden(id)` / `setAppHidden(id, hidden)` for the launcher.
There is no settings UI for placements or flyout sizes: change them by
editing `bar-placement.json`, `tray-placement.json`, `qa-placement.json` or
`flyout-sizes.json` in the settings folder (the shell reloads them).
Do NOT use `required property var modelData` in its Instantiator delegate —
it silently aborts construction (context `modelData` only).

### `PopupManager.qml` (instantiated as `popupManager`)
Single-open policy for flyouts. `BarFlyout` registers itself in
`onOpenChanged`; opening one flyout closes whatever else was open
(close-then-open so focus grabs never overlap). `popupManager.closeAll()`
force-closes the current one.

### Overflow model (no chevron)
Quick Actions is the single overflow surface: tucked bar modules render as
grid tiles (`quickMod.moduleEntries`, wired in shell.qml) and tucked tray
apps render as a `TrayItem` row above the grid (the flyout pins itself
while a tray context menu is open — `TrayItem.menuOpen` counting).

### Theme knobs
`Theme.fontScale` / `fontFamily` / `accentPrimaryName` are pushed in from
shell.qml via `Binding` elements (a singleton can't resolve settingsStore).
`Theme.accentPrimary` is THE highlight/selection accent — use it for
selected rows, active pills, focused cards; keep semantic accents
(red=danger, green=ok…) fixed.

### Opener highlight
`ConnectivityModule`, `SoundModule` and `PowerModule` expose
`toggleOpen(from)`. `from` (a promoted icon, a Quick Actions tile) is kept in
`_openAnchor` so the bar highlights whatever opened the flyout; it does not
move the flyout, which is always centred.

## Primitives

### `BarFlyout`
The single popup primitive: a card centred on the screen of `parentBar`.
Used by every bar module and flyout modal. Wraps `PopupWindow + SproutBg +
animated FocusScope`. Content goes directly inside the braces — it lands in
the inner FocusScope via the default property alias. Registers with
`PopupManager` so only one flyout is open at a time. Bar modules still keep
`_openAnchor` (the icon that opened them), but only for the bar highlight.
Unaccepted Escape closes by default.

```qml
BarFlyout {
    parentBar: bar            // the flyout opens centred on this bar's screen
    open: mod.popupOpen
    cardWidth: 380
    cardHeight: 460
    pinned: mod.pinned
    onDismissed: mod.popupOpen = false
    onKeyPressed: (e) => { /* handle keys */ }

    // Content (default-alias goes into FocusScope)
    ColumnLayout { /* ... */ }
}
```

**Critical**: `onDismissed` must clear the consumer's open state via the
binding source (e.g. `mod.popupOpen = false`). Do not assign to `card.open`
directly — it breaks the `open: mod.popupOpen` binding and the popup can't
reopen.

**Bar wiring for Scope-level modals**: modals instantiated in `shell.qml`
(Spotlight, Clipboard, Keybinds, SystemMonitor, DayPanel) expose an
`anchorBar` property, bound once to the active bar from the bar's
`Component.onCompleted`. Their flyout binds
`open: root.open && root.anchorBar !== null`. DayPanel also keeps
`anchorItem` (clock or bell) so the opener stays highlighted.

### `PopupCard`
Top drawer: a card hanging from the bar's bottom edge — top-center by
default, `edge: "right"` for toast-like sheets. Used by `PolkitPrompt`
(exclusive keyboard, no click-away) and `ScreenshotActions` (top-right).
Pass content via `contentComponent: Component { … }`.

### `SproutBg`
The flyout background: a rounded rect with an optional tail (BarFlyout
draws it without the tail).

## Bar modules

Each module is an `Item` placed inside the bar's right or center group.
Pattern:

- Renders an icon row centered in its bounds (`anchors.centerIn`)
- `MouseArea anchors.fill: parent` handles clicks
- Owns its own popup (usually a `BarFlyout`)
- Exposes `parentBar`, `popupOpen`, `pinned` properties
- Exposes `toggleOpen(from)` (records the opener for the bar highlight) and `openAt(idx)` for the Ctrl+Left/Right ring

`QuickActions` is the catch-all overflow panel: stateful toggles (Microphone,
Activity icons) + a 3-column grid of one-shots (Clipboard, Screenshot, Record,
Color picker, Keybinds). Bound to `Super+A`. Two sets of toggles
have moved out to sit beside what they describe: Do Not Disturb and Stay Awake
are in the day panel, and Immich/Jellyfin sync, Remote access and Windows VM
are in `ServicesModule` — duplicating them here left two places to look and
two probes polling the same scripts. All of them stay searchable in Spotlight,
which now concatenates `servicesMod.spotlightActions` onto the Quick Actions
arrays.

`ServicesModule` sits beside Quick Actions and is the read-out to its remote
control: three session daemons (battery-notify, power-auto, dotwatch), the
two scheduled syncs, and three on-demand services (remote access, Windows VM,
games browser). It is the only place to flip them; it also shows whether
`dotwatch` survived the last session and when the Jellyfin timer next fires. One probe backs the whole panel —
`scripts/services-status.sh` prints `key=value` pairs on one line, so no shell
pipeline lives in a QML string literal. A running daemon is not clickable
(there is nothing to do); a dead one starts on click, detached, because a
daemon parented to Quickshell would die with the next reload — which is the
very failure the panel exists to report. The bar glyph turns orange only for a
session daemon that should be up and isn't; everything else being off is a
choice, not a fault. Openable as `quickshell:services` (no key bound by
default).

`MediaCard` is the MPRIS now-playing card at the top of the day panel's
notification column: art, title/artist, scrub bar, prev/play-pause/next. It
has no visibility setting — it shows whenever something is playing and
collapses to zero height when nothing is. Auto-prefers the Playing player when
multiple exist; wheel-scroll cycles through controllable players; an inline
`N/M` counter appears when there is more than one.

## The day panel

`DayPanel.qml` is the one flyout behind both `Super+D` and `Super+N`: the
calendar column (`CalendarPane`) on the left, the notification column
(`NotifPane`) on the right, split by a hairline. It owns the open/pinned state
and the keyboard map; the two panes are pure views over the `IcsCalendar` and
`Notifications` services, which hold every piece of state between them.

- Opening re-centres the calendar on today and marks the history seen —
  `notifs.panelOpen` is bound to the panel's `open`, so the unread badge
  clears and the app groups collapse without anyone calling a method.
- Unmodified arrow keys, `PgUp`/`PgDn`, `T` and `Home` drive the calendar
  column; `Ctrl+←/→` still walks the flyout nav ring.
- The single pin lives in the calendar header, since that's the panel's
  leading edge.
- `WeatherCard` sits under the calendar header — the header row is already a
  title plus four controls, and the reading has more to say than fits between
  them. `WeatherService` pulls current conditions, today's daily block and the
  hourly series in one open-meteo request, so feels-like, high/low, humidity,
  wind, sun times and the next twelve hours cost no extra round trip. Condition
  glyphs take their bucket's accent and temperatures run through `tempColor`, a
  deliberately coarse warm-to-cool ramp. Hidden entirely when no location is
  configured.
- The hourly strip answers "when does it rain" twice over: `rainSummary` says
  it in words (`Rain 19:00–23:00 · peak 85%`), and the bars say it in shape.
  The bars plot one measure — chance of rain as height — so colour is not a
  second copy of it: every bar is the same hue, dim below `rainThreshold` and
  full above, which leaves the hours worth caring about as the ones that stand
  out. Only the peak is labelled; hovering a bar swaps the summary line for
  that hour. A dry day is a hairline baseline and nothing else.
- Do Not Disturb and Stay Awake are pills under the notification header.
  Neither is in the Quick Actions grid any more: DND decides what lands in
  the list right below it, and Stay Awake is the other "stop interrupting
  me" switch, so both read better here. Stay Awake names its automatic
  condition (media / AC) when something other than the manual switch is
  holding sleep off. Both remain searchable in the Spotlight palette.

## Modals

All flyouts and drawers share the same open animation: scale `0.94–0.96 → 1.0`,
opacity `0 → 1`, `transformOrigin: Item.Center` for flyouts (`Item.Top` for drawers that drop from the bar),
`Theme.duration.normal`, `Theme.easing.standard`.

What opens what from the bar: launcher icon → Spotlight · clock and bell →
DayPanel (same surface) · Quick Actions chevron → QuickActions, whose tiles
open Clipboard and Keybinds · own icons → ConnectivityModule, SoundModule ·
battery icon → PowerModule. SystemMonitor has no bar opener (`Super+M` or
Spotlight).

Each modal exposes:
- `property bool open: false`
- `function toggle()` and `function close()`
- Members of the Ctrl+Left/Right ring (Spotlight, DayPanel, QuickActions,
  Sound, Power, Connectivity) also expose `openAt(idx)`, which opens with a
  specific entry focused

Cross-modal Ctrl+Left/Right navigation is wired in `shell.qml` via
`navigateNext` / `navigatePrev` signals on each module.

### Spotlight's second mode: picking a default app

`Default browser` / `terminal` / `editor` / `file manager` in the command
palette do not open anything — they call `spotlight.startPick(role)`, which
keeps the launcher up and turns the same list into a chooser: apps filtered to
the role's freedesktop category, Enter assigns instead of launching, Escape
backs out to the normal list rather than closing.

Two details make it behave:
- `activate()` skips its usual `close()` when the action left `pickRole` set,
  otherwise the launcher would shut the instant the mode opened.
- The assignment goes through `scripts/default-app.sh set`, never straight to
  a config file. Browser and file manager have real XDG defaults, so that
  script writes those too — picking a browser here also changes what a link in
  another app opens. Terminal and editor have no such standard, which is why
  the Hyprland binds call `default-app.sh run <role>` instead of naming a
  command: `var_terminal` and `var_fileManager` in `general.lua` route through
  it, so a pick takes effect without editing the config.

### Hiding apps from the launcher

`Ctrl+D` drops the highlighted app; `Hidden apps` in the palette reopens the
same list showing only what is hidden, where Enter puts one back. Both stay
open after acting — hiding a run of entries should not mean reopening the
launcher between each one.

The list is `settingsStore.hiddenApps`, a desktop-id → true map, and it is
launcher-scoped on purpose. The alternative, writing `NoDisplay=true` into
`~/.local/share/applications/<id>.desktop` the way a menu editor does, would
apply everywhere — but it risks clobbering an entry that already lives there
(the WinApps ones do), and un-hiding would become a file deletion rather than
a value change.

`Ctrl+H` was not available for this: it is already the flyout ring's vim-left.

### Notable modals (post-initial-doc additions)

- **`SystemMonitor`** (`Super+M`) — CPU + per-core grid, RAM, all mounted
  filesystems, CPU/NVMe temps, fans, top processes, uptime. Two probes:
  `scripts/sysfast.sh` (counters, every tick at the interval picked in the
  header: 0.5/1/2/5 s) and `scripts/sysinfo.sh` (processes, disks,
  temperatures; on a slower timer).
- **`WallpaperDeck`** (`Super+W`) — a fanned hand of wallpaper cards along
  the bottom of the focused monitor. Hold Super and tap W to turn over the
  next card, dealt from a shuffle of `~/Pictures/wallpapers`; releasing Super
  applies it via `scripts/wallpaper.sh <path>`. Not a flyout — a bottom-
  anchored, click-through overlay with no anchor item.
- **`RegionSelector`** (`Super+Shift+S`) — full-screen dim overlay with
  click-drag region selection, live dimensions readout, multi-monitor-aware
  coordinate translation. Pipes the resulting `"X,Y WxH"` to
  `scripts/screenshot.sh` and chains into ScreenshotActions. (The one
  intentionally fullscreen surface besides WorkspaceOverview's strip.)
- **`ScreenshotActions`** — post-capture top-right action sheet
  (`PopupCard edge: "right"`) that opens once `screenshot.sh` echoes the
  saved path. Buttons: Edit (swappy), OCR (screenshot-ocr.sh), Reveal
  (nautilus), Done. Keys `E/O/R`, `Enter`=Edit.
- **`WorkspaceOverview`** (`Super+Tab`) — full-width top drawer strip of
  workspace cards with live grim thumbnails. Click-away closes via focus
  grab; Super release commits the highlighted workspace.

## Conventions

### Titles and section headers

Two distinct layers of text labels:

**Modal title** — plain English at the top of a modal, identifies the whole
popup. Used so users can refer to "the Network modal" or "Calendar". Style:

```qml
Text {
    text: "Audio & Power"
    color: Theme.fg
    font.family: Theme.font
    font.pixelSize: Theme.fontSize.md
    font.bold: true
    horizontalAlignment: Text.AlignHCenter
}
```

**Section header** — uppercase tag inside a modal, identifies a region.
Used so users can refer to "the BACKLIGHT section". Style:

```qml
Text {
    text: "POWER PROFILE"
    color: Theme.mutedDeep
    font.family: Theme.font
    font.pixelSize: Theme.fontSize.xs
    font.letterSpacing: 1
    font.bold: true
}
```

If the section that follows needs to sit tight against the header, set
`Layout.topMargin: -8` on the first child.

### Animations

`Theme.duration` and `Theme.easing` constants are the single source. Don't
hard-code `NumberAnimation { duration: 180 }` — use
`duration: Theme.duration.normal; easing.type: Theme.easing.standard`.

### Pinning

Modals with a `PinButton` should expose a `pinned` property and gate
`HyprlandFocusGrab.active` on `!pinned`. While pinned, focus changes don't
close the popup.

## Service patterns

- **Shell-level services** are instantiated at the top of `shell.qml`:
  `Notifications { id: notifService }`. The id should *not* collide with any
  child property name — bindings `notifs: notifService` work; `notifs: notifs`
  resolves to the child's own property instead of the outer id.
- **Periodic state probes** (daemon checks) live in the consumer module as a
  `Process` fired by a `Timer { running: popupOpen }`. Combine probes into
  one shell invocation where possible to keep `pgrep` cheap.
- **Optimistic toggles**: flip the UI state in the click handler, then start
  the backing process. Set an `inFlight` flag with a short timer that clears
  it, and skip the periodic probe while it is set, so stale reads don't bounce
  the UI back. See `inFlight` / `clearInFlight` in `IdleService.qml`.

## Adding a new modal

1. Create `MyModal.qml`. Root is `Scope`.
2. Add `property bool open: false`, `function toggle()`, `function close()`,
   plus `property var anchorBar: null`.
3. Use `BarFlyout { parentBar: root.anchorBar;
   open: root.open && root.anchorBar !== null; … }` with content inside the
   braces. (Only use `PopupCard` for bar-edge drawers with no natural icon.)
4. Bind `anchorBar` to the active bar in the bar's `Component.onCompleted`
   in `shell.qml` (`myModal.anchorBar = Qt.binding(() => shellRoot.activeBar)`).
5. Add a plain-English modal title at the top of the content.
6. Add uppercase section headers above each visual grouping.
7. Instantiate it once at the top of `shell.qml`: `MyModal { id: myModal }`.
8. Wire keybind: add an entry `{ name: "mymodal", description: "...", run: () => ... }`
   to the table in `Shortcuts.qml` (pass the modal in as a `...Ref` property), and `hl.bind(var_mainMod .. " + X", hl.dsp.global("quickshell:mymodal"))` in
   `hypr/modules/keys.lua`.

## Adding a new bar icon

Use `BarIcon` if it's a click-and-go button:

```qml
BarIcon {
    glyph: "󰂯"
    color: Theme.accent.blue
    tooltip: "Whatever"
    onClicked: someModal.toggle()
}
```

Use a full module file if it needs its own popup. Pattern is in
`SoundModule.qml` / `PowerModule.qml` / `ConnectivityModule.qml`.

## Logging

Quickshell logs to `/run/user/1000/quickshell/by-id/<id>/log.qslog` (binary;
read with `qs log <file>`). QML `console.warn(…)` lands there with category
`qml:`. `console.log` is usually filtered out — use `console.warn` for
ad-hoc debug. The wrapped shell scripts log via `scripts/lib/notify.sh` for
user-visible notifications; daemon output mostly goes to `/dev/null` (see
`scripts/restart.sh`).
