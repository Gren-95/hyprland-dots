// Extracts a highlight accent from the current wallpaper (accent-only
// theming — surfaces stay warm-stone). Quantizes the image to 8 colors
// via ImageMagick and picks the most saturated, reasonably bright bucket;
// the result is cached in settingsStore.accentAutoHex so it survives
// restarts. Theme.accentPrimary uses it when the accent is set to "auto".
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: svc

    function refresh() {
        extractProc.running = false;
        extractProc.running = true;
    }
    // Wallpaper swaps take a moment (hyprpaper preload + set); let the
    // new image land before asking hyprpaper what's active.
    function refreshSoon() { soonTimer.restart() }
    Timer { id: soonTimer; interval: 2500; onTriggered: svc.refresh() }

    Component.onCompleted: refresh()

    Process {
        id: extractProc
        command: ["sh", "-c",
            'p=$(hyprctl hyprpaper listactive | head -1 | sed "s/^[^:]*: //"); '
            + '[ -n "$p" ] && magick "$p" -resize 64x64 -colors 8 -depth 8 -format "%c" histogram:info:']
        running: false
        stdout: StdioCollector { onStreamFinished: svc._pick(text) }
    }

    // Score = saturation × value: skips gray and near-black buckets, favors
    // vivid mid-bright colors (a 1×1 average returns muddy brown on photos).
    function _pick(t) {
        let best = "", bestScore = 0;
        for (const l of t.split("\n")) {
            const m = l.match(/\((\d+),(\d+),(\d+)/);
            if (!m) continue;
            const r = +m[1], g = +m[2], b = +m[3];
            const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
            if (mx === 0) continue;
            const sat = (mx - mn) / mx, val = mx / 255;
            if (sat < 0.15 || val < 0.25) continue;
            const score = sat * val;
            if (score > bestScore) {
                bestScore = score;
                best = "#" + [r, g, b].map(c => c.toString(16).padStart(2, "0")).join("");
            }
        }
        if (best !== "") settingsStore.accentAutoHex = best;
    }
}
