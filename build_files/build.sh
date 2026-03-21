#!/bin/bash
# build.sh — caelestia-bluefin
# Installs the full caelestia dots (shell + CLI + configs + all dependencies)
# on top of bluefin-dx (Fedora 43).

set -ouex pipefail

log() { echo "=== $* ==="; }

###############################################################################
# VERSIONS
###############################################################################
CAELESTIA_SHELL_VERSION="v1.4.2"   # https://github.com/caelestia-dots/shell/releases
CAELESTIA_CLI_VERSION="v1.0.5"     # https://github.com/caelestia-dots/cli/releases
CAVA_VERSION="0.10.6"              # https://github.com/LukashonakV/cava/releases
NERD_FONTS_VERSION="v3.3.0"        # https://github.com/ryanoasis/nerd-fonts/releases

###############################################################################
# COPR REPOS
###############################################################################
log "Enabling COPR repos..."

COPR_REPOS=(
    solopasha/hyprland
    errornointernet/quickshell
)

for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr enable "$repo" || true
done

###############################################################################
# PACKAGES
###############################################################################
log "Installing packages..."

HYPR_PKGS=(
    hyprland
    hypridle
    hyprlock
    hyprpaper
    hyprcursor
    hyprpicker
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    uwsm
)

QS_PKGS=(
    quickshell-git
)

CAELESTIA_RUNTIME=(
    brightnessctl
    ddcutil
    pipewire
    pipewire-utils
    wireplumber
    pavucontrol
    NetworkManager
    network-manager-applet
    grim
    slurp
    swappy
    wl-clipboard
    cliphist
    libnotify
    dunst
    fuzzel
    thunar
    thunar-volman
    thunar-archive-plugin
    trash-cli
    fastfetch
    btop
    lm_sensors
    foot
    fish
    starship
    eza
    qalculate
    libqalculate
    inotify-tools
    qt5ct
    qt6ct
    qt6-qtbase
    qt6-qtdeclarative
    qt6-qtsvg
    qt6-qt5compat
    adw-gtk3-theme
    papirus-icon-theme
    playerctl
    jq
    curl
    bash
)

BUILD_DEPS=(
    git
    cmake
    ninja-build
    gcc
    gcc-c++
    pkg-config
    meson
    fftw-devel
    iniparser-devel
    ncurses-devel
    portaudio-devel
    alsa-lib-devel
    pulseaudio-libs-devel
    pipewire-devel
    qt6-qtbase-devel
    qt6-qtdeclarative-devel
    qt6-qtbase-private-devel
    libdrm-devel
    wayland-devel
    wayland-protocols-devel
    aubio-devel
    libqalculate-devel
    nodejs
    nodejs-npm
    python3-build
    python3-installer
    python3-hatch-vcs
    python3
    python3-pip
)

dnf5 install --setopt=install_weak_deps=False -y \
    "${HYPR_PKGS[@]}" \
    "${QS_PKGS[@]}" \
    "${CAELESTIA_RUNTIME[@]}" \
    "${BUILD_DEPS[@]}"

# dart-sass via npm (needed by caelestia-cli for Discord theming)
npm install -g sass

###############################################################################
# BUILD CAVA (provides libcava + pkg-config)
###############################################################################
log "Building cava ${CAVA_VERSION}..."

curl -fsSL "https://github.com/LukashonakV/cava/archive/refs/tags/${CAVA_VERSION}.tar.gz" \
    -o /tmp/cava.tar.gz
cd /tmp && tar xf cava.tar.gz && cd "cava-${CAVA_VERSION}"

CC=gcc CXX=g++ meson setup build --prefix=/usr --buildtype=release
CC=gcc CXX=g++ meson compile -C build -j"$(nproc)"
meson install -C build

ln -sf /usr/lib64/pkgconfig/cava.pc /usr/lib64/pkgconfig/libcava.pc
ldconfig
cd /tmp && rm -rf "cava-${CAVA_VERSION}" cava.tar.gz

###############################################################################
# BUILD CAELESTIA-SHELL
###############################################################################
log "Building caelestia-shell ${CAELESTIA_SHELL_VERSION}..."

