pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // ===== User-tunable knobs =====
    // Pushed in from shell.qml via Binding elements (a singleton can't
    // resolve the settingsStore id itself). Defaults match the classic look.
    property real fontScale: 1.0
    property string fontFamily: "FiraCode Nerd Font"
    property string accentPrimaryName: "blue"
    // The highlight/selection accent — used for selected rows, focused
    // cards, active pills. Semantic accents (red=danger, green=ok, …) stay.
    readonly property color accentPrimary: {
        switch (accentPrimaryName) {
        case "green":  return accent.green;
        case "red":    return accent.red;
        case "orange": return accent.orange;
        case "yellow": return accent.yellow;
        case "purple": return accent.purple;
        case "pink":   return accent.pink;
        case "teal":   return accent.teal;
        case "slate":  return accent.slate;
        }
        return accent.blue;
    }

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
        readonly property color blue:   "#3b82f6"
        readonly property color green:  "#22c55e"
        readonly property color red:    "#ef4444"
        readonly property color orange: "#f97316"
        readonly property color yellow: "#eab308"
        readonly property color purple: "#a78bfa"
        readonly property color pink:   "#f472b6"
        readonly property color teal:   "#34d399"
        readonly property color slate:  "#94a3b8"
    }

    // Typography (scaled by the user's fontScale)
    readonly property string font: fontFamily
    readonly property QtObject fontSize: QtObject {
        readonly property int xs:   Math.round(10 * fontScale)
        readonly property int sm:   Math.round(11 * fontScale)
        readonly property int base: Math.round(13 * fontScale)
        readonly property int md:   Math.round(14 * fontScale)
        readonly property int lg:   Math.round(16 * fontScale)
        readonly property int xl:   Math.round(18 * fontScale)
        readonly property int xxl:  Math.round(22 * fontScale)
        readonly property int hero: Math.round(28 * fontScale)
        readonly property int huge: Math.round(32 * fontScale)
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
