function upi --description "Update everything: backup, dnf, flatpak, fisher"
    echo "Updating system..."
    util system backup
    and sudo dnf update
    and flatpak update
    and sudo dnf autoremove
    and flatpak remove --unused
    and fisher update
end
