require("modules.monitors")
require("modules.autostart")
require("modules.general")
require("modules.appearance")
require("modules.input")
require("modules.gestures")
require("modules.keys")
require("modules.rules")

-- HyprMod writes its saved settings here; sourced last so they override the modules above
require("hyprland-gui")

-- The settings app (apps/settings) writes this machine's choices here; loaded
-- after everything so they win. Gitignored, so it is missing on a fresh install.
pcall(require, "settings")
