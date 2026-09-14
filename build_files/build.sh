#!/bin/bash

set -euo pipefail

log() { echo "=== $* ==="; }

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
    dnf5 -y copr enable "$repo"
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
    # qtengine-git
)

DOTS_OPT_PKGS=(
    thunar
    uwsm
    gnome-keyring
    polkit
    openrgb
    steam
    gamescope
)


dnf5 install --setopt=install_weak_deps=False -y \
    "${CAELESTIA_SHELL_CLI_DEPS[@]}" \
    "${DOTS_PKGS[@]}" \
    "${DOTS_OPT_PKGS[@]}"


# COPR Quickshell may require a newer Qt ABI than the base image provides.
log "Updating Qt runtime packages..."
dnf5 upgrade --refresh -y 'qt6-*'

# Executing qs catches linker errors that command -v cannot detect.
log "Checking Quickshell and Qt compatibility..."
rpm -q quickshell-git qt6-qtbase qt6-qtdeclarative
qs --version

log "Disabling COPR repos..."
for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
done

###############################################################################
# CONFIG MIGRATION HELPER
###############################################################################
log "Installing Caelestia config migration helper..."
install -Dm0755 /ctx/migrate-caelestia-config.py /usr/bin/hyprblue-caelestia-migrate
hyprblue-caelestia-migrate --help >/dev/null

log "Build complete!"

###############################################################################
# FONTS
###############################################################################

FONT_DIR="/usr/share/fonts/jetbrains"
install -d "${FONT_DIR}"
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" | tar xJ -C /usr/share/fonts/jetbrains
fc-cache -f "${FONT_DIR}"

###############################################################################
# CAELESTIA DOTS CONFIGS → /etc/skel
###############################################################################
log "Installing caelestia dots configs..."

# Clone the current upstream dots. /usr/share is also the source used by the
# per-user legacy migration helper after an image upgrade.
git clone --depth=1 \
    https://github.com/caelestia-dots/caelestia.git /usr/share/caelestia-dots

# /etc/skel only initializes new home directories. Existing users should run
# hyprblue-caelestia-migrate after an upgrade from the legacy .conf layout.
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
