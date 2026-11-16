function open --description "Open a file or URL in its default app, detached and silent"
    xdg-open $argv >/dev/null 2>&1 &
    disown
end
