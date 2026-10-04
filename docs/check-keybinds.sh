#!/bin/bash
# Fail when KEYBINDS.md documents a Super+... combo that config/hypr/modules/keys.lua
# does not bind. Catches stale rows after a bind is removed or moved.
#
# Usage: docs/check-keybinds.sh
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec python3 - "$root/KEYBINDS.md" "$root/config/hypr/modules/keys.lua" <<'PY'
import re, sys

doc, lua = (open(p).read() for p in sys.argv[1:3])
MODS = {"SUPER": "super", "$MAINMOD": "super", "VAR_MAINMOD": "super", "SHIFT": "shift",
        "CTRL": "ctrl", "ALT": "alt"}
ALIAS = {"enter": "return", "esc": "escape", "[": "bracketleft", "]": "bracketright"}
GROUPS = {"arrow": ["left", "right", "up", "down"], "wheel": ["mouse_up", "mouse_down"],
          "drag": ["mouse:272", "mouse:273"], "1..9,0": list("1234567890")}


def norm(token):
    t = token.strip().lower()
    return ALIAS.get(t, t)


bound = set()
for m in re.finditer(r'hl\.bind\(\s*((?:var_mainMod|"[^"]*")(?:\s*\.\.\s*"[^"]*")*)', lua):
    expr = m.group(1)
    parts = re.findall(r'"([^"]*)"|(var_mainMod)', expr)
    text = " ".join(a or "SUPER" for a, b in parts)
    toks = [t.strip() for t in re.split(r"\+", text.replace(" ", "+")) if t.strip()]
    mods = frozenset(MODS[t.upper()] for t in toks if t.upper() in MODS)
    keys = [norm(t) for t in toks if t.upper() not in MODS]
    if keys:
        bound.add((mods, keys[-1]))

bad = []
for combo in sorted(set(re.findall(r"`(Super\+[^`]+)`", doc))):
    toks = combo.split("+")
    mods = frozenset(MODS[t.upper()] for t in toks[:-1] if t.upper() in MODS)
    key = toks[-1]
    if key.startswith("drag"):
        key = "drag"
    keys = GROUPS.get(key.lower(), [norm(key)])
    if not any((mods, k) in bound for k in keys):
        bad.append(combo)

if bad:
    print("KEYBINDS.md lists combos with no bind in config/hypr/modules/keys.lua:", file=sys.stderr)
    for c in bad:
        print(f"  {c}", file=sys.stderr)
    sys.exit(1)
print("check-keybinds: ok")
PY
