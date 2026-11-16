function ga --description "Create a git worktree and branch next to this repo and cd into it"
    if test (count $argv) -ne 1
        echo "Usage: ga <branch>" >&2
        return 1
    end
    set -l branch $argv[1]
    set -l root (git rev-parse --show-toplevel); or return 1
    # A branch like feature/x must not turn into nested directories.
    set -l path "$root--"(string replace -a / - $branch)
    git worktree add -b $branch $path; and cd $path
end
