#!/usr/bin/env bash
#
# Build a custom BalenaOS image for Raspberry Pi Compute Module 5 (CM5) with:
#   - JD9365DA-H3 panel kernel module (loaded early at boot)
#   - Device tree overlay jd9365da-h3 on the boot partition
#   - Early systemd service to load the panel module before DSI probes
#
# Uses meta-brisby layer and outputs an image suitable for flashing to CM5.
# Build space and output: /Volumes/BRISBY/brisby_custom (or BRISBY_BUILD_SPACE on Linux/cloud)
#
# Prerequisites:
#   - Docker (Docker Desktop on macOS; use containerized build only)
#   - Run from balena-raspberrypi repo root
#   - Optional: cgroups v1 if on Linux (see BUILD_CUSTOM_BALENA_IMAGE.md)
#
# Builder image: If pulling ghcr.io/balena-os/balena-yocto-scripts fails (denied),
# the script builds the helper image locally from balena-yocto-scripts/automation.
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRISBY_EXTRAS="${REPO_ROOT}/brisby_extras"
META_BRISBY="${REPO_ROOT}/layers/meta-brisby"
# On Linux/cloud (e.g. DigitalOcean) set BRISBY_BUILD_SPACE to a local path, e.g. export BRISBY_BUILD_SPACE=$HOME/brisby_custom
BUILD_SPACE="${BRISBY_BUILD_SPACE:-/Volumes/BRISBY/brisby_custom}"
DEVICE_TYPE="raspberrypi5"
DEPLOY_SUBDIR="tmp/deploy/images/${DEVICE_TYPE}"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Build custom BalenaOS image for CM5 with JD9365DA-H3 panel support."
    echo ""
    echo "Options:"
    echo "  -n, --dry-run       Only prepare build space and meta-brisby; do not run build"
    echo "  -r, --refresh       Refresh panel/overlay sources from brisby_extras into meta-brisby"
    echo "  --rebuild-helper    Rebuild the Docker helper image (use if you see groupadd GID errors)"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Output: image and artifacts in ${BUILD_SPACE}/"
    echo ""
    echo "On Linux/cloud (e.g. DigitalOcean): export BRISBY_BUILD_SPACE=\$HOME/brisby_custom"
    exit 0
}

REFRESH_SOURCES=""
DRY_RUN=""
REBUILD_HELPER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)       DRY_RUN="1"; shift ;;
        -r|--refresh)       REFRESH_SOURCES="1"; shift ;;
        --rebuild-helper)   REBUILD_HELPER="1"; shift ;;
        -h|--help)          usage ;;
        *)                  echo "Unknown option: $1"; usage ;;
    esac
done

echo "[brisby] Repo root: ${REPO_ROOT}"
echo "[brisby] Build space: ${BUILD_SPACE}"
echo ""

# Ensure build space exists
if [[ ! -d "${BUILD_SPACE}" ]]; then
    echo "[brisby] Creating build space: ${BUILD_SPACE}"
    mkdir -p "${BUILD_SPACE}"
fi

# Optional: refresh panel and overlay sources from brisby_extras into meta-brisby
if [[ -n "${REFRESH_SOURCES}" ]]; then
    echo "[brisby] Refreshing panel and overlay sources from brisby_extras..."
    cp -f "${BRISBY_EXTRAS}/panel-jadard-jd9365da-h3.c" \
          "${META_BRISBY}/recipes-kernel/panel-jd9365da/files/"
    cp -f "${BRISBY_EXTRAS}/jd9365da-h3-overlay.dts" \
          "${META_BRISBY}/recipes-bsp/jd9365da-overlay/files/"
    echo "[brisby] Sources updated."
fi

# Sanity checks
if [[ ! -f "${META_BRISBY}/conf/layer.conf" ]]; then
    echo "[brisby] ERROR: meta-brisby layer not found at ${META_BRISBY}. Run from balena-raspberrypi repo root."
    exit 1
fi
if [[ ! -f "${REPO_ROOT}/balena-yocto-scripts/build/balena-build.sh" ]]; then
    echo "[brisby] ERROR: balena-build.sh not found. Run from balena-raspberrypi repo root."
    exit 1
fi

