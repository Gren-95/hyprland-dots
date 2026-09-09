# Stone — a tide colour preset

`stone.fish` recolours the [tide](https://github.com/IlanCosman/tide) prompt
with the palette in [`quickshell/Theme.qml`](../../quickshell/Theme.qml), so the
prompt reads as part of the same system as the bar, the window borders and the
lock screen.

Shape is unchanged — this is still tide's **Lean** style, two lines, no frames.
Only the 91 colour variables are replaced.

## Apply

```fish
fish ~/.config/fish/tide-stone/apply.fish
```

tide stores its colours in fish universal variables, so this only needs running
once. `fisher update` replaces tide's own files but leaves universal variables
alone; re-running afterwards is idempotent.

Running tide's own wizard (`tide configure`) overwrites these variables with one
of its built-in presets. Re-run `apply.fish` afterwards.

## Colour assignments

Semantics match the shell's: green = ok, yellow = warn, red = danger, and
accentPrimary (blue) marks the thing you are actually looking at — here, the
path.

| Item | Colour | |
|---|---|---|
| pwd dirs / anchors | `3b82f6` / `60a5fa` | accent, accent bright |
| git branch, upstream | `34d399` | teal |
| git dirty | `eab308` | warn |
| git staged | `f97316` | orange |
| git conflicted, operation | `ef4444` | danger |
| git untracked | `94a3b8` | slate |
| character ok / failed | `22c55e` / `ef4444` | |
| cmd duration, time | `78716c` | mutedDeep |
| context default / root / ssh | `a8a29e` / `ef4444` / `f97316` | |

Tool badges (node, rustc, python, docker, aws…) keep a hue near their usual
brand colour so they stay tellable apart, but every value comes from the
palette.

## On making this an official tide style

Looked into it; not worth pursuing upstream as things stand.

Two reasons. First, structural: in tide a *style* means prompt **shape** —
Lean, Classic, Rainbow — and each style hardcodes its own palette in
`configure/configs/<style>.fish`. Colour is not an independent axis; the wizard
only offers "True color" vs "16 colors". Stone reuses Lean's shape exactly, so
it is a palette, not a style. Landing it properly would mean adding a
palette/colour-scheme step to the wizard — a feature change, not a new file.

Second, practical: the repo is close to dormant. Last non-bot commit
2025-08-03, last release v6.2.0 (2025-08), 160 open issues and 34 open pull
requests, the oldest sitting unmerged since 2024-01. A style PR would very
likely sit there too.

The realistic route, if this is ever worth sharing, is a fisher-installable
plugin — a small repo whose `conf.d/` applies these variables. That needs
nobody's review, and `stone.fish` is already written in tide's own preset
format, so it would drop straight in if tide ever grows a palette axis.
