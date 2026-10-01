# Development

Lint checks and the pre-commit hook.

[`.github/workflows/lint.yml`](../.github/workflows/lint.yml) runs on every push and
pull request. [`.githooks/pre-commit`](../.githooks/pre-commit) runs the same checks
against the index at commit time — `setup.sh` enables it, or turn it on by hand:

```bash
git config core.hooksPath .githooks
```

Each check is skipped with a note when its tool is missing, so the hook still
works on a machine without Hyprland. Bypass it with `git commit --no-verify`.

The checks by hand:

```bash
shellcheck -S warning $(git ls-files '*.sh' | grep -v '^ranger/scope.sh$')
luac -p $(git ls-files '*.lua')
Hyprland --verify-config -c "$PWD/hypr/hyprland.lua"
./dotfiles-manager.sh status
```

`--verify-config` catches unknown config keys as well as Lua syntax errors, so
it is worth running before a reload rather than finding out from a live session.
