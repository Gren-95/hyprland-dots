# Quickshell widget design

Reference for the QML components that make up this shell. Aimed at "I want to
add a new modal" or "where do I change X" — not a tutorial.

## Layers

| Layer | Lives in | Examples |
|---|---|---|
| **Singletons** | `Theme.qml`, `Hypr.qml`, `TailscaleService.qml` | Design tokens (with user-tunable knobs), hyprctl dispatch helper, Tailscale CLI wrapper |
| **Root stores** | `Settings.qml` (`settingsStore`), `PopupManager.qml` (`popupManager`) | Persisted user settings + single-open flyout policy. Instantiated FIRST in shell.qml and resolved via the id scope chain — NOT singletons (see warning below) |
| **Primitives** | `BarFlyout.qml`, `PopupCard.qml`, `TabStrip.qml`, `SproutBg.qml`, `SegmentedControl.qml` | The flyout envelope, the top-drawer envelope, the speech-bubble shape, settings controls |
| **Bar items** | `BarIcon.qml`, `BarSep.qml`, `WorkspaceStrip.qml`, `MediaKeys.qml`, `OverflowChevron.qml` | Leaf widgets that sit on the top bar |
| **Bar modules** | `ConnectivityModule.qml`, `AudioPowerModule.qml`, `NotifBell.qml`, `QuickActions.qml` | Bar entry points that open their own flyout |
| **Flyout modals** | `Spotlight.qml`, `Clipboard.qml`, `Keybinds.qml`, `IcsCalendar.qml`, `Notifications.qml`, `SystemMonitor.qml`, `WallpaperPicker.qml`, `SettingsPanel.qml` | Scope-level services whose UI opens as a flyout under a bar item |
| **Drawers & overlays** | `WorkspaceOverview.qml` (top drawer strip), `PolkitPrompt.qml` (top-center drawer), `ScreenshotActions.qml` (top-right sheet), `ScreenRecorder.qml`, `Osd.qml`, `RegionSelector.qml` | Everything not anchored to a specific bar icon |
| **Reusable widgets** | `TabPill`, `PinButton`, `BtToggle`, `VolumeSlider`, `BrightnessRow`, `ProfileSelector`, `*Row` files | Pieces composed into modules |

**WARNING — config singletons don't reliably instantiate on cold start.**
A `pragma Singleton` file referenced only from component files (not from
shell.qml itself) may never instantiate: consumer binding reads just return
undefined until a change notification happens to heal them, and
`required property` Instantiator delegates abort construction silently.
Shared state therefore lives in **root-scope instances** (`settingsStore`,
`popupManager`) declared first in shell.qml — guaranteed creation order,
resolved everywhere via the id scope chain (same pattern as `notifService`).
Theme survives as a singleton only because shell.qml reads it directly.

**Unified-shell rule:** nothing opens as a free-floating centered window.
Every surface either hangs under its bar icon (`BarFlyout`), drops from the
bar edge (`PopupCard` top drawer, WorkspaceOverview strip), or is inherently
fullscreen (RegionSelector). The power menu lives in AudioPowerModule's
Power tab (SESSION row) — `quickshell:powermenu` opens that tab.

Entry point is `shell.qml`. It instantiates every modal and the per-screen bar
via `Variants { model: Quickshell.screens }`.

## Singletons

### `Theme.qml`
All design tokens. Read these instead of hard-coding values.

- `Theme.fg / fgMuted / fgDim / mutedDeep / muted` — text colors, light → dark
- `Theme.bg / bgAlt / bgDeep / bgHover` — surface colors
- `Theme.accent.{blue,green,red,orange,yellow,purple,slate}` — semantic accents
- `Theme.border / borderStrong / borderSubtle` — separator/border lines
- `Theme.fontSize.{xs,sm,base,md,lg,xl,xxl,hero,huge}` — type scale
- `Theme.spacing.{xs,sm,md,lg,xl,xxl}` — gaps and margins
- `Theme.height.{chip,control,row,rowSm,tile,card}` — vertical sizes
- `Theme.radius.{sm,md,lg}` — corner radii
- `Theme.duration.{fast=120, normal=180, slow=240}` — animation durations (ms)
- `Theme.easing.{standard=OutCubic, emphasized=OutBack, decelerated=OutQuad}`
- `Theme.font` — primary font family

### `Hypr.qml`
Hyprland dispatch wrapper. `Hypr.dispatch("workspace e+1")` instead of
spawning `hyprctl dispatch …` by hand.

### `TailscaleService.qml`
Wraps the `tailscale` CLI. Properties: `state`, `tailnet`, `host`, `selfIPs`,
`peers`, `exitNodeId`, `daemonOk`, `running`. Methods: `refresh()`, `toggle()`,
`setExitNode(id)`, `copyIp(ip)`. Background poll every 15s, fast poll every 4s
while the VPN tab is open.

