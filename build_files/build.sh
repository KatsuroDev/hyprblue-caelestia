#!/bin/bash
# build.sh — installs caelestia-shell and its minimal runtime dependencies
# on top of bluefin-dx.
#
# Dependency notes
# ─────────────────────────────────────────────────────────────────────────────
# • quickshell-git   → errornointernet/quickshell COPR
# • hyprland stack   → solopasha/hyprland COPR
# • libcava          → Fedora ships only the cava CLI; we build from source
#                      to get the shared library + pkg-config file.
# • caelestia-shell  → built from source with CMake + Ninja
# • caelestia-cli    → Python package, built with python -m build
# • app2unit         → single-file shell script downloaded from GitHub
# • Fonts            → Material Symbols Rounded + CaskaydiaCove Nerd Font
#                      downloaded from GitHub releases
# ─────────────────────────────────────────────────────────────────────────────

set -ouex pipefail

log() { echo "=== $* ==="; }

###############################################################################
# VERSIONS — pin these to avoid surprises; bump to update
###############################################################################
CAELESTIA_SHELL_VERSION="v1.4.2"
CAELESTIA_CLI_VERSION="v1.0.5"
CAVA_VERSION="0.10.6"           # LukashonakV/cava release tag
APP2UNIT_VERSION=""       # unused, cloning master directly
# Nerd Fonts release (used for CaskaydiaCove NF)
NERD_FONTS_VERSION="v3.3.0"
# Material Symbols font from google-fonts tree (commit-pinned tarball not practical;
# we pull the latest release from the fonts/google repo mirror instead)
MATERIAL_SYMBOLS_URL="https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf"

###############################################################################
# COPR REPOS
###############################################################################
log "Enabling COPR repos..."

COPR_REPOS=(
    solopasha/hyprland           # hyprland, hypridle, hyprlock, hyprpaper …
    errornointernet/quickshell   # quickshell and quickshell-git
)

for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr enable "$repo" || true
done

###############################################################################
# RUNTIME PACKAGES
###############################################################################
log "Installing runtime packages..."

# Hyprland stack — from solopasha/hyprland COPR + standard Fedora
HYPR_PKGS=(
    hyprland
    hypridle
    hyprlock
    hyprpaper
    hyprcursor
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    # polkit: bluefin-dx already ships a working GNOME polkit agent
)

# quickshell — git version required by caelestia-shell
QS_PKGS=(
    quickshell-git
)

# caelestia-shell runtime dependencies (Fedora package names)
CAELESTIA_RUNTIME=(
    # display / brightness
    brightnessctl
    ddcutil
    # networking widget
    NetworkManager            # already in bluefin, but belt-and-suspenders
    network-manager-applet
    # audio / pipewire
    pipewire
    pipewire-utils
    wireplumber
    # system sensors
    lm_sensors
    # screenshot tool
    swappy
    grim
    slurp
    # calculator widget (libqalculate runtime)
    qalculate
    # fish shell (used in some caelestia helper scripts)
    fish
    # clipboard
    wl-clipboard
    cliphist
    # Qt6 runtime (quickshell is Qt6-based)
    qt6-qtbase
    qt6-qtdeclarative
    qt6-qtsvg
    qt6-qt5compat
    # misc utilities used by shell scripts
    bash
    curl
    jq
)

# Build-time tools (kept in image for potential user rebuilds;
# small enough that it's not worth a multi-stage clean-up layer)
BUILD_DEPS=(
    git
    cmake
    ninja-build
    gcc
    gcc-c++
    pkg-config
    # cava build deps (meson + audio libs)
    meson
    fftw-devel
    iniparser-devel
    ncurses-devel
    portaudio-devel
    alsa-lib-devel
    pulseaudio-libs-devel
    pipewire-devel
    # caelestia-shell build deps
    qt6-qtbase-devel
    qt6-qtdeclarative-devel
    qt6-qtbase-private-devel
    libdrm-devel
    wayland-devel
    wayland-protocols-devel
    # aubio (beat detector)
    aubio-devel
    # caelestia-cli (Python build)
    python3-build
    python3-installer
    python3-hatch-vcs
    python3
    python3-pip
    # libqalculate dev (for shell calculator plugin)
    libqalculate-devel
)

dnf5 install --setopt=install_weak_deps=False -y \
    "${HYPR_PKGS[@]}" \
    "${QS_PKGS[@]}" \
    "${CAELESTIA_RUNTIME[@]}" \
    "${BUILD_DEPS[@]}"

###############################################################################
# BUILD CAVA FROM SOURCE (provides libcava + pkg-config file)
###############################################################################
# Fedora packages cava as a CLI-only binary without the shared library or
# the pkg-config file that caelestia-shell's CMake build requires.
# Building from source installs both.
log "Building cava ${CAVA_VERSION} from source (meson)..."

# Use the LukashonakV fork which ships a meson build that properly installs
# libcava as a shared library + pkg-config file. The autotools path only
# installs the CLI binary.
CAVA_TARBALL="cava-${CAVA_VERSION}.tar.gz"
curl -fsSL "https://github.com/LukashonakV/cava/archive/refs/tags/${CAVA_VERSION}.tar.gz" \
    -o "/tmp/${CAVA_TARBALL}"

cd /tmp
tar xf "${CAVA_TARBALL}"
cd "cava-${CAVA_VERSION}"

CC=gcc CXX=g++ meson setup build --prefix=/usr --buildtype=release
CC=gcc CXX=g++ meson compile -C build -j"$(nproc)"
meson install -C build

