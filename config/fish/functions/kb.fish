function kb --description "Fuzzy-search Hyprland keybinds"
    bash $HOME/.config/scripts/hypr-binds.sh 2>/dev/null | python3 -c '
import json, sys
MODS = ((64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"))
for b in json.load(sys.stdin):
    combo = "+".join([n for bit, n in MODS if b["modmask"] & bit] + [b["key"]])
    action = (b["dispatcher"] + " " + b["arg"]).replace("\n", " ")
    print(f"{combo:<28} {action}")
' | fzf --prompt 'keybind> '
end
