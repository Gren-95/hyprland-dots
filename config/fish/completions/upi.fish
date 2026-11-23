# Completions for upi (apps/upi): its steps and options.
set -l steps dnf plugins firmware flatpak appimages npm uv bun immich-rs fisher vscode tldr dots
complete -c upi -f
complete -c upi -n "not __fish_seen_argument -l last -l list -l help" -a "$steps" -d step
complete -c upi -s c -l check -d "Only list what would update"
complete -c upi -s y -l yes -d "Do not ask before updating"
complete -c upi -l no-snapshot -d "Skip the Timeshift snapshot"
complete -c upi -l skip -x -a "$steps" -d "Every step except these"
complete -c upi -l last -d "Show how the last run went"
complete -c upi -l list -d "List the steps"
complete -c upi -s h -l help -d "Show help"
