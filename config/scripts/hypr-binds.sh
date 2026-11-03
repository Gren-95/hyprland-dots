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
set -euo pipefail

exec python3 - "$@" <<'PY'
import json, os, re, subprocess, sys, pathlib

HYPR = pathlib.Path.home() / ".config/hypr"
MODS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "ALT": 8,
        "MOD2": 16, "MOD3": 32, "SUPER": 64, "MOD5": 128}


def lua_sources():
    return sorted(HYPR.rglob("*.lua"))


def var_map(texts):
    """Collect `var_*` assignments, including `..` concatenations that use a
    `local x = os.getenv("HOME") .. "..."` prefix."""
    home = os.environ.get("HOME", "")
    out = {}
    for t in texts:
        for m in re.finditer(r'^\s*local\s+(\w+)\s*=\s*os\.getenv\("HOME"\)\s*\.\.\s*"([^"]*)"', t, re.M):
            out[m.group(1)] = home + m.group(2)
        for m in re.finditer(r'^\s*(var_\w+)\s*=\s*(.+)$', t, re.M):
            out[m.group(1)] = resolve_str(m.group(2), out)
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
        if "monitor" in kv:
            return "focusmonitor", kv["monitor"]
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
            lua = re.sub(r"\bvar_\w+\b",
                         lambda v: json.dumps(vars_[v.group(0)]) if v.group(0) in vars_ else v.group(0),
                         act)
            index[combo_key(combo)] = (*to_dispatcher(path, inner_args, vars_), lua)
    return index


EXEC_TEXT = [
    (r"default-app\.sh run terminal", "Open a terminal"),
    (r"default-app\.sh run filemanager", "Open the file manager"),
    (r"hyprlock", "Lock the screen"),
    (r"hyprpicker", "Pick a color from the screen and copy it"),
    (r"wallpaper\.sh", "Switch to a random wallpaper"),
    (r"screenshot-ocr\.sh", "Screenshot a region and copy the text in it (OCR)"),
    (r"screenshot-window\.sh", "Screenshot the focused window"),
    (r"screenrecord\.sh", "Start or stop screen recording"),
    (r"wayvnc-toggle\.sh", "Turn remote desktop (VNC) on or off"),
    (r"restart\.sh", "Restart the shell and background services"),
    (r"mpv --no-video", "Play the music folder on shuffle"),
    (r"pkill mpv", "Stop the music"),
    (r"scratchpad\.sh", "Show or hide the drop-down scratchpad terminal"),
    (r"night\.sh toggle", "Turn the night light on or off"),
    (r"idle-inhibit-toggle\.sh", "Stay Awake: block screen lock and sleep until toggled off"),
    (r"gamemode\.sh toggle", "Turn game mode on or off"),
    (r"set-volume .*5%\+", "Raise the volume"),
    (r"set-volume .*5%-", "Lower the volume"),
    (r"set-mute @DEFAULT_AUDIO_SINK@", "Mute or unmute the speakers"),
    (r"set-mute @DEFAULT_AUDIO_SOURCE@", "Mute or unmute the microphone"),
    (r"brightnessctl s 5%\+", "Raise the screen brightness"),
    (r"brightnessctl s 5%-", "Lower the screen brightness"),
    (r"kbd_backlight s \+1", "Keyboard backlight: next level"),
    (r"kbd_backlight s 1-", "Keyboard backlight: previous level"),
    (r"kbd_backlight g", "Cycle the keyboard backlight level"),
    (r"playerctl next", "Next track"),
    (r"playerctl previous", "Previous track"),
    (r"playerctl play-pause", "Play or pause the music"),
    (r"systemctl suspend", "Suspend the computer"),
    (r"dpms.*\bon\b", "Lid opened: wake the display and restore brightness"),
]