### `Settings.qml` (instantiated as `settingsStore`)
Typed schema-driven settings engine. One tiny file per setting under
`~/.config/quickshell/settings/` (gitignored), written via `FileView.setText` (atomic, watched).
To add a setting: declare a typed property with its default + one `_schema`
row (`{ name, file, type }`, type ∈ bool/int/real/string/json). External
edits load into the property; property writes persist. Absent file = QML
default. Maps (`json` type) must be REASSIGNED, never mutated.
Also owns the bar-placement API: `placement(id)` / `setPlacement(id, p)` /
`trayPlacementOf(tid)` / `setTrayPlacement(tid, p)` with p ∈
`"bar" | "overflow" | "hidden"`, and `flyoutSize(id, dim, def)` /
`setFlyoutSize(id, dim, v)` for per-flyout geometry.
Do NOT use `required property var modelData` in its Instantiator delegate —
it silently aborts construction (context `modelData` only).

### `PopupManager.qml` (instantiated as `popupManager`)
Single-open policy for flyouts. `BarFlyout` registers itself in
`onOpenChanged`; opening one flyout closes whatever else was open
(close-then-open so focus grabs never overlap). `popupManager.closeAll()`
force-closes the current one.

### `SettingsPanel.qml` (`quickshell:settings`, Super+,)
Tabbed settings flyout under the Quick Actions chevron (also opened from
the gear tile). Tabs: **General** (clock, notifications, power), **Bar**
(bar items, Quick Actions items, live tray apps — Bar/Tuck/Hide), **Appearance**
(highlight accent swatches, font scale, bar height, font family),
**Tuning** (module knobs, calendar URL, wallpaper dir, flyout sizes).

### `OverflowChevron.qml`
Windows-style hidden-tray ˄ before the tray. Hosts overflow tray apps as
real `TrayItem`s (the flyout pins itself while a context menu is open —
`TrayItem.menuOpen` counting) and overflow modules as launcher rows that
call `entry.open(chev)` → `module.openTab(tab, chev)`, re-anchoring the
module flyout to the chevron. Hidden entirely when nothing is in overflow.

