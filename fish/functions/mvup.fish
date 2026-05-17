function mvup --description "Flatten subdirectories into cwd"
    find . -mindepth 2 -type f -print -exec mv {} . \;
end
