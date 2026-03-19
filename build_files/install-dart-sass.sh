#!/usr/bin/env bash
set -euo pipefail

DART_SASS_VERSION="${1:-1.98.0}"
ARCH="$(uname -m)"

case "${ARCH}" in
  x86_64) SASS_ARCH="x64" ;;
  aarch64) SASS_ARCH="arm64" ;;
  *)
    echo "Unsupported architecture for dart-sass: ${ARCH}" >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
ARCHIVE="dart-sass-${DART_SASS_VERSION}-linux-${SASS_ARCH}.tar.gz"

curl -L \
  "https://github.com/sass/dart-sass/releases/download/${DART_SASS_VERSION}/${ARCHIVE}" \
  -o "${TMP_DIR}/${ARCHIVE}"

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}"
rm -rf /usr/local/lib/dart-sass
mkdir -p /usr/local/lib
mv "${TMP_DIR}/dart-sass" /usr/local/lib/dart-sass

ln -sf /usr/local/lib/dart-sass/sass /usr/local/bin/sass

rm -rf "${TMP_DIR}"
