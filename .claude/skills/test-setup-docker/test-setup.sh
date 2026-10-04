#!/bin/bash
# Runs INSIDE the Fedora container as root: create a sudo user, copy the repo,
# run dots.sh setup --yes as that user, then show what landed.
set -e
dnf install -y -q sudo git dnf-plugins-core >/dev/null
useradd -m tester
user_home=$(getent passwd tester | cut -d: -f6)
echo 'tester ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/tester
cp -r /repo "$user_home/dots"
chown -R tester:tester "$user_home/dots"
su - tester -c 'cd ~/dots && ./dots.sh setup --yes' 2>&1 || echo "=== dots.sh setup failed ==="
su - tester -c 'ls -l ~/.local/share/thumbnailers ~/.config; command -v unzip magick'
