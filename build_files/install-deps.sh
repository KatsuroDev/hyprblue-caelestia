#!/usr/bin/env bash
set -euo pipefail

QUICKSHELL_COPR="${1:-errornointernet/quickshell}"

dnf5 -y copr enable "${QUICKSHELL_COPR}"

dnf5 install --setopt=install_weak_deps=False -y \
    hyprland \
    xdg-desktop-portal-hyprland \
    xdg-desktop-portal-gtk \
    hyprpicker \
    wl-clipboard \
    cliphist \
    app2unit \
    wireplumber \
    brightnessctl \
    ddcutil \
    lm_sensors \
    fish \
    swappy \
    libqalculate \
    libqalculate-devel \
    qalculate \
    cava \
    NetworkManager \
    libnotify \
    foot \
    fuzzel \
    grim \
    slurp \
    quickshell-git \
    cmake \
    ninja-build \
    git \
    curl \
    unzip \
    gcc-c++ \
    make \
    pkgconf-pkg-config \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel \
    aubio-devel \
    python3-build \
    python3-installer \
    python3-hatchling \
    python3-hatch-vcs \
    python3-pip \
    python3-pillow

# Optional:
# caelestia-cli "record" expects gpu-screen-recorder.
# Fedora availability varies, so it's left disabled by default.
#
# Example if you choose to enable an extra COPR yourself:
# dnf5 -y copr enable brycensranch/gpu-screen-recorder-git
# dnf5 install --setopt=install_weak_deps=False -y gpu-screen-recorder

dnf5 clean all
