function dots --description "Dotfiles symlink status/fix (dotfiles-manager.sh)"
    set -l sub status
    set -q argv[1]; and set sub $argv[1]
    contains -- $sub status fix; or begin
        echo "usage: dots [status|fix] [--dry-run|--force|--verbose]" >&2
        return 1
    end
    bash (path dirname (path resolve $HOME/.config/fish))/dotfiles-manager.sh $sub $argv[2..]
end
