# Development

Lint checks and the pre-commit hook.

[`.github/workflows/lint.yml`](../.github/workflows/lint.yml) runs on every push and
pull request. [`.githooks/pre-commit`](../.githooks/pre-commit) runs most of the same
checks against the index at commit time (CI alone also runs fish `--no-execute`,
`systemd-analyze verify` on the user units, and actionlint on the workflows) — `dots.sh setup` enables it, or turn it on by hand:

```bash
git config core.hooksPath .githooks
```

Each check is skipped with a note when its tool is missing, so the hook still
works on a machine without Hyprland. Bypass it with `git commit --no-verify`.

The checks by hand:

```bash
sh_files=$(git ls-files '*.sh' .githooks | grep -v '^config/ranger/scope.sh$')
shellcheck -S warning $sh_files
shfmt -d $sh_files
for f in $sh_files; do bash -n "$f"; done
luac -p $(git ls-files '*.lua')
Hyprland --verify-config -c "$PWD/config/hypr/hyprland.lua"
for f in $(git ls-files 'config/fish/*.fish'); do fish --no-execute "$f"; done
systemd-analyze --user --man=no verify systemd/user/*.service systemd/user/*.timer
bash docs/check-keybinds.sh   # KEYBINDS.md matches keys.lua
./dots.sh status
```

The QML JavaScript helper `config/quickshell/IcsParse.js` has unit tests in
`tests/`; the settings app has its own (`cargo test` in `apps/settings`). Neither CI
nor the hook runs them yet; run them by hand after changing either file:

```bash
node --test tests/*.test.js
```

`--verify-config` catches unknown config keys as well as Lua syntax errors, so
it is worth running before a reload rather than finding out from a live session.
