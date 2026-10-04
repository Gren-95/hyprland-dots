#!/bin/bash
# Regenerate KEYBINDS.md from the live bind table (config/scripts/hypr-binds.sh, which
# resolves the real dispatcher/arg for Lua-registered binds).
#
# The hand-written intro (everything above the first "## " heading) is kept;
# the category tables below it are rewritten. Binds whose action has no label
# below still appear, with the raw dispatcher and arg, under their category.
#
# Usage: docs/gen-keybinds.sh [--stdout]
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out="$root/KEYBINDS.md"

command -v hyprctl >/dev/null || {
    echo "gen-keybinds: hyprctl not found (needs a running Hyprland session)" >&2
    exit 1
}
hyprctl version >/dev/null 2>&1 || {
    echo "gen-keybinds: hyprctl cannot reach Hyprland (is it running?)" >&2
    exit 1
}
command -v python3 >/dev/null || {
    echo "gen-keybinds: python3 not found" >&2
    exit 1
}

binds=$(bash "$root/config/scripts/hypr-binds.sh" 2>/dev/null) || {
    echo "gen-keybinds: config/scripts/hypr-binds.sh failed" >&2
    exit 1
}
[[ -n "$binds" ]] || {
    echo "gen-keybinds: no binds returned" >&2
    exit 1
}

