// Single-open policy for bar flyouts. Every BarFlyout registers here when it
// opens; opening one closes whatever else was open (close-then-open, same
// ordering the nav ring already used, so focus grabs never overlap).

import QtQuick
import Quickshell

Scope {
    id: mgr

    // The flyout currently open, or null. Surfaces must expose a `close()`
    // function that routes through their consumer's state (via dismissed()).
    property var current: null

    function opened(surface) {
        if (current && current !== surface) current.close();
        current = surface;
    }

    function closed(surface) {
        if (current === surface) current = null;
    }

    function closeAll() {
        if (current) current.close();
        current = null;
    }
}
