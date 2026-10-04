pragma Singleton
import QtQuick
import Quickshell

// Filesystem locations the shell reaches into. Scripts live in the dots repo
// and are reached through the ~/.config/scripts symlink, so every caller
// builds on `scripts` instead of re-deriving $HOME.
Singleton {
    readonly property string home: Quickshell.env("HOME")
    readonly property string scripts: home + "/.config/scripts"
}
