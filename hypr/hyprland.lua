-- Hyprland Lua config entry point. Hyprland v0.55 looks for this file
-- first (~/.config/hypr/hyprland.lua); if absent, falls back to
-- hyprland.conf (kept around as a backup in the same directory).

-- Make modules/ require()-able.
package.path = package.path .. ";" .. os.getenv("HOME") .. "/.config/hypr/?.lua"

require("modules.monitors")
require("modules.autostart")
require("modules.general")
require("modules.appearance")
require("modules.input")
require("modules.gestures")
require("modules.keys")
require("modules.rules")
