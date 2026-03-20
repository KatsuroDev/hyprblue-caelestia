# Base Image — ARG must come before any FROM that uses it
ARG BASE_IMAGE=ghcr.io/ublue-os/bluefin-dx:latest

# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Main image
FROM ${BASE_IMAGE}

### MODIFICATIONS
# All customisations live in build.sh so this layer stays minimal.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build.sh

### LINTING
RUN bootc container lint
