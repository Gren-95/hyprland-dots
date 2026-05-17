# Quickshell widget design

Reference for the QML components that make up this shell. Aimed at "I want to
add a new modal" or "where do I change X" — not a tutorial.

## Layers

| Layer | Lives in | Examples |
|---|---|---|
| **Singletons** | `Theme.qml`, `Hypr.qml`, `TailscaleService.qml` | Design tokens, hyprctl dispatch helper, Tailscale CLI wrapper |
| **Primitives** | `BarPopupCard.qml`, `PopupCard.qml`, `TabStrip.qml`, `SproutBg.qml` | Reusable popup envelopes + the speech-bubble shape |
| **Bar items** | `BarIcon.qml`, `BarSep.qml`, `WorkspaceStrip.qml` | Leaf widgets that sit on the top bar |
| **Bar modules** | `ConnectivityModule.qml`, `AudioPowerModule.qml`, `NotifBell.qml`, `QuickActions.qml` | Bar entry points that open their own popup |
| **Modals** | `Spotlight.qml`, `Clipboard.qml`, `Keybinds.qml`, `PowerMenu.qml`, `PolkitPrompt.qml`, `IcsCalendar.qml`, `Notifications.qml`, `WorkspaceOverview.qml`, `ScreenRecorder.qml`, `Osd.qml` | Centered or bar-anchored overlays |
| **Reusable widgets** | `TabPill`, `PinButton`, `BtToggle`, `VolumeSlider`, `BrightnessRow`, `ProfileSelector`, `*Row` files | Pieces composed into modules |

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

## Primitives

### `BarPopupCard`
Bar-anchored centered popup. Used by `ConnectivityModule`, `AudioPowerModule`,
`IcsCalendar`. Wraps `PopupWindow + SproutBg + animated FocusScope`. Content
goes directly inside the braces — it lands in the inner FocusScope via the
default property alias.

```qml
BarPopupCard {
    parentBar: bar
    open: mod.popupOpen
    cardWidth: 360
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

### `PopupCard`
Full-screen-backdrop centered modal. Used by `Spotlight`, `Clipboard`,
`Keybinds`, `PowerMenu`, `PolkitPrompt`. Pass content via
`contentComponent: Component { … }` (the default alias breaks inside the
per-screen `Variants` delegate).

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
Awake, Immich/Jellyfin sync, Remote access) + a 3-column grid of one-shots
(Clipboard, Screenshot, Record, Color picker, Keybinds).

## Modals

All centered modals share the same open animation: scale `0.96 → 1.0`,
opacity `0 → 1`, `Theme.duration.normal`, `Theme.easing.standard`.

Each modal exposes:
- `property bool open: false`
- `function toggle()` and `function close()`
- An `openAt(idx)` helper that focuses a specific entry (for cross-modal nav)

Cross-modal Ctrl+Left/Right navigation is wired in `shell.qml` via
`navigateNext` / `navigatePrev` signals on each module.

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
2. Add `property bool open: false`, `function toggle()`, `function close()`.
3. For centered-modal layout, use `PopupCard { contentComponent: Component { … } }`.
4. For bar-anchored, use `BarPopupCard` and treat the consumer as a bar module.
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
