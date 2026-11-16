function mvup --description "Flatten subdirectories into cwd (never overwrites, asks first)"
    # Hidden files and directories are left alone: inside a git repository
    # flattening .git would break it.
    set -l files (find . -mindepth 2 -type f -not -path '*/.*')
    if test (count $files) -eq 0
        echo "mvup: nothing to move"
        return 0
    end

    printf '%s\n' $files
    read -l -P "Move these "(count $files)" files into "(pwd)"? [y/N] " answer
    if not string match -qi y -- $answer
        echo "mvup: cancelled"
        return 1
    end

    for f in $files
        mv -n -- $f .
    end
end
