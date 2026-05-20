-- Environment + startup commands.

hl.env("XCURSOR_SIZE",        "24")
hl.env("HYPRCURSOR_SIZE",     "24")
hl.env("QT_QPA_PLATFORMTHEME","hyprqt6engine")
hl.env("QML_IMPORT_PATH",     "/home/ghost/.local/lib64/qt6/qml")
-- Silence Quickshell's per-desktop-entry parse warnings — they come from
-- system .desktop files we don't ship (swappy uses non-standard `\$` escapes
-- in Exec=) and can't fix. Keeps the qslog readable.
hl.env("QT_LOGGING_RULES",    "quickshell.desktopentry.warning=false")

-- One-shot startup. restart.sh respawns hyprpaper, hypridle, polkit, qs, etc.
-- Immich + Jellyfin sync are scheduled via cron, toggleable from Quick Actions.
-- See scripts/sync-toggle.sh.
hl.on("hyprland.start", function()
    hl.exec_cmd("bash ~/.config/scripts/restart.sh")
    hl.exec_cmd("bash ~/.config/scripts/power-auto.sh")
end)
