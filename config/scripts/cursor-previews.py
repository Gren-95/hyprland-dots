#!/usr/bin/python3
"""List the installed cursor themes with preview images of a few cursors.

Usage: cursor-previews.py

Prints a JSON array, sorted by name:
  [{"id", "name", "comment", "kind": "xcursor" | "hyprcursor", "samples": [file, ...]}]

Called by `cursor-theme.sh list` for the Cursors tab of the Icons & cursors
popup (quickshell/IconThemes.qml). XCursor themes are directories with a
`cursors/` folder of Xcursor files; Hyprcursor themes have a `manifest.hl`
and zipped `.hlc` cursors. Previews are written to
$XDG_CACHE_HOME/dots/cursor-previews/<theme>/ (PNG from Xcursor files, the
packed SVG or PNG from Hyprcursor ones) and redone when the source is newer.
"""
import json
import os
import struct
import sys
import zipfile

from PIL import Image

HOME = os.path.expanduser("~")
THEME_DIRS = [os.path.join(HOME, ".local/share/icons"), os.path.join(HOME, ".icons"), "/usr/share/icons"]
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.join(HOME, ".cache")), "dots", "cursor-previews")
# One sample per slot; the first name a theme has wins.
SAMPLE_SLOTS = [
    ["left_ptr", "default", "arrow"],
    ["hand2", "pointer", "hand1"],
    ["xterm", "text"],
    ["watch", "wait", "left_ptr_watch", "progress"],
    ["cross", "crosshair"],
    ["fleur", "move", "all-scroll"],
    ["sb_h_double_arrow", "ew-resize", "col-resize"],
    ["crossed_circle", "not-allowed", "dnd_no_drop"],
]
PREVIEW_SIZE = 48
XCURSOR_IMAGE = 0xFFFD0002


def index_key(theme_dir, key):
    """Value of key in the [Icon Theme] section of index.theme, or ""."""
    path = os.path.join(theme_dir, "index.theme")
    inside = False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.strip()
                if line.startswith("["):
                    inside = line == "[Icon Theme]"
                elif inside and line.startswith(key + "="):
                    return line.split("=", 1)[1]
    except OSError:
        pass
    return ""


def manifest_key(theme_dir, key):
    """Value of `key = value` in a Hyprcursor manifest.hl, or ""."""
    try:
        with open(os.path.join(theme_dir, "manifest.hl"), encoding="utf-8", errors="replace") as f:
            for line in f:
                name, sep, value = line.partition("=")
                if sep and name.strip() == key:
                    return value.strip()
    except OSError:
        pass
    return ""


def fresh(out, source):
    return os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(source)


def xcursor_to_png(source, out):
    """Write the first frame of the Xcursor image whose nominal size is
    nearest PREVIEW_SIZE as a PNG."""
    with open(source, "rb") as f:
        data = f.read()
    if data[:4] != b"Xcur":
        raise ValueError("not an Xcursor file")
    ntoc, = struct.unpack_from("<I", data, 12)
    images = []
    for i in range(ntoc):
        kind, nominal, pos = struct.unpack_from("<III", data, 16 + i * 12)
        if kind == XCURSOR_IMAGE:
            images.append((abs(nominal - PREVIEW_SIZE), pos))
    if not images:
        raise ValueError("no images")
    _, pos = min(images)
    width, height = struct.unpack_from("<II", data, pos + 16)
    pixels = data[pos + 36:pos + 36 + width * height * 4]
    # Xcursor pixels are premultiplied ARGB, stored little-endian (B G R A).
    img = Image.frombytes("RGBa", (width, height), pixels, "raw", "BGRa").convert("RGBA")
    img.save(out, "PNG")


def hyprcursor_extract(source, out_base):
    """Extract the first image of a .hlc archive; return its path."""
    with zipfile.ZipFile(source) as z:
        for name in z.namelist():
            ext = os.path.splitext(name)[1].lower()
            if ext in (".svg", ".png") and "/" not in name:
                out = out_base + ext
                if not fresh(out, source):
                    with open(out, "wb") as f:
                        f.write(z.read(name))
                return out
    raise ValueError("no image in archive")


def samples(theme_id, theme_dir, kind):
    out_dir = os.path.join(CACHE, theme_id)
    os.makedirs(out_dir, exist_ok=True)
    files = []
    for slot, names in enumerate(SAMPLE_SLOTS):
        for name in names:
            if kind == "xcursor":
                source = os.path.realpath(os.path.join(theme_dir, "cursors", name))
            else:
                cursors = manifest_key(theme_dir, "cursors_directory") or "hyprcursors"
                source = os.path.join(theme_dir, cursors, name + ".hlc")
            if not os.path.isfile(source):
                continue
            out_base = os.path.join(out_dir, str(slot))
            try:
                if kind == "xcursor":
                    out = out_base + ".png"
                    if not fresh(out, source):
                        xcursor_to_png(source, out)
                else:
                    out = hyprcursor_extract(source, out_base)
            except (OSError, ValueError, struct.error, zipfile.BadZipFile) as e:
                print(f"cursor-previews: {source}: {e}", file=sys.stderr)
                continue
            files.append(out)
            break
    return files


def themes():
    seen = set()
    for base in THEME_DIRS:
        try:
            entries = sorted(os.listdir(base))
        except OSError:
            continue
        for theme_id in entries:
            theme_dir = os.path.join(base, theme_id)
            if theme_id in seen:
                continue
            if os.path.isfile(os.path.join(theme_dir, "manifest.hl")):
                kind = "hyprcursor"
                name = manifest_key(theme_dir, "name") or theme_id
                comment = manifest_key(theme_dir, "description")
            elif os.path.isdir(os.path.join(theme_dir, "cursors")):
                kind = "xcursor"
                name = index_key(theme_dir, "Name") or theme_id
                comment = index_key(theme_dir, "Comment")
            else:
                continue
            files = samples(theme_id, theme_dir, kind)
            if not files:
                continue
            seen.add(theme_id)
            yield {"id": theme_id, "name": name, "comment": comment, "kind": kind, "samples": files}


def main():
    result = sorted(themes(), key=lambda t: t["name"].lower())
    json.dump(result, sys.stdout)
    print()


if __name__ == "__main__":
    main()
