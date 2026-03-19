# bluefin-dx-caelestia

A ready-to-push custom Universal Blue image repo for a **minimal Hyprland + Caelestia Shell** setup on top of **Bluefin DX**.

This image is built from `ghcr.io/ublue-os/bluefin-dx:stable` and installs:

- Hyprland
- Quickshell (`quickshell-git` from COPR)
- Caelestia Shell
- Caelestia CLI
- only the core runtime packages needed for the shell and CLI to work
- a minimal Hyprland config that autostarts `caelestia shell -d`

## What is included

### Core session packages
- `hyprland`
- `xdg-desktop-portal-hyprland`
- `xdg-desktop-portal-gtk`
- `hyprpicker`
- `wl-clipboard`
- `cliphist`
- `app2unit`
- `wireplumber`
- `foot`
- `fuzzel`
- `grim`
- `slurp`

### Shell runtime packages
- `brightnessctl`
- `ddcutil`
- `lm_sensors`
- `fish`
- `swappy`
- `libqalculate`
- `cava`
- `NetworkManager`
- `libnotify`
- `quickshell-git`

### Build/install dependencies
- `cmake`
- `ninja-build`
- `git`
- `gcc-c++`
- `qt6-qtbase-devel`
- `qt6-qtdeclarative-devel`
- `aubio-devel`
- `libqalculate-devel`
- `python3-build`
- `python3-installer`
- `python3-hatchling`
- `python3-hatch-vcs`
- `python3-pip`
- `python3-pillow`

### Fonts and assets
- exact **Material Symbols Rounded**
- exact **Caskaydia Cove Nerd Font**
- **Dart Sass** binary for CLI theming support

## Known limitation

`caelestia-cli`'s `record` subcommand expects `gpu-screen-recorder`, which is not installed by default in this repo because Fedora packaging for it is less straightforward and can vary. Everything else needed for the shell and the main CLI utilities is included.

If you want that too, uncomment the optional section in `build_files/install-deps.sh`.

### 3. Optional: enable Cosign signing
This workflow will build and push without signing.
If you want signed images, add a signing step or migrate to the upstream Universal Blue image template workflow.

### 4. Enable GitHub Actions
In your GitHub repo:
- open **Actions**
- enable workflows

## Build behavior

On push to `main`, GitHub Actions will:

1. build the image
2. push it to GHCR
3. tag it as:
   - `latest`
   - `sha-<commit>`

## Rebasing onto the image

You can rebase a Bluefin installation onto it with something like:

```bash
sudo bootc switch ghcr.io/KatsuroDev/bluefin-dx-caelestia:latest
sudo systemctl reboot
```

## Session notes

This repo drops a minimal user Hyprland config into `/etc/skel/.config/hypr/hyprland.conf`.

For **new users**, that becomes the default config.
For **existing users**, copy it manually if needed:

```bash
mkdir -p ~/.config/hypr
cp /etc/skel/.config/hypr/hyprland.conf ~/.config/hypr/hyprland.conf
```

The config autostarts:

```ini
exec-once = caelestia shell -d
```

## Version pins

Default build args:

- `CAELESTIA_SHELL_REF=v1.5.1`
- `CAELESTIA_CLI_REF=v1.0.6`
- `DART_SASS_VERSION=1.98.0`
