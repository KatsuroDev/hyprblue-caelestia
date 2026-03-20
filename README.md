# caelestia-bluefin

A minimal [bootc](https://github.com/bootc-dev/bootc) image based on
[`bluefin-dx`](https://github.com/ublue-os/bluefin) that ships
[caelestia-shell](https://github.com/caelestia-dots/shell) (the Quickshell-based
desktop shell) along with Hyprland and the exact runtime packages it needs — nothing
more.

## What's included

| Component | Source | Notes |
|---|---|---|
| **caelestia-shell** | Built from source | Pinned to a release tag |
| **caelestia-cli** | Built from Python wheel | Full IPC + wallpaper/scheme control |
| **quickshell-git** | `errornointernet/quickshell` COPR | Required by caelestia-shell |
| **Hyprland stack** | `solopasha/hyprland` COPR | hyprland, hypridle, hyprlock, hyprpaper |
| **cava** | Built from source | Provides `libcava` which Fedora's package omits |
| **app2unit** | Downloaded from GitHub | Launches apps as systemd units |
| **Material Symbols Rounded** | Google Fonts | Required font for the shell UI |
| **CaskaydiaCove Nerd Font** | Nerd Fonts releases | Monospace font for the shell |

## What's NOT included

- 1Password, Google Chrome, or any proprietary app
- Niri, Waybar, hyprpanel, or other alternative shell components
- Any theming/dotfiles beyond the shell itself

## How to use

### Switch to this image

```bash
sudo bootc switch ghcr.io/<your-username>/caelestia-bluefin:latest
```

Reboot, then log in to your normal GNOME session first.

### Configure Hyprland to start the shell

Add to your Hyprland config (`~/.config/hypr/hyprland.conf`):

```
exec-once = caelestia shell -d
```

Or launch manually:

```bash
qs -c caelestia
```

### Start Hyprland

From a TTY or via UWSM:

```bash
uwsm start hyprland
```

### Post-install configuration

The shell reads `~/.config/caelestia/shell.json` — create it from the
[example in the upstream README](https://github.com/caelestia-dots/shell#example-configuration).

Wallpapers are read from `~/Pictures/Wallpapers` by default.

## Pinned versions

Edit `build_files/build.sh` to bump any of these:

```bash
CAELESTIA_SHELL_VERSION="v1.4.2"
CAELESTIA_CLI_VERSION="v1.3.0"
CAVA_VERSION="0.10.4"
APP2UNIT_VERSION="v1.7.1"
NERD_FONTS_VERSION="v3.3.0"
```

## Building locally

```bash
podman build --network=host -t caelestia-bluefin:local .
```

## Troubleshooting

**Screen flickering?**  
Add to `~/.config/caelestia/hypr-user.conf`:
```
misc { vrr = 0 }
```

**Shell not launching?**  
Check that `qs` is in your PATH and `quickshell-git` is installed:
```bash
qs --version
```

**Wallpapers not showing in launcher?**  
Put images in `~/Pictures/Wallpapers` — at least 3 (the launcher shows an odd count).
