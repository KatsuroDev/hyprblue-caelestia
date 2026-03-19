#!/usr/bin/env bash
set -euo pipefail

SHELL_REF="${1:-v1.5.1}"
CLI_REF="${2:-v1.0.6}"

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