git clone --depth=1 --branch "${CAELESTIA_SHELL_VERSION}" \
    https://github.com/caelestia-dots/shell.git /tmp/caelestia-shell

cd /tmp/caelestia-shell

cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DINSTALL_QSCONFDIR=/usr/share/quickshell/caelestia

cmake --build build -j"$(nproc)"
cmake --install build

mkdir -p /etc/xdg/quickshell
ln -sf /usr/share/quickshell/caelestia /etc/xdg/quickshell/caelestia

mkdir -p /usr/lib64/qt6/qml
ln -sf /usr/lib/qt6/qml/Caelestia /usr/lib64/qt6/qml/Caelestia

ldconfig
cd /tmp && rm -rf /tmp/caelestia-shell

###############################################################################
# BUILD CAELESTIA-CLI
###############################################################################
log "Building caelestia-cli ${CAELESTIA_CLI_VERSION}..."

git clone --depth=1 --branch "${CAELESTIA_CLI_VERSION}" \
    https://github.com/caelestia-dots/cli.git /tmp/caelestia-cli

cd /tmp/caelestia-cli

pip3 install materialyoucolor --break-system-packages
python3 -m build --wheel --no-isolation
python3 -m installer --prefix /usr dist/*.whl

install -Dm644 completions/caelestia.fish \
    /usr/share/fish/vendor_completions.d/caelestia.fish

cd /tmp && rm -rf /tmp/caelestia-cli

###############################################################################
# INSTALL APP2UNIT
###############################################################################
log "Installing app2unit..."

git clone --depth=1 \
    https://github.com/Vladimir-csp/app2unit.git /tmp/app2unit

install -Dpm755 /tmp/app2unit/app2unit              -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-open          -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-open-scope    -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-open-service  -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-term          -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-term-scope    -t /usr/bin
install -Dpm755 /tmp/app2unit/app2unit-term-service  -t /usr/bin

rm -rf /tmp/app2unit

###############################################################################
# INSTALL FONTS
###############################################################################
log "Installing fonts..."

FONT_DIR="/usr/share/fonts/caelestia"
install -d "${FONT_DIR}"

curl -fsSL \
    "https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" \
    -o "${FONT_DIR}/MaterialSymbolsRounded.ttf"

curl -fsSL \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/CascadiaCode.zip" \
    -o /tmp/CascadiaCode.zip
cd /tmp && unzip -q CascadiaCode.zip "CaskaydiaCoveNerd*.ttf" -d "${FONT_DIR}"
rm -f /tmp/CascadiaCode.zip

curl -fsSL \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/JetBrainsMono.zip" \
    -o /tmp/JetBrainsMono.zip
cd /tmp && unzip -q JetBrainsMono.zip "JetBrainsMonoNerd*.ttf" -d "${FONT_DIR}"
rm -f /tmp/JetBrainsMono.zip

fc-cache -f "${FONT_DIR}"

###############################################################################
# CAELESTIA DOTS CONFIGS → /etc/skel
###############################################################################
# Clone the main dots repo and install configs into /etc/skel so every new
# user gets a working setup automatically. Existing users: cp -rn /etc/skel/.config ~/
log "Installing caelestia dots configs..."

git clone --depth=1 \
    https://github.com/caelestia-dots/caelestia.git /usr/share/caelestia-dots

install -d /etc/skel/.config

for dir in hypr foot fish fastfetch uwsm btop thunar; do
    if [ -d "/usr/share/caelestia-dots/${dir}" ]; then
        cp -r "/usr/share/caelestia-dots/${dir}" "/etc/skel/.config/${dir}"
    fi
done

if [ -f /usr/share/caelestia-dots/starship.toml ]; then
    cp /usr/share/caelestia-dots/starship.toml /etc/skel/.config/starship.toml
fi

install -d /etc/skel/Pictures/Wallpapers

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

###############################################################################
# DISABLE COPR REPOS
###############################################################################
log "Disabling COPR repos..."

for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
done

log "Build complete."