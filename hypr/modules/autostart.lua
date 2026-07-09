hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "rose-pine-hyprcursor")
hl.env("XCURSOR_THEME", "BreezeX-RosePine-Linux")
hl.env("QT_QPA_PLATFORMTHEME", "hyprqt6engine")
hl.env("QML_IMPORT_PATH", "/home/ghost/.local/lib64/qt6/qml")

-- Silence Quickshell's per-desktop-entry parse warnings — they come from

-- system .desktop files we don't ship (swappy uses non-standard `\$` escapes

-- in Exec=) and can't fix. Keeps the qslog readable.
hl.env("QT_LOGGING_RULES", "quickshell.desktopentry.warning=false")

hl.on("hyprland.start", function()
    hl.exec_cmd("bash ~/.config/scripts/restart.sh")
end)

-- Immich + Jellyfin sync are scheduled via cron, toggleable from Quick Actions.

-- See scripts/sync-toggle.sh.

-- Auto-switch power profile on AC plug/unplug.
hl.on("hyprland.start", function()
    hl.exec_cmd("bash ~/.config/scripts/power-auto.sh")
end)

-- Keep Nautilus resident so file-manager windows open in ~0.2s instead of ~2s

-- (cold D-Bus activation of the GTK4 app is the slow part; the service isn't

-- GNOME-session-managed on Hyprland, so nothing keeps it alive otherwise).
hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/bin/nautilus --gapplication-service")
end)
