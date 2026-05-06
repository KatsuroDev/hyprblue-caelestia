#!/bin/bash

###############################################################################
# COPR REPOS
###############################################################################
log "Enabling COPR repos..."

COPR_REPOS=(
    "errornointernet/quickshell"
    "celestelove/libcava"
    "celestelove/app2unit"
    "brycensranch/gpu-screen-recorder-git"
    "celestelove/caelestia"
    "sdegler/hyprland"
    "dturner/TOS"
    "atim/starship"
)

for repo in "${COPR_REPOS[@]}"; do
    dnf -y copr enable "$repo" || true
done

###############################################################################
# PACKAGES
###############################################################################
log "Installing packages..."

CAELESTIA_SHELL_CLI_DEPS=(
    quickshell-git
    libcava-devel
    app2unit
    gpu-screen-recorder-ui
    ImageMagick
)

DOTS_PKGS=(
    caelestia-shell
    caelestia-cli
    hyprland
    hyprpicker
    hyprland-guiutils
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    inotify-tools
    wireplumber
    trash-cli
    foot
    fastfetch
    starship
    btop
    jq
    eza
    adw-gtk3-theme
    papirus-icon-theme
    xdg-utils
    # qtengine-git
)

DOTS_OPT_PKGS=(
    thunar
    uwsm
    gnome-keyring
    polkit
)


dnf5 install --setopt=install_weak_deps=False --skip-unavailable -y \
    "${CAELESTIA_SHELL_CLI_DEPS[@]}" \
    "${DOTS_PKGS[@]}" \
    "${DOTS_OPT_PKGS[@]}"


log "Disabling COPR repos..."
for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
done

log "Build complete!"

###############################################################################
# CAELESTIA DOTS CONFIGS → /etc/skel
###############################################################################
log "Installing caelestia dots configs..."

# Clone to the path the install script expects
git clone --depth=1 \
    https://github.com/caelestia-dots/caelestia.git /usr/share/caelestia-dots

# The caelestia hypr configs use relative source includes — they expect the
# repo to be at a stable path. We put it in /usr/share/caelestia-dots and
# copy (not symlink) into skel so users get their own editable copy.
install -d /etc/skel/.config
install -d /etc/skel/.local/share

# Copy all config dirs into skel
for dir in hypr foot fish fastfetch uwsm btop thunar micro; do
    if [ -d "/usr/share/caelestia-dots/${dir}" ]; then
        cp -r "/usr/share/caelestia-dots/${dir}" "/etc/skel/.config/${dir}"
    fi
done

# starship prompt config
if [ -f /usr/share/caelestia-dots/starship.toml ]; then
    cp /usr/share/caelestia-dots/starship.toml /etc/skel/.config/starship.toml
fi

# Wallpapers directory
install -d /etc/skel/Pictures/Wallpapers

# caelestia-specific config dir
install -d /etc/skel/.config/caelestia

cat > /etc/skel/.config/caelestia/shell.json << 'EOF'
{
    "general": {
        "apps": {
            "terminal": ["foot"],
            "audio": ["pavucontrol"],
            "explorer": ["thunar"]
        }
    },
    "paths": {
        "wallpaperDir": "~/Pictures/Wallpapers"
    },
    "services": {
        "useFahrenheit": false,
        "useTwelveHourClock": false
    }
}
EOF

cat > /etc/skel/.config/caelestia/cli.json << 'EOF'
{
    "theme": {
        "enableDiscord": false,
        "enableSpicetify": false
    }
}
EOF

wget -qO- https://git.io/papirus-folders-install | sh
