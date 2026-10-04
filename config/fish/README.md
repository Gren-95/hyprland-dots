# Fish

Only hand-written config is tracked here. Plugin files (and tool-generated
completions or `fish_frozen_*` theme files) are gitignored; on a fresh machine
restore the plugins with:

```fish
fisher update      # reads fish/fish_plugins; install fisher first if missing
fish ~/.config/fish/tide-stone/apply.fish   # tide colours (universal variables)
```

## Plugins (`fish_plugins`)

| Plugin | Purpose |
|---|---|
| `jorgebucaran/fisher` | Plugin manager |
| `jorgebucaran/autopair.fish` | Auto-close brackets and quotes |
| `meaningful-ooo/sponge` | Drop failed commands from history |
| `franciscolourenco/done` | Desktop notification when a long command finishes |
| `edc/bass` | Run bash snippets and import their env |
| `patrickf1/fzf.fish` | fzf key bindings (history, files, git, processes) |
| `patrickf1/colored_man_pages.fish` | Coloured `man` |
| `ilancosman/tide@v6` | Prompt, coloured by `tide-stone/` |

## Own files

- `config.fish`: abbreviations, fzf colours, zoxide (init output cached in `~/.cache/fish`), PATH, `reload`, `claude` alias.
- `conf.d/`: `claude.fish` (config dir), `rustup.fish` (cargo PATH), `util-env.fish` (loads `scripts/util.env`, skipping secrets), `esc2pipe.fish` (Esc inserts ` |`; still closes the pager).
- `functions/`: `ipa` (IPs), `mvup` (flatten subdirs, never overwrites), `upi` (update everything), `cless`, `kb` (fzf over Hyprland keybinds; abbr `keys`), `dots` (`status` / `fix` via dotfiles-manager.sh), `music` (`start|stop|toggle`).
- Abbreviations: DNF (`up in are re dls`), Flatpak (`fup fin fare fre`), `fishup`, `sdn`, `backup`, `st`, `rpgmd`, `nf`, `cls`, `vi`/`vim` (nvim), `keys`.
- `tide-stone/`: the Stone colour preset for tide, see its README.
