function gd --description "Remove the current git worktree and its branch (asks first)"
    set -l git_dir (git rev-parse --absolute-git-dir 2>/dev/null)
    or begin
        echo "gd: not in a git repository" >&2
        return 1
    end
    if test "$git_dir" = (git rev-parse --path-format=absolute --git-common-dir)
        echo "gd: this is the main worktree, nothing to remove" >&2
        return 1
    end

    set -l worktree (git rev-parse --show-toplevel)
    set -l branch (git branch --show-current)
    set -l main (git worktree list --porcelain | string replace -rf '^worktree (.*)' '$1' | head -n 1)
    set -l dirty ""
    test -n "$(git status --porcelain)"; and set dirty " It has uncommitted changes."

    read -l -P "Remove worktree $worktree and delete branch '$branch'?$dirty [y/N] " answer
    string match -qir '^y(es)?$' -- $answer; or return 1

    cd $main; or return 1
    git worktree remove --force $worktree; or return 1
    if test -n "$branch"
        git branch -D $branch
    end
end
