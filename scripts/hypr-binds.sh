#!/bin/bash
# Emit `hyprctl binds -j`, but with the real dispatcher/arg filled in.
#
# Hyprland's Lua config registers every bind as a Lua closure, so `hyprctl
# binds -j` reports dispatcher="__lua" and arg="<callback index>" for all of
# them — useless for the Quickshell keybind viewer, which groups and labels
# binds by dispatcher. This re-derives the real action by parsing the Lua
# source and merges it back in, keyed on (modmask, key).
#
# Binds it can't resolve are passed through untouched.
exec python3 - "$@" <<'PY'
import json, re, subprocess, sys, pathlib

HYPR = pathlib.Path.home() / ".config/hypr"
MODS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "ALT": 8,
        "MOD2": 16, "MOD3": 32, "SUPER": 64, "MOD5": 128}


def lua_sources():
    return sorted(HYPR.rglob("*.lua"))


def var_map(texts):
    out = {}
    for t in texts:
        for m in re.finditer(r'^\s*(var_\w+)\s*=\s*"([^"]*)"', t, re.M):
            out[m.group(1)] = m.group(2)
    return out


def split_top(s):
    """Split on top-level commas, respecting quotes and nesting."""
    parts, depth, inq, cur = [], 0, False, ""
    for c in s:
        if c == '"':
            inq = not inq
        if not inq:
            if c in "({[":
                depth += 1
            elif c in ")}]":
                depth -= 1
            elif c == "," and depth == 0:
                parts.append(cur); cur = ""; continue
        cur += c
    if cur.strip():
        parts.append(cur)
    return [p.strip() for p in parts]


def balanced(text, start):
    """Return the substring inside the parens opened at `start`."""
    depth, inq, i = 0, False, start
    while i < len(text):
        c = text[i]
        if c == '"':
            inq = not inq
        elif not inq:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return text[start + 1:i]
        i += 1
    return None


def resolve_str(expr, vars_):
    """Evaluate a Lua string expression: literals and var_ joined by `..`."""
    out = ""
    for tok in expr.split(".."):
        tok = tok.strip()
        m = re.fullmatch(r'"([^"]*)"', tok)
        if m:
            out += m.group(1)
        elif tok in vars_:
            out += vars_[tok]
        else:
            out += tok
    return out.strip()


def table_kv(expr):
    """Parse `{ a = 1, b = "x" }` into a dict of strings."""
    m = re.search(r"\{(.*)\}", expr, re.S)
    if not m:
        return {}
    kv = {}
    for part in split_top(m.group(1)):
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        kv[k.strip()] = v.strip().strip('"')
    return kv


def to_dispatcher(path, args, vars_):
    """Map an hl.dsp.* call onto the classic Hyprland dispatcher/arg pair,
    which is what the viewer's category rules already understand."""
    kv = table_kv(args)
    bare = args.strip().strip('"')
    if path == "exec_cmd":
        return "exec", resolve_str(args, vars_)
    if path == "global":
        return "global", bare
    if path == "window.close":
        return "killactive", ""
    if path == "window.pseudo":
        return "pseudo", ""
    if path == "window.float":
        return "togglefloating", ""
    if path == "window.drag":
        return "movewindow", ""
    if path == "window.cycle_next":
        return "cyclenext", ""
    if path == "window.fullscreen_state":
        return "fullscreen", ""
    if path == "workspace.move":
        return "movecurrentworkspacetomonitor", kv.get("monitor", "")
    if path == "layout":
        return (bare or "layoutmsg"), ""
    if path == "dpms":
        return "dpms", bare
    if path == "focus":
        if "workspace" in kv:
            return "workspace", kv["workspace"]
        if "direction" in kv:
            return "movefocus", kv["direction"]
    if path == "window.move":
        if "workspace" in kv:
            return "movetoworkspace", kv["workspace"]
        if "direction" in kv:
            return "movewindow", kv["direction"]
    if path == "window.resize":
        return "resizeactive", f"{kv.get('x', 0)} {kv.get('y', 0)}"
    return path.split(".")[-1], bare


def combo_key(combo):
    """'SUPER + CTRL + left' -> (modmask, 'left')"""
    mask, key = 0, ""
    for tok in combo.split("+"):
        tok = tok.strip()
        if not tok:
            continue
        if tok.upper() in MODS:
            mask |= MODS[tok.upper()]
        else:
            key = tok
    return mask, key.lower()


def build_index():
    texts = [p.read_text(errors="replace") for p in lua_sources()]
    vars_ = var_map(texts)
    index = {}
    for t in texts:
        for m in re.finditer(r"hl\.bind[a-z]*\(", t):
            inner = balanced(t, m.end() - 1)
            if inner is None:
                continue
            args = split_top(inner)
            if len(args) < 2:
                continue
            combo = resolve_str(args[0], vars_)
            act = args[1].strip()
            am = re.match(r"hl\.dsp\.([a-z_.]+)\s*\(", act)
            if not am:
                continue
            path = am.group(1).rstrip(".")
            inner_args = balanced(act, am.end() - 1) or ""
            index[combo_key(combo)] = to_dispatcher(path, inner_args, vars_)
    return index


def main():
    try:
        raw = subprocess.run(["hyprctl", "binds", "-j"],
                             capture_output=True, text=True, check=True).stdout
        binds = json.loads(raw)
    except Exception as e:
        print(f"[]", file=sys.stdout)
        print(f"hypr-binds: cannot read hyprctl binds: {e}", file=sys.stderr)
        return 1

    index = build_index()
    hits = 0
    for b in binds:
        if b.get("dispatcher") != "__lua":
            continue
        found = index.get((b.get("modmask", 0), str(b.get("key", "")).lower()))
        if found:
            b["dispatcher"], b["arg"] = found
            hits += 1
    print(json.dumps(binds))
    print(f"hypr-binds: resolved {hits}/{len(binds)} binds", file=sys.stderr)
    return 0


sys.exit(main())
PY
