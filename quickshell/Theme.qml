pragma Singleton
import QtQuick
import Quickshell

Singleton {
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
}
