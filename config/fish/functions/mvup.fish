function mvup --description "Flatten subdirectories into cwd (never overwrites)"
    find . -mindepth 2 -type f -print -exec mv -n {} . \;
end
