pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme

    // Surfaces
    readonly property color bg:        "#1c1917"   // primary background (cards)
    readonly property color bgAlt:     "#292524"   // secondary (popup body)
    readonly property color bgDeep:    "#16130f"   // deepest (inset wells, sliders)
    readonly property color bgHover:   "#231f1d"
    readonly property color bgActive:  "#332e2b"

    // Borders / dividers
    readonly property color border:        "#3a3633"
    readonly property color borderSubtle:  "#2a2624"
    readonly property color borderStrong:  "#44403c"

    // Text
    readonly property color fg:        "#fafaf9"
    readonly property color fgDim:     "#e7e5e4"
    readonly property color fgMuted:   "#d6d3d1"
    readonly property color muted:     "#a8a29e"
    readonly property color mutedDeep: "#78716c"
    readonly property color disabled:  "#57534e"

    // Accents
    readonly property QtObject accent: QtObject {
        // Semantic accents — meaning is stable, do NOT change per wallpaper.
        readonly property color blue:   "#3b82f6"
        readonly property color green:  "#22c55e"
        readonly property color red:    "#ef4444"
        readonly property color orange: "#f97316"
        readonly property color yellow: "#eab308"
        readonly property color purple: "#a78bfa"
        readonly property color pink:   "#f472b6"
        readonly property color teal:   "#34d399"
        readonly property color slate:  "#94a3b8"
        // Material 3 wallpaper-driven roles — written by
        // scripts/accent-from-wallpaper.py and watched by the FileView below.
        // Names match the M3 spec.
        property color primary:            "#3b82f6"   // main accent
        property color primaryContainer:   "#1e3a8a"   // softer accent surface
        property color onPrimary:          "#ffffff"   // text on primary
        property color onPrimaryContainer: "#dbeafe"   // text on primaryContainer
        property color outline:            "#6b7280"   // accent-tinted divider
    }

    // Watch ~/.cache/quickshell/accent.conf and update the wallpaper-driven
    // accent roles. Format: key=value pairs, one per line.
    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/accent.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const valid = ["primary", "primaryContainer", "onPrimary",
                           "onPrimaryContainer", "outline"];
            for (const line of text().split("\n")) {
                const eq = line.indexOf("=");
                if (eq <= 0) continue;
                const key = line.slice(0, eq).trim();
                const val = line.slice(eq + 1).trim();
                if (!/^#[0-9a-fA-F]{6}$/.test(val)) continue;
                if (valid.indexOf(key) >= 0) theme.accent[key] = val;
            }
        }
    }

    // Typography
    readonly property string font:  "FiraCode Nerd Font"
    readonly property QtObject fontSize: QtObject {
        readonly property int xs:   10
        readonly property int sm:   11
        readonly property int base: 13
        readonly property int md:   14
        readonly property int lg:   16
        readonly property int xl:   18
        readonly property int xxl:  22
        readonly property int hero: 28
        readonly property int huge: 32
    }

    // Geometry
    readonly property QtObject spacing: QtObject {
        readonly property int xs: 4
        readonly property int sm: 6
        readonly property int md: 8
        readonly property int lg: 12
        readonly property int xl: 16
        readonly property int xxl: 20
    }
    readonly property QtObject radius: QtObject {
        readonly property int sm: 6
        readonly property int md: 8
        readonly property int lg: 12
        readonly property int xl: 16
    }
    readonly property QtObject height: QtObject {
        readonly property int chip:    22    // tiny pill (BtToggle, badges)
        readonly property int control: 28    // toggle pills, tab pills
        readonly property int row:     40    // list rows (notifications, devices, networks)
        readonly property int rowSm:   36    // dense rows (peers)
        readonly property int tile:    78    // QuickActions tile
        readonly property int card:    56    // ProfileSelector cards
    }

    // Animation
    readonly property QtObject duration: QtObject {
        readonly property int fast:   120   // micro: hover/colour ticks
        readonly property int normal: 180   // standard: popup open/close, scale snaps
        readonly property int slow:   240   // deliberate: workspace switches, big morphs
    }
    readonly property QtObject easing: QtObject {
        readonly property int standard:    Easing.OutCubic      // most things
        readonly property int emphasized:  Easing.OutBack       // playful pops (chips)
        readonly property int decelerated: Easing.OutQuad       // long, gentle settles
    }
}