doc=$(
    BINDS="$binds" INTRO_FILE="$out" python3 - <<'PY'
import json, os, re

binds = json.loads(os.environ["BINDS"])
MODS = ((64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"))
KEYS = {"Return": "Enter", "space": "Space", "Escape": "Esc", "bracketleft": "[",
        "bracketright": "]", "left": "arrow", "right": "arrow", "up": "arrow",
        "down": "arrow", "mouse_up": "wheel", "mouse_down": "wheel"}
CATS = ["Apps & system actions", "Quickshell modals", "Capture",
        "Window management", "Workspaces", "Hardware keys", "Personal", "Other"]

APP, QS, CAP, WIN, WS, HW, PERS = CATS[:7]
QS_LABELS = {
    "spotlight": (QS, "App launcher (Spotlight) - `Ctrl+D` hides the highlighted app, `←`/`→` flips to the hidden ones"),
    "unhide": (QS, "Hidden apps - pick one to show again (`↵`)"),
    "clipboard": (QS, "Clipboard history"),
    "notifications": (QS, "Toggle the day panel (calendar + notifications)"),
    "calendar": (QS, "Toggle the day panel (calendar + notifications)"),
    "quickactions": (QS, "Quick actions panel"),
    "bluetooth": (QS, "Bluetooth menu (Network modal, BT tab)"),
    "keybinds": (QS, "Keybinds viewer (live, searchable)"),
    "sysmon": (QS, "System monitor (CPU / RAM / temps / fans / uptime)"),
    "audiopower": (QS, "Audio & Power panel (Sound tab)"),
    "wallpaper": (QS, "Wallpaper deck - hold Super, W deals the next card, release applies"),
    "wallpaper-back": (QS, "Deal the previous card (wallpaper deck)"),
    "wallpaper-apply": (QS, "Apply the card in hand (wallpaper deck)"),
    "wallpaper-cancel": (QS, "Dismiss the wallpaper deck without applying"),
    "overview-cycle": (QS, "Workspace overview (cycle next while held)"),
    "overview-cycle-prev": (QS, "Workspace overview (cycle previous)"),
    "powermenu": (APP, "Power menu (Lock / Suspend / Logout / Reboot / Shutdown)"),
    "screenshot-region": (CAP, "Screenshot region → file + clipboard"),
}
EXEC_LABELS = [  # (substring of arg, category, label)
    ("default-app.sh run terminal", APP, "Open terminal (default app)"),
    ("default-app.sh run filemanager", APP, "Open file manager (default app)"),
    ("default-app.sh run", APP, "Open default app"),
    ("hyprpicker", APP, "Color picker (hyprpicker)"),
    ("hyprlock", APP, "Lock screen (hyprlock + album art)"),
    ("restart.sh", APP, "Restart all userspace services (`config/scripts/restart.sh`)"),
    ("screenshot-ocr.sh", CAP, "Screenshot region → OCR → clipboard text"),
    ("screenrecord.sh", CAP, "Toggle screen recording (gpu-screen-recorder)"),
    ("wallpaper.sh", CAP, "Random wallpaper"),
    ("wayvnc-toggle.sh", CAP, "Toggle WayVNC remote access"),
    ("pkill mpv", PERS, "Stop mpv"),
    ("mpv --no-video", PERS, "mpv shuffle `~/Music`"),
    ("set-volume", HW, "Sink volume ±5%"),
    ("@DEFAULT_AUDIO_SINK@ toggle", HW, "Toggle sink mute"),
    ("@DEFAULT_AUDIO_SOURCE@ toggle", HW, "Toggle source mute"),
    ("playerctl play-pause", HW, "Play / pause (playerctl)"),
    ("playerctl next", HW, "Next track (playerctl)"),
    ("playerctl previous", HW, "Previous track (playerctl)"),
    ("brightnessctl s 5%", HW, "Screen brightness ±5%"),
    ("kbd_backlight s +1", HW, "Keyboard backlight +1 step (does not wrap)"),
    ("kbd_backlight s 1-", HW, "Keyboard backlight -1 step"),
    ("kbd_backlight", HW, "Cycle keyboard backlight (off / half / full)"),
    ("systemctl suspend", HW, "Suspend"),
]


def combo_of(b, collapse):
    mods = [n for bit, n in MODS if b["modmask"] & bit]
    key = b["key"]
    if key.startswith("switch:"):
        return "Lid close" if ":on:" in key else "Lid open"
    if collapse == "digit":
        key = "1..9,0"
    elif key.startswith("mouse:"):
        key = "drag (LMB)" if key == "mouse:272" else "drag (RMB)"
    else:
        key = KEYS.get(key, key if len(key) > 1 and not key.startswith("XF86") else key.upper() if len(key) == 1 else key)
    return "+".join(mods + [key])


def classify(b):
    d, arg, key = b["dispatcher"], b["arg"].strip(), b["key"]
    collapse = None
    if key.startswith("switch:"):
        return HW, ("Lid closed → screen off" if ":on:" in key else "Lid opened → screen on"), None
    if d == "global" and arg.startswith("quickshell:"):
        name = arg.split(":", 1)[1]
        if name in QS_LABELS:
            c, l = QS_LABELS[name]
            return c, l, None
        return QS, f"`{arg}`", None
    if d == "exec":
        for sub, c, l in EXEC_LABELS:
            if sub in arg:
                return c, l, None
        return "Other", f"exec `{arg}`", None
    if d == "killactive":
        return WIN, "Close active window", None
    if d == "togglefloating":
        return WIN, "Toggle floating", None
    if d == "togglesplit":
        return WIN, "Toggle split direction", None
    if d == "pseudo":
        return WIN, "Pseudo-tile", None
    if d == "fullscreen":
        return WIN, "Maximize (fullscreen state 1: keeps bar and gaps)", None
    if d == "movefocus":
        return WIN, "Focus window in direction", None
    if d == "movewindow":
        return WIN, ("Move window" if key.startswith("mouse:") else "Move window in direction"), None
    if d == "resizeactive":
        if key.startswith("mouse:"):
            return WIN, "Resize window", None
        if key in ("KP_Add", "KP_Subtract"):
            return WIN, "Grow / shrink active window", None
        return WIN, "Resize active window", None
    if d == "cyclenext":
        prev = b["modmask"] & 1 or "prev" in arg
        return WIN, ("Cycle windows previous (no overlay)" if prev else "Cycle windows next (no overlay)"), None
    if d == "workspace":
        if key.isdigit():
            return WS, "Switch to workspace N", "digit"
        if key.startswith("mouse_"):
            return WS, ("Cycle workspace across all monitors" if arg.startswith("e") else "Cycle workspace on current monitor"), None
        return WS, "Previous / next workspace on current monitor", None
    if d == "movetoworkspace":
        if key.isdigit():
            return WS, "Move window to workspace N", "digit"
        return WS, "Move window to previous / next workspace on monitor", None
    if d == "focusmonitor":
        return WS, "Focus next monitor", None
    if d == "movecurrentworkspacetomonitor":
        return WS, "Move current workspace to next monitor", None
    return "Other", f"`{d} {arg}`".strip(), None


rows = {c: {} for c in CATS}
for b in binds:
    cat, label, collapse = classify(b)
    combo = combo_of(b, collapse)
    entry = rows[cat].setdefault(label, [])
    if combo not in entry:
        entry.append(combo)

# Same combo-set label order is first-seen; merge labels sharing an identical
# action into one row (already keyed by label).
with open(os.environ["INTRO_FILE"]) as f:
    text = f.read()
intro = text.split("\n## ", 1)[0].rstrip("\n")

out = [intro, ""]
for c in CATS:
    if not rows[c]:
        continue
    out += [f"## {c}", "", "| Key | Action |", "|---|---|"]
    for label, combos in rows[c].items():
        out.append("| " + " / ".join(f"`{x}`" for x in combos) + f" | {label} |")
    out.append("")
print("\n".join(out).rstrip("\n"))
PY
)

if [[ "${1:-}" == "--stdout" ]]; then
    printf '%s\n' "$doc"
else
    printf '%s\n' "$doc" >"$out"
    echo "gen-keybinds: wrote $out"
fi
