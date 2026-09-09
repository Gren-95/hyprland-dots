# Stone - ranger colorscheme matching the palette in quickshell/Theme.qml.
#
# ranger draws through curses, so colours are xterm-256 indices rather than
# hex. Each constant below is the closest index to its Theme.qml counterpart;
# the hex in the comment is the palette colour it stands in for.
#
# Subclasses Default and overrides only the contexts that carry colour, so
# ranger's own layout and attribute logic (bold, reverse, marked rows) is
# left alone.

from __future__ import (absolute_import, division, print_function)

from ranger.colorschemes.default import Default
from ranger.gui.color import default

FG = 252          # d6d3d1  fgMuted   - regular files
FG_BRIGHT = 255   # fafaf9  fg        - titles, selection
MUTED = 247       # a8a29e  muted     - info columns
MUTED_DEEP = 243  # 78716c  mutedDeep - borders, dimmed text
ACCENT = 75       # 60a5fa  blueBright - directories
ACCENT_DEEP = 33  # 3b82f6  blue      - titlebar, active tab
GREEN = 41        # 22c55e  green     - executables, ok
TEAL = 79         # 34d399  teal      - links
YELLOW = 178      # eab308  yellow    - marked, warnings
ORANGE = 208      # f97316  orange    - staged
RED = 203         # ef4444  red       - errors, danger
PURPLE = 141      # a78bfa  purple    - sockets, devices
SLATE = 109       # 94a3b8  slate     - untracked


class Scheme(Default):
    progress_bar_color = ACCENT_DEEP

    def use(self, context):  # noqa: C901
        fg, bg, attr = Default.use(self, context)

        if context.in_browser:
            if context.directory:
                fg = ACCENT
            elif context.executable and not any(
                    (context.media, context.container, context.fifo,
                     context.socket, context.device)):
                fg = GREEN
            elif context.link:
                fg = TEAL if context.good else RED
            elif context.socket or context.fifo or context.device:
                fg = PURPLE
            elif context.media:
                fg = PURPLE
            elif context.container:
                fg = ORANGE
            else:
                fg = FG

            if context.marked:
                fg = YELLOW
            if context.empty or context.error:
                fg = RED
            if context.inactive_pane:
                fg = MUTED_DEEP

        if context.in_titlebar:
            if context.hostname:
                fg = RED if context.bad else ACCENT_DEEP
            elif context.directory:
                fg = ACCENT
            elif context.tab:
                fg = FG_BRIGHT if context.good else MUTED
            elif context.link:
                fg = TEAL

        if context.in_statusbar:
            if context.permissions:
                fg = GREEN if context.good else RED
            elif context.message:
                fg = RED if context.bad else FG
            elif context.loaded:
                bg = self.progress_bar_color

        if context.border:
            fg = MUTED_DEEP
            bg = default

        # Version control column, mirroring the shell's git semantics:
        # green = clean, yellow = changed, orange = staged, red = conflict.
        if context.vcsfile and not context.selected:
            if context.vcsconflict:
                fg = RED
            elif context.vcsuntracked:
                fg = SLATE
            elif context.vcschanged:
                fg = YELLOW
            elif context.vcsstaged:
                fg = ORANGE
            elif context.vcssync:
                fg = GREEN
            elif context.vcsignored:
                fg = MUTED_DEEP

        if context.vcsremote and not context.selected:
            if context.vcssync or context.vcsnone:
                fg = GREEN
            elif context.vcsbehind:
                fg = YELLOW
            elif context.vcsahead:
                fg = ACCENT
            elif context.vcsdiverged:
                fg = RED
            elif context.vcsunknown:
                fg = MUTED_DEEP

        return fg, bg, attr
