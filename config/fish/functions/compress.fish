function compress --description "Create a .tar.gz archive of a file or directory"
    if test (count $argv) -ne 1
        echo "Usage: compress <file-or-directory>" >&2
        return 1
    end
    set -l target (string trim --right --chars=/ -- $argv[1])
    tar -czf "$target.tar.gz" $target
end