# Apply overrides from brisby_extras/overrides/ onto submodules (no need to push to other repos)
# This way only the fork needs to be cloned; balena-yocto-scripts and poky stay upstream.
if [[ -d "${BRISBY_EXTRAS}/overrides" ]]; then
    echo "[brisby] Applying overrides (balena-yocto-scripts, poky)..."
    [[ -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/entry_scripts/prepare-and-start.sh" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/entry_scripts/prepare-and-start.sh" \
              "${REPO_ROOT}/balena-yocto-scripts/automation/entry_scripts/"
    [[ -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/include/balena-lib.inc" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/include/balena-lib.inc" \
              "${REPO_ROOT}/balena-yocto-scripts/automation/include/"
    [[ -f "${BRISBY_EXTRAS}/overrides/poky/meta/classes/sanity.bbclass" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/poky/meta/classes/sanity.bbclass" \
              "${REPO_ROOT}/layers/poky/meta/classes/"
    echo "[brisby] Overrides applied."
fi

# Run containerized build: use meta-brisby templates and add panel packages to image
echo "[brisby] Starting BalenaOS containerized build for ${DEVICE_TYPE}..."
echo "[brisby] This can take a long time (tens of GB download + build)."
echo ""

if [[ -n "${DRY_RUN}" ]]; then
    echo "[brisby] Dry run: skipping actual build."
    echo "[brisby] To build, run without -n:"
    echo "  $0"
    exit 0
fi

# Ensure builder image exists. When we have Brisby overrides for balena-yocto-scripts,
# build the helper from the repo (so the container uses our GID/UID 0 fix); otherwise pull or build.
HELPER_REPO="${HELPER_IMAGE_REPO:-ghcr.io/balena-os/balena-yocto-scripts}"
HELPER_VERSION="$(head -n1 "${REPO_ROOT}/balena-yocto-scripts/VERSION" 2>/dev/null || echo "1.39.19")"
HELPER_TAG="${HELPER_REPO}:${HELPER_VERSION}-yocto-build-env"
BRISBY_HELPER_OVERRIDE="${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/entry_scripts/prepare-and-start.sh"
if [[ -n "${REBUILD_HELPER}" ]]; then
    echo "[brisby] Rebuilding builder image ${HELPER_TAG}..."
    docker rmi "${HELPER_TAG}" 2>/dev/null || true
fi
if [[ -f "${BRISBY_HELPER_OVERRIDE}" ]]; then
    # Build helper from repo so it includes our prepare-and-start.sh (GID/UID 0 fix)
    if ! docker image inspect "${HELPER_TAG}" &>/dev/null || [[ -n "${REBUILD_HELPER}" ]]; then
        echo "[brisby] Building helper image from repo (includes Brisby overrides)..."
        ( cd "${REPO_ROOT}/balena-yocto-scripts/automation" && \
          docker build -f Dockerfile_yocto-build-env -t "${HELPER_TAG}" . )
    fi
    # So balena-build.sh does not pull and overwrite our image
    export BRISBY_USE_LOCAL_HELPER=1
elif ! docker image inspect "${HELPER_TAG}" &>/dev/null; then
    echo "[brisby] Pulling builder image ${HELPER_TAG}..."
    if ! docker pull "${HELPER_TAG}" 2>/dev/null; then
        echo "[brisby] Pull failed (e.g. ghcr.io denied). Building builder image locally..."
        ( cd "${REPO_ROOT}/balena-yocto-scripts/automation" && \
          docker build -f Dockerfile_yocto-build-env -t "${HELPER_TAG}" . )
    fi
fi

cd "${REPO_ROOT}"
./balena-yocto-scripts/build/balena-build.sh \
    -d "${DEVICE_TYPE}" \
    -s "${BUILD_SPACE}" \
    -g "-t layers/meta-brisby/conf/samples -a SANITY_SKIP_CASE_INSENSITIVE_FS=1"

# Copy deploy artifacts to build space for easy access
BUILD_DIR="${REPO_ROOT}/build"
DEPLOY_DIR="${BUILD_DIR}/${DEPLOY_SUBDIR}"
if [[ -d "${DEPLOY_DIR}" ]]; then
    echo "[brisby] Copying image and artifacts to ${BUILD_SPACE}..."
    cp -v "${DEPLOY_DIR}"/balena-image-*.balenaos-img* "${BUILD_SPACE}/" 2>/dev/null || true
    cp -v "${DEPLOY_DIR}"/balena-image-*.wic* "${BUILD_SPACE}/" 2>/dev/null || true
    # Also copy overlay for reference / manual use
    if [[ -f "${DEPLOY_DIR}/jd9365da-h3.dtbo" ]]; then
        mkdir -p "${BUILD_SPACE}/overlays"
        cp -v "${DEPLOY_DIR}/jd9365da-h3.dtbo" "${BUILD_SPACE}/overlays/"
    fi
    echo ""
    echo "[brisby] Done. Flash the image from: ${BUILD_SPACE}"
    echo "[brisby] Set BALENA_HOST_CONFIG_dtoverlay to \"jd9365da-h3\" in Balena Cloud (or config.txt) so the overlay is loaded at boot."
else
    echo "[brisby] WARNING: deploy dir not found at ${DEPLOY_DIR}. Image path may differ for this device."
fi
