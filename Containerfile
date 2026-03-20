FROM ghcr.io/ublue-os/bluefin-dx:stable

ARG QUICKSHELL_COPR=errornointernet/quickshell
ARG CAELESTIA_SHELL_REF=v1.5.1
ARG CAELESTIA_CLI_REF=v1.0.6
ARG DART_SASS_VERSION=1.98.0

LABEL org.opencontainers.image.title="bluefin-dx-caelestia" \
      org.opencontainers.image.description="Bluefin DX with Hyprland, Quickshell, Caelestia Shell and Caelestia CLI" \
      org.opencontainers.image.source="https://github.com/YOUR_GITHUB_USERNAME/bluefin-dx-caelestia"

COPY build_files/ /tmp/build_files/
COPY system_files/ /

RUN chmod +x /tmp/build_files/*.sh \
    && /tmp/build_files/install-deps.sh "${QUICKSHELL_COPR}" \
    && /tmp/build_files/install-fonts.sh \
    && /tmp/build_files/install-dart-sass.sh "${DART_SASS_VERSION}" \
    && /tmp/build_files/install-caelestia.sh "${CAELESTIA_SHELL_REF}" "${CAELESTIA_CLI_REF}" \
    && fc-cache -f \
    && rm -rf /tmp/build_files /tmp/caelestia-shell /tmp/caelestia-cli /var/cache/dnf

# Default to graphical.target from the base image.