GLOBAL_TEXT = {
    "spotlight": "Open the app launcher",
    "unhide": "Manage hidden apps in the launcher",
    "notifications": "Open the notification center",
    "clipboard": "Open the clipboard history",
    "screenshot-region": "Screenshot a region you select with the mouse",
    "powermenu": "Open the power menu (sleep, reboot, shut down)",
    "keybinds": "Show this keybind list",
    "sysmon": "Open the system monitor",
    "quickactions": "Open Quick Actions (toggles and shortcuts)",
    "audiopower": "Open sound, battery and power profile controls",
    "calendar": "Open the calendar",
    "wallpaper": "Browse wallpapers (keep Super held, release to apply)",
    "wallpaper-apply": "Apply the wallpaper you are browsing",
    "wallpaper-cancel": "Close the wallpaper browser without changing it",
    "wallpaper-back": "Go back one wallpaper while browsing",
    "bluetooth": "Open Bluetooth devices",
    "overview-cycle": "Workspace overview: go to the next workspace",
    "overview-cycle-prev": "Workspace overview: go to the previous workspace",
}

WORKSPACE_STEPS = {"m-1": "the previous workspace on this monitor", "m+1": "the next workspace on this monitor",
                   "e-1": "the previous open workspace", "e+1": "the next open workspace"}


def describe(b):
    """Plain-language text for a bind, from its resolved dispatcher and arg."""
    d, arg, key = b.get("dispatcher", ""), str(b.get("arg", "")), str(b.get("key", ""))
    if d == "exec":
        for pat, text in EXEC_TEXT:
            if re.search(pat, arg):
                return text
        return ""
    if d == "global":
        return GLOBAL_TEXT.get(arg.split(":", 1)[-1], "")
    if d == "killactive":
        return "Close the focused window"
    if d == "togglefloating":
        return "Float or tile the focused window"
    if d == "pseudo":
        return "Toggle pseudo-tiling for the focused window"
    if d == "togglesplit":
        return "Flip the split direction of the focused window"
    if d == "fullscreen":
        return "Toggle fullscreen for the focused window"
    if d == "cyclenext":
        return "Cycle focus to the next window"
    if d == "movefocus":
        return f"Move focus to the window on the {arg}"
    if d == "movewindow":
        if key == "mouse:272":
            return "Drag to move a window"
        return f"Move the focused window {arg}"
    if d == "resizeactive":
        if key == "mouse:273":
            return "Drag to resize a window"
        x, y = (arg.split() + ["0", "0"])[:2]
        grow = (int(x) + int(y)) > 0
        return ("Grow" if grow else "Shrink") + " the focused window"
    if d == "workspace":
        if key.startswith("mouse_"):
            return "Scroll to switch to " + WORKSPACE_STEPS.get(arg, "another workspace")
        return "Switch to " + (WORKSPACE_STEPS[arg] if arg in WORKSPACE_STEPS else f"workspace {arg}")
    if d == "movetoworkspace":
        return "Send the focused window to " + (WORKSPACE_STEPS[arg] if arg in WORKSPACE_STEPS else f"workspace {arg}")
    if d == "focusmonitor":
        return "Focus the next monitor"
    if d == "movecurrentworkspacetomonitor":
        return "Send this workspace to the next monitor"
    if d == "dpms":
        return "Lid closed: turn the built-in display off"
    return ""


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
        # Hyprland 0.55 and 0.56 report "__lua"; 0.57 reports "HL.Dispatcher(name)".
        disp = b.get("dispatcher", "")
        if disp != "__lua" and not disp.startswith("HL.Dispatcher("):
            continue
        found = index.get((b.get("modmask", 0), str(b.get("key", "")).lower()))
        if found:
            b["dispatcher"], b["arg"], b["lua"] = found
            hits += 1
    for b in binds:
        if not b.get("description"):
            b["description"] = describe(b)
    print(json.dumps(binds))
    print(f"hypr-binds: resolved {hits}/{len(binds)} binds", file=sys.stderr)
    return 0


sys.exit(main())
PY
