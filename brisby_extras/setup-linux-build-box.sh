#!/usr/bin/env bash
#
# One-time setup for a Linux box (e.g. DigitalOcean Ubuntu 22.04) to build
# the Brisby BalenaOS image for CM5. Run as a normal user (will use sudo for installs).
#
# Prerequisites:
#   - Fresh Ubuntu 22.04 LTS (e.g. DigitalOcean droplet, 8 GB RAM, 4 vCPU, 100+ GB disk)
#   - Your balena-raspberrypi repo with meta-brisby and brisby_extras pushed to a Git URL
#
# Usage:
#   curl -sSL <raw-url-of-this-script> | bash -s -- [REPO_URL]
#   # or
#   chmod +x setup-linux-build-box.sh
#   ./setup-linux-build-box.sh [REPO_URL]
#
# If REPO_URL is omitted, REPO_URL env var must be set (your fork with meta-brisby).
# Example: REPO_URL=git@github.com:brisby-engineering/balena-raspberrypi.git ./setup-linux-build-box.sh
#

set -e

# Avoid GUI prompts (e.g. "restart services that use old libraries?" / needrestart)
export DEBIAN_FRONTEND=noninteractive

REPO_URL="${1:-${REPO_URL}}"
BRISBY_BRANCH="${BRISBY_BRANCH:-brisby}"
INSTALL_DIR="${BRISBY_INSTALL_DIR:-$HOME/balena-raspberrypi}"
BUILD_SPACE="${BRISBY_BUILD_SPACE:-$HOME/brisby_custom}"

echo "[setup] Brisby Linux build box setup (Ubuntu 22.04)"
echo "[setup] Install dir: ${INSTALL_DIR}"
echo "[setup] Build space: ${BUILD_SPACE}"
echo ""

# --- Docker ---
if ! command -v docker &>/dev/null; then
    echo "[setup] Installing Docker..."
    sudo -E apt-get update
    sudo -E apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME:-$UBUNTU_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo -E apt-get update
    sudo -E apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "[setup] Docker installed. You may need to log out and back in for group 'docker' to apply."
else
    echo "[setup] Docker already installed."
fi

# --- Git and minimal deps ---
sudo -E apt-get install -y git

# --- Clone repo (must contain meta-brisby and brisby_extras) ---
if [[ -z "${REPO_URL}" ]]; then
    echo ""
    echo "[setup] ERROR: No repo URL. Your balena-raspberrypi fork (with meta-brisby) must be cloned."
    echo "  Set REPO_URL or pass it as the first argument:"
    echo "    REPO_URL=git@github.com:brisby-engineering/balena-raspberrypi.git $0"
    echo "  or push your branch to a fork and run:"
    echo "    $0 git@github.com:brisby-engineering/balena-raspberrypi.git"
    exit 1
fi

if [[ ! -d "${INSTALL_DIR}/.git" ]]; then
    echo "[setup] Cloning repo from ${REPO_URL} into ${INSTALL_DIR} (branch: ${BRISBY_BRANCH})..."
    git clone -b "${BRISBY_BRANCH}" --recursive "${REPO_URL}" "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"
else
    echo "[setup] Directory ${INSTALL_DIR} already exists (git repo). Skipping clone."
    cd "${INSTALL_DIR}"
    echo "[setup] Fetching and checking out ${BRISBY_BRANCH}..."
    git fetch origin "${BRISBY_BRANCH}" 2>/dev/null || true
    git checkout "${BRISBY_BRANCH}" 2>/dev/null || true
    echo "[setup] Updating submodules..."
    git submodule update --init --recursive
fi

mkdir -p "${BUILD_SPACE}"
echo "[setup] Build space ready: ${BUILD_SPACE}"
echo ""

# --- Summary ---
echo "---"
echo "Setup done. Next steps:"
echo ""
echo "  1. If Docker was just installed, log out and back in (or run: newgrp docker)"
echo "  2. Run the build:"
echo ""
echo "     export BRISBY_BUILD_SPACE=${BUILD_SPACE}"
echo "     cd ${INSTALL_DIR}"
echo "     ./brisby_extras/build-brisby-compute5-image.sh"
echo ""
echo "  3. Wait 4–8 hours. Image will be in: ${BUILD_SPACE}/"
echo "  4. Download to your Mac: scp user@this-host:${BUILD_SPACE}/balena-image-raspberrypi5.balenaos-img* ."
echo ""