### Theme knobs
`Theme.fontScale` / `fontFamily` / `accentPrimaryName` are pushed in from
shell.qml via `Binding` elements (a singleton can't resolve settingsStore).
`Theme.accentPrimary` is THE highlight/selection accent — use it for
selected rows, active pills, focused cards; keep semantic accents
(red=danger, green=ok…) fixed.

### Flyout anchoring override
Modules with tabs expose `openTab(name, from)` — `from` re-anchors the
flyout under whatever opened it (satellite icons, overflow rows) via
`_openAnchor`; `flyoutAnchor` is the placement-aware default bound in
shell.qml. Fallback chain: `_openAnchor ?? flyoutAnchor ?? self`.

## Primitives

### `BarFlyout`
The single popup primitive: a card hanging directly under a bar item, with
the SproutBg tail pointing up at it, growing downward out of the bar. Used
by every bar module and flyout modal. Wraps `PopupWindow + SproutBg +
animated FocusScope`. Content goes directly inside the braces — it lands in
the inner FocusScope via the default property alias, below the tail.
Positioning is computed into `anchor.rect`: centered under `anchorItem`,
clamped to the screen edges (the tail keeps tracking the icon when clamped).
Registers with `PopupManager` so only one flyout is open at a time.
Unaccepted Escape closes by default.

```qml
BarFlyout {
    parentBar: bar
    anchorItem: someBarIcon   // the item it hangs from
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

**Anchor wiring for Scope-level modals**: modals instantiated in `shell.qml`
(Spotlight, Clipboard, Keybinds, SystemMonitor, WallpaperPicker, IcsCalendar,
Notifications) expose `anchorBar` / `anchorItem` properties, assigned once
from the bar's `Component.onCompleted` (or the anchor item's, for the
clock/bell). Their flyout binds
`open: root.open && root.anchorBar !== null`.

### `PopupCard`
Top drawer: a card hanging from the bar's bottom edge — top-center by
default, `edge: "right"` for toast-like sheets. Used by `PolkitPrompt`
(exclusive keyboard, no click-away) and `ScreenshotActions` (top-right).
Pass content via `contentComponent: Component { … }`.

### `TabStrip`
Rounded pill container for tab navigation. Used by `ConnectivityModule` and
`AudioPowerModule`.

```qml
TabStrip {
    activeId: mod.activeTab
    onPicked: (id) => mod.setTab(id)
    tabs: [
        { glyph: "󰂯", label: "Bluetooth", accent: Theme.accent.blue, id: "bluetooth" },
        { glyph: "󰖩", label: "Wi-Fi",     accent: Theme.accent.green, id: "wifi" }
    ]
}
```

### `SproutBg`
The speech-bubble background shape (rounded rect + optional tail).

## Bar modules

Each module is an `Item` placed inside the bar's right or center group.
Pattern:

- Renders an icon row centered in its bounds (`anchors.centerIn`)
- `MouseArea anchors.fill: parent` handles clicks
- Owns its own popup (usually `BarPopupCard`)
- Exposes `parentBar`, `popupOpen`, `pinned` properties
- Exposes `openTab(name)` for tab-switching consumers

`QuickActions` is the catch-all overflow panel: stateful toggles (DnD, Stay
Awake, Immich/Jellyfin sync, Remote access, Media keys) + a 3-column grid of
one-shots (Clipboard, Screenshot, Record, Color picker, Keybinds, Wallpaper).
Bound to `Super+A`.

`MediaKeys` is a special bar item — it sits in the gap between the centered
clock and the right systray (positioned via a wrapper Item with anchors
`left: clockAnchor.right, right: rightGroup.left`, MediaKeys `anchors.centerIn`).
Compact MPRIS-driven chip with optional track title + prev/play-pause/next
buttons. Visibility bound to `Settings.mediaKeysVisible` (toggled from
Quick Actions). Auto-prefers Playing player when multiple exist; wheel-scroll
on the chip cycles through controllable players; inline `N/M` counter shown
when >1 player.

## Modals

All flyouts and drawers share the same open animation: scale `0.94–0.96 → 1.0`,
opacity `0 → 1`, `transformOrigin: Item.Top` (grow out of the bar),
`Theme.duration.normal`, `Theme.easing.standard`.

Flyout anchor map: launcher icon → Spotlight, Clipboard, Keybinds ·
clock → IcsCalendar · bell → Notifications center · clock cluster →
SystemMonitor · Quick Actions chevron → WallpaperPicker, QuickActions ·
their own bar icons → ConnectivityModule, AudioPowerModule, MediaKeys.

Each modal exposes:
- `property bool open: false`
- `function toggle()` and `function close()`
- An `openAt(idx)` helper that focuses a specific entry (for cross-modal nav)

Cross-modal Ctrl+Left/Right navigation is wired in `shell.qml` via
`navigateNext` / `navigatePrev` signals on each module.

### Notable modals (post-initial-doc additions)

- **`SystemMonitor`** (`Super+M`) — CPU + per-core grid, RAM, all mounted
  filesystems, CPU/NVMe temps, fans, uptime. Backed by `scripts/sysinfo.sh`
  emitting a single JSON line every 1.5s.
- **`WallpaperPicker`** — 3-column scrolling grid of thumbnails from
  `~/Pictures/wallpapers`. Click sets via `scripts/wallpaper.sh <path>`.
  Opened from Quick Actions' Wallpaper tile.
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
  the backing process. Use an `inFlightTimer` to pause the periodic probe for
  ~800ms so stale reads don't bounce the UI back. See `QuickActions.qml`.

## Adding a new modal

1. Create `MyModal.qml`. Root is `Scope`.
2. Add `property bool open: false`, `function toggle()`, `function close()`,
   plus `property var anchorBar: null` / `property var anchorItem: null`.
3. Use `BarFlyout { parentBar: root.anchorBar; anchorItem: root.anchorItem;
   open: root.open && root.anchorBar !== null; … }` with content inside the
   braces. (Only use `PopupCard` for bar-edge drawers with no natural icon.)
4. Pick the bar item it should hang from and assign the anchors in the bar's
   `Component.onCompleted` in `shell.qml`.
5. Add a plain-English modal title at the top of the content.
6. Add uppercase section headers above each visual grouping.
7. Instantiate it once at the top of `shell.qml`: `MyModal { id: myModal }`.
8. Wire keybind: add `GlobalShortcut { name: "mymodal"; onPressed: myModal.toggle() }`
   in the bar, and `bind = $mainMod, X, global, quickshell:mymodal` in
   `hypr/modules/keys.conf`.

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
`AudioPowerModule.qml` / `ConnectivityModule.qml`.

## Logging

Quickshell logs to `/run/user/1000/quickshell/by-id/<id>/log.qslog` (binary;
read with `qs log <file>`). QML `console.warn(…)` lands there with category
`qml:`. `console.log` is usually filtered out — use `console.warn` for
ad-hoc debug. The wrapped shell scripts log via `scripts/lib/notify.sh` for
user-visible notifications; daemon output mostly goes to `/dev/null` (see
`scripts/restart.sh`).
