https://copr.fedorainfracloud.org/coprs/celestelove/caelestia/
https://github.com/caelestia-dots/caelestia/blob/main/PKGBUILD
https://github.com/KernelFreeze/caelestia-shell-fedora

Note:

Seems like the foots are not great, might wanna fix those.
Papirus-folders might need fix for cli?
Missing cli.json and shell.json in ~/.config/caelestia/

## Prerequisites

caelestia-shell requires quickshell-git, libcava, gpu-screen-recorder, and app2unit, each available from separate COPRs:

sudo dnf copr enable errornointernet/quickshell
sudo dnf install quickshell-git

sudo dnf copr enable celestelove/libcava
sudo dnf install libcava-devel

sudo dnf copr enable celestelove/app2unit
sudo dnf install app2unit

sudo dnf copr enable brycensranch/gpu-screen-recorder-git
sudo dnf install gpu-screen-recorder-ui

### Install

To install caelestia-shell and cli, enable the repository and install:

sudo dnf copr enable celestelove/caelestia
sudo dnf install caelestia-shell caelestia-cli
