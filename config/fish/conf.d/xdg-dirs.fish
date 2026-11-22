# Keep tool data out of the top of $HOME (XDG locations instead of ~/.bun, ~/.npmrc, ~/.python_history).
set -gx BUN_INSTALL $HOME/.local/share/bun
set -gx NPM_CONFIG_USERCONFIG $HOME/.config/npm/npmrc
set -gx PYTHON_HISTORY $HOME/.local/state/python/history
