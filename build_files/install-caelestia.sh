#!/usr/bin/env bash
set -euo pipefail

SHELL_REF="${1:-v1.5.1}"
CLI_REF="${2:-v1.0.6}"

install_libcava() {
  echo "Installing libcava from source because Fedora's cava package does not provide the pkg-config metadata Caelestia Shell expects."
  git clone --depth=1 https://github.com/karlstav/cava.git /tmp/cava
  cd /tmp/cava

  ./autogen.sh
  ./configure --prefix=/usr/local
  make -j"$(nproc)"
  make install

  ldconfig || true

  pkg-config --exists cava
}

# Shell build expects pkg-config module 'cava'.
# On Fedora, the distro cava package commonly lacks the pkg-config metadata/header package needed here.
if ! pkg-config --exists cava; then
  install_libcava
fi

# Install shell
git clone --depth=1 --branch "${SHELL_REF}" https://github.com/caelestia-dots/shell.git /tmp/caelestia-shell
cmake -S /tmp/caelestia-shell -B /tmp/caelestia-shell/build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/
cmake --build /tmp/caelestia-shell/build
cmake --install /tmp/caelestia-shell/build

# Install CLI dependencies not conveniently available in Fedora repos
python3 -m pip install --no-cache-dir --break-system-packages materialyoucolor

# Install CLI
git clone --depth=1 --branch "${CLI_REF}" https://github.com/caelestia-dots/cli.git /tmp/caelestia-cli
cd /tmp/caelestia-cli
python3 -m build --wheel
python3 -m installer dist/*.whl
install -Dm0644 completions/caelestia.fish /usr/share/fish/vendor_completions.d/caelestia.fish

# Smoke checks
command -v qs
command -v caelestia
command -v sass
pkg-config --exists cava
