# Dotfiles for my theme of hyprland (inspired by tailwind)

> [!TIP]
> I recommend symbolic linking the folders to .config (each folder separately)

> [!NOTE]
> I made this on Nobara 42 Gnome so there may be some Fedora/Nobara specific commands.

## Dependencies

* `hyprland`
* `kitty`
* `wofi`
* `wlogout`
* `nautilus`
* `clipse`
* `cliphist`
* `hyprpaper`
* `hyprpicker`
* `hyprlock`
* `hypridle`
* `swaync`
* `grim`
* `slurp`
* `swappy`
* `wl-clipboard`
* `swayosd`
* `neovim`
* `waybar`
* `firefox`
* `brightnessctl`
* `playerctl`
* `pavucontrol`
* `polkit-gnome`
* `network-manager-applet`
* `gnome-calendar`
* `gnome-keyring`
* `powerprofilesctl`
* `io.github.ebonjaeger.bluejay`

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
sudo dnf install hyprland kitty wofi wlogout nautilus clipse cliphist hyprpaper hyprpicker hyprlock hypridle swaync grim slurp swappy wl-clipboard swayosd neovim waybar firefox brightnessctl playerctl pavucontrol polkit-gnome network-manager-applet gnome-calendar gnome-keyring powerprofilesctl hyprland-plugin-hyprtrails hyprland-plugin-hyprexpo
```
> **Note:** For Bluetooth app Bluejay, install with:
> ```bash
> flatpak install flathub io.github.ebonjaeger.bluejay
> ```

## Setup

### Wallpapers

Set your own pictures directory in `hypr/wallpaper.sh`

```bash
chmod +x hypr/wallpaper.sh
```

and add all pictures to hyprpaper to preload otherwise it will not work

```bash
nvim hypr/hyprpaper.conf
```

### Restart script

This script is for easily restarting startup services

```bash
chmod +x hypr/restart.sh
```

If you modified any of the dependencies you should modify the processes here also:

```bash
nvim hypr/restart.sh
```

### Idle timeout

Set your own custom values in `hypr/hypridle.conf`

```bash
nvim hypr/hypridle.conf
```

### Keybinds

Set your own preferred keybinds at `hypr/hyprland.conf`

```bash
nvim hypr/hyprland.conf
```

### OSD

You will need to run this command for osd to run

```bash
sudo systemctl start --now swayosd-libinput-backend.service
sudo systemctl enable --now swayosd-libinput-backend.service
```