# meson installs the pkg-config file as 'cava.pc' but caelestia-shell's
# CMake looks for 'libcava' — create a symlink to satisfy it
ln -sf /usr/lib64/pkgconfig/cava.pc /usr/lib64/pkgconfig/libcava.pc

ldconfig

cd /tmp
rm -rf "cava-${CAVA_VERSION}" "${CAVA_TARBALL}"

###############################################################################
# BUILD CAELESTIA-SHELL FROM SOURCE
###############################################################################
log "Building caelestia-shell ${CAELESTIA_SHELL_VERSION}..."

SHELL_SRC="/tmp/caelestia-shell-src"
git clone --depth=1 --branch "${CAELESTIA_SHELL_VERSION}" \
    https://github.com/caelestia-dots/shell.git "${SHELL_SRC}"

cd "${SHELL_SRC}"

# Install to /usr so the QML plugin and binary land in standard paths.
# INSTALL_QSCONFDIR places the QML config at /usr/share/quickshell/caelestia
# (the default Quickshell config search path).
cmake -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DINSTALL_QSCONFDIR=/usr/share/quickshell/caelestia

cmake --build build -j"$(nproc)"
cmake --install build

# qs -c caelestia searches XDG config paths for a subdir named "caelestia".
# Symlink the installed config into /etc/xdg/quickshell/ so it's found system-wide.
mkdir -p /etc/xdg/quickshell
ln -sf /usr/share/quickshell/caelestia /etc/xdg/quickshell/caelestia

cd /tmp
rm -rf "${SHELL_SRC}"

###############################################################################
# BUILD CAELESTIA-CLI FROM SOURCE
###############################################################################
log "Building caelestia-cli ${CAELESTIA_CLI_VERSION}..."

CLI_SRC="/tmp/caelestia-cli-src"
git clone --depth=1 --branch "${CAELESTIA_CLI_VERSION}" \
    https://github.com/caelestia-dots/cli.git "${CLI_SRC}"

cd "${CLI_SRC}"

# Build a wheel and install it system-wide
python3 -m build --wheel --no-isolation
python3 -m installer --prefix /usr dist/*.whl

# Fish completions
install -Dm644 completions/caelestia.fish \
    /usr/share/fish/vendor_completions.d/caelestia.fish

cd /tmp
rm -rf "${CLI_SRC}"

###############################################################################
# INSTALL APP2UNIT
###############################################################################
log "Installing app2unit (latest master)..."

git clone --depth=1 \
    https://github.com/Vladimir-csp/app2unit.git /tmp/app2unit-src

# The Makefile defaults to /usr/local which is a broken symlink in bootc images.
# Install scripts directly to /usr/bin instead.
install -Dpm755 /tmp/app2unit-src/app2unit -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-open -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-open-scope -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-open-service -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-term -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-term-scope -t /usr/bin
install -Dpm755 /tmp/app2unit-src/app2unit-term-service -t /usr/bin

rm -rf /tmp/app2unit-src

###############################################################################
# INSTALL FONTS
###############################################################################
log "Installing fonts..."

FONT_DIR="/usr/share/fonts/caelestia"
install -d "${FONT_DIR}"

# 1. Material Symbols Rounded (variable font)
curl -fsSL "${MATERIAL_SYMBOLS_URL}" \
    -o "${FONT_DIR}/MaterialSymbolsRounded.ttf"

# 2. CaskaydiaCove Nerd Font from Nerd Fonts releases
NF_BASE="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}"
curl -fsSL "${NF_BASE}/CascadiaCode.zip" -o /tmp/CascadiaCode.zip
cd /tmp
unzip -q CascadiaCode.zip "CaskaydiaCoveNerd*.ttf" -d "${FONT_DIR}" || \
    unzip -q CascadiaCode.zip "*.ttf" -d "${FONT_DIR}"   # fallback glob
rm -f CascadiaCode.zip

# Regenerate font cache
fc-cache -f "${FONT_DIR}"

###############################################################################
# DEFAULT CONFIG FILES
###############################################################################
# Ship minimal working configs so users don't need to create them manually.
# These land in /etc/skel so they're copied to new user home directories,
# and can also be copied manually: cp -r /etc/skel/.config ~/

install -d /etc/skel/.config/hypr
cat > /etc/skel/.config/hypr/hyprland.conf <<'EOF'
# caelestia-bluefin default hyprland config
# See https://wiki.hyprland.org/Configuring/

exec-once = caelestia shell -d

input {
    kb_layout = us
    follow_mouse = 1
    touchpad {
        natural_scroll = true
    }
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee)
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}

decoration {
    rounding = 10
    blur {
        enabled = true
        size = 3
        passes = 1
    }
}

animations {
    enabled = true
}

dwindle {
    pseudotile = true
    preserve_split = true
}

# Keybinds — all shell interactions go via caelestia global shortcuts
$mod = SUPER
bind = $mod, return, exec, foot
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, V, togglefloating
bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

# Mouse
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow
EOF

install -d /etc/skel/.config/caelestia
cat > /etc/skel/.config/caelestia/shell.json <<'EOF'
{
    "general": {
        "apps": {
            "terminal": ["foot"],
            "audio": ["pavucontrol"],
            "explorer": ["nautilus"]
        }
    },
    "paths": {
        "wallpaperDir": "~/Pictures/Wallpapers"
    }
}
EOF

install -d /etc/skel/Pictures/Wallpapers

###############################################################################
# DISABLE COPR REPOS (keep final image clean)
###############################################################################
log "Disabling COPR repos..."
for repo in "${COPR_REPOS[@]}"; do
    dnf5 -y copr disable "$repo" || true
done

log "Build complete."