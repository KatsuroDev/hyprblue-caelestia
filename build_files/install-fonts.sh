#!/usr/bin/env bash
set -euo pipefail

FONT_DIR="/usr/local/share/fonts/caelestia"
mkdir -p "${FONT_DIR}"

# Exact Material Symbols Rounded font expected by the shell.
curl -L \
  "https://raw.githubusercontent.com/google/material-design-icons/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf" \
  -o "${FONT_DIR}/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"

# Exact Caskaydia Cove Nerd Font family expected by the shell.
TMP_DIR="$(mktemp -d)"
curl -L \
  "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaCode.zip" \
  -o "${TMP_DIR}/CascadiaCode.zip"

unzip -q "${TMP_DIR}/CascadiaCode.zip" -d "${TMP_DIR}/cascadia"

find "${TMP_DIR}/cascadia" -maxdepth 1 -type f -name 'CaskaydiaCoveNerdFont*.ttf' -exec cp {} "${FONT_DIR}/" \;
find "${TMP_DIR}/cascadia" -maxdepth 1 -type f -name 'CaskaydiaCoveNF*.ttf' -exec cp {} "${FONT_DIR}/" \; || true

rm -rf "${TMP_DIR}"
