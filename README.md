# Dotfiles for my theme of hyprland (inspired by tailwind)

> [!TIP]
> I recomment symbolic linking the folders to .config (each folder seperatly)

> [!NOTE]
> I made this on Nobara 42 Gnome so there may be some Fedora/Nobara specific commands.

## Dependencies

* `hyprland`
* `kitty`
* `wofi`
* `nautilus`
* `clispe`
* `hyprpaper`
* `hyprpicker`
* `hyprlock`
* `hypridle`
* `swaync`
* `grim`
* `wl-clipboard`
* `swayosd`
* `vim`
* `waybar`
* `firefox`
* `brightnessctl`
* `playerctl`
* `slurp`
* `pavucontrol`
* `polkit-gnome`
* `blueman-applet`
* `network-manager-applet`
* `gnome-calendar`
* `powerprofilesctl`

## Install Dependancies (Nobara 42)

### External repositories

```bash
sudo dnf copr enable markupstart/SwayOSD    # osd
sudo dnf copr enable azandure/clipse        # clipboard
sudo dnf copr enable solopasha/hyprland     # hyprland
```

#### Optional integration of Kitty to Nautilus

```bash
sudo dnf copr enable monkeygold/nautilus-open-any-terminal
sudo dnf install nautilus-open-any-terminal
```

### Install all dependancies

```bash
sudo dnf install hyprland kitty wofi nautilus clipse hyprpaper hyprpicker hyprlock hypridle swaync grim wl-clipboard swayosd vim waybar firefox brightnessctl playerctl slurp pavucontrol polkit-gnome blueman-applet network-manager-applet gnome-calendar powerprofilesctl
```

## Setup

### Wallpapers

Set your own pictures directory in `hypr/wallpaper.sh`

```bash
chmod +x hypr/wallpaper.sh
```

and add all pictures to hyprpaper to preload otherwise it will not work

```bash
vim hypr/hyprpaper.conf
```

### Restart script

This script is for easily restarting startup services

```bash
chmod +x hypr/restart.sh
```

If you modified any of the dependancies you should modify the processes here also:

```bash
vim hypr/restart.sh
```

### Idle timeout

Set your own custom values in `hypr/hypridle.conf`

```bash
vim hypr/hypridle.conf
```

### Keybinds

Set your own preferred keybinds at `hypr/hyprland.conf`

```bash
vim hypr/hyprland.conf
```

### OSD

You will need to run this command for osd to run

```bash
sudo systemctl start --now swayosd-libinput-backend.service
sudo systemctl enable --now swayosd-libinput-backend.service
```
