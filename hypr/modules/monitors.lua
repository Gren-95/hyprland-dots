-- Monitors + workspace-to-monitor assignments.

-- Built-in laptop display, others auto-detected.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1 })
hl.monitor({ output = "",      mode = "preferred", position = "auto", scale = 1 })
-- hl.monitor({ output = "DP-4",  mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Laptop lid switch handler.
hl.bind(", switch:on:Lid Switch",  hl.dsp.exec_cmd('hyprctl keyword monitor "eDP-1, disable"'),                { locked = true })
hl.bind(", switch:off:Lid Switch", hl.dsp.exec_cmd('hyprctl keyword monitor "eDP-1, preferred, 0x0, 1"'),     { locked = true })

-- Workspace assignments: 1–5 on the laptop, 6–10 on DP-4.
-- WorkspaceRuleSpec.workspace is typed as string, not int.
hl.workspace_rule({ workspace = "1", monitor = "eDP-1", default = true })
for i = 2, 5 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1" })
end
for i = 6, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "DP-4" })
end
