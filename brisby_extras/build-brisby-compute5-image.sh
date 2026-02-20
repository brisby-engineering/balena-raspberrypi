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
    echo "  -n, --dry-run           Only prepare build space and meta-brisby; do not run build"
    echo "  -r, --refresh           Refresh panel/overlay sources from brisby_extras into meta-brisby"
    echo "  --cleansstate-kernel   Run only 'bitbake -c cleansstate linux-raspberrypi' (fix pseudo/inode errors), then exit"
    echo "  --cleansstate-panel    Clean sstate cache for panel-jd9365da-h3 to force rebuild with new driver"
    echo "  --clean-conf           Pre-cleanup: always remove build/conf so template is re-applied (guarantees meta-brisby)"
    echo "  --rebuild-helper       Rebuild the Docker helper image (use if you see groupadd GID errors)"
    echo "  -h, --help             Show this help"
    echo ""
    echo "Output: image and artifacts in ${BUILD_SPACE}/"
    echo ""
    echo "On Linux/cloud (e.g. DigitalOcean): export BRISBY_BUILD_SPACE=\$HOME/brisby_custom"
    exit 0
}

REFRESH_SOURCES=""
DRY_RUN=""
REBUILD_HELPER=""
CLEANSTATE_KERNEL=""
CLEANSTATE_PANEL=""
CLEAN_CONF=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)             DRY_RUN="1"; shift ;;
        -r|--refresh)             REFRESH_SOURCES="1"; shift ;;
        --cleansstate-kernel)     CLEANSTATE_KERNEL="1"; shift ;;
        --cleansstate-panel)      CLEANSTATE_PANEL="1"; shift ;;
        --clean-conf)             CLEAN_CONF="1"; shift ;;
        --rebuild-helper)         REBUILD_HELPER="1"; shift ;;
        -h|--help)                usage ;;
        *)                        echo "Unknown option: $1"; usage ;;
    esac
done

echo "[brisby] Repo root: ${REPO_ROOT}"
echo "[brisby] Build space: ${BUILD_SPACE}"
echo ""

# --- Pre-cleanup: ensure the system is ready for building ---
echo "[brisby] Pre-cleanup: ensuring build environment is ready..."

# Ensure build space exists (for shared-downloads, sstate, and artifact copy)
if [[ ! -d "${BUILD_SPACE}" ]]; then
    echo "[brisby] Creating build space: ${BUILD_SPACE}"
    mkdir -p "${BUILD_SPACE}"
fi

# Optional: refresh panel and overlay sources from brisby_extras into meta-brisby.
# Canonical source for bare metal is casco-web (deploy-overlay.sh / deploy-panel-module.sh).
# This copies overlay .dts and panel .c only; do NOT copy the casco-web Makefile (recipe uses Yocto KERNEL_DIR).
if [[ -n "${REFRESH_SOURCES}" ]]; then
    echo "[brisby] Refreshing panel and overlay sources from brisby_extras..."
    cp -f "${BRISBY_EXTRAS}/panel-jadard-jd9365da-h3.c" \
          "${META_BRISBY}/recipes-kernel/panel-jd9365da/files/"
    cp -f "${BRISBY_EXTRAS}/jd9365da-h3-overlay.dts" \
          "${META_BRISBY}/recipes-bsp/jd9365da-overlay/files/"
    echo "[brisby] Sources updated."
fi

# Sanity checks: meta-brisby layer and template must exist
if [[ ! -f "${META_BRISBY}/conf/layer.conf" ]]; then
    echo "[brisby] ERROR: meta-brisby layer not found at ${META_BRISBY}. Run from balena-raspberrypi repo root."
    exit 1
fi
if [[ ! -f "${META_BRISBY}/conf/samples/bblayers.conf.sample" ]]; then
    echo "[brisby] ERROR: meta-brisby template not found at ${META_BRISBY}/conf/samples/. Need bblayers.conf.sample."
    exit 1
fi
if [[ ! -f "${REPO_ROOT}/balena-yocto-scripts/build/balena-build.sh" ]]; then
    echo "[brisby] ERROR: balena-build.sh not found. Run from balena-raspberrypi repo root."
    exit 1
fi

# Ensure build/conf will use meta-brisby template. Yocto only copies the template when conf is first created.
# Remove build/conf if: (1) user asked --clean-conf, or (2) conf exists but doesn't list meta-brisby (stale stock conf).
BUILD_CONF="${REPO_ROOT}/build/conf/bblayers.conf"
if [[ -n "${CLEAN_CONF}" ]]; then
    if [[ -d "${REPO_ROOT}/build/conf" ]]; then
        echo "[brisby] Removing build/conf (--clean-conf)."
        rm -rf "${REPO_ROOT}/build/conf"
    fi
elif [[ -f "${BUILD_CONF}" ]]; then
    if ! grep -q "meta-brisby" "${BUILD_CONF}"; then
        echo "[brisby] Removing stale build/conf (missing meta-brisby; would produce stock image)."
        rm -rf "${REPO_ROOT}/build/conf"
    fi
fi

echo "[brisby] Pre-cleanup done."
echo ""

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

# When host is root, the container runs as builder 1000:1000; chown repo and build space so builder can write to /work
if [ "$(id -u)" = "0" ]; then
    echo "[brisby] Running as root; chown repo and build space to 1000:1000 so container builder can write..."
    # Add repo to git safe.directory so git commands work after chown (git security check)
    git config --global --add safe.directory "${REPO_ROOT}" 2>/dev/null || true
    chown -R 1000:1000 "${REPO_ROOT}" "${BUILD_SPACE}"
fi

cd "${REPO_ROOT}"
if [[ -n "${CLEANSTATE_KERNEL}" ]]; then
    echo "[brisby] Running only: bitbake -c cleansstate linux-raspberrypi (to fix pseudo/inode path mismatch)"
    ./balena-yocto-scripts/build/balena-build.sh \
        -d "${DEVICE_TYPE}" \
        -s "${BUILD_SPACE}" \
        -g "-t layers/meta-brisby/conf/samples -a SANITY_SKIP_CASE_INSENSITIVE_FS=1" \
        -i "linux-raspberrypi" \
        -b "-c cleansstate"
    echo "[brisby] Done. Re-run without --cleansstate-kernel to do the full image build."
    exit 0
fi

if [[ -n "${CLEANSTATE_PANEL}" ]]; then
    echo "[brisby] Running only: bitbake -c cleansstate panel-jd9365da-h3 (to force rebuild with new driver)"
    ./balena-yocto-scripts/build/balena-build.sh \
        -d "${DEVICE_TYPE}" \
        -s "${BUILD_SPACE}" \
        -g "-t layers/meta-brisby/conf/samples -a SANITY_SKIP_CASE_INSENSITIVE_FS=1" \
        -i "panel-jd9365da-h3" \
        -b "-c cleansstate"
    echo "[brisby] Done. Re-run without --cleansstate-panel to do the full image build."
    exit 0
fi
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

    # Verify the built image manifest contains our packages (proof we did not build stock)
    BRISBY_MANIFEST=""
    for m in "${DEPLOY_DIR}"/balena-image-*.manifest; do
        [[ -e "$m" ]] && BRISBY_MANIFEST="$m" && break
    done
    if [[ -n "${BRISBY_MANIFEST}" ]]; then
        MISSING=""
        grep -q "prevent-host-os-update" "${BRISBY_MANIFEST}" || MISSING="${MISSING} prevent-host-os-update"
        grep -qE "panel-jd9365da-h3|kernel-module-panel-jadard-jd9365da-h3" "${BRISBY_MANIFEST}" || MISSING="${MISSING} panel-jd9365da-h3"
        if [[ -n "${MISSING}" ]]; then
            echo "[brisby] WARNING: image manifest missing expected packages:${MISSING}"
            echo "[brisby] DO NOT FLASH - this is a stock image."
            echo "[brisby] Fix: rm -rf build/conf && $0   (script will re-create conf from meta-brisby template)"
        else
            echo "[brisby] Verified: image manifest contains prevent-host-os-update and panel packages."
        fi
    else
        echo "[brisby] Note: no .manifest found in deploy dir; skipping package verification."
    fi

    echo ""
    echo "[brisby] Done. Flash the image from: ${BUILD_SPACE}"
    echo "[brisby] Set BALENA_HOST_CONFIG_dtoverlay to \"jd9365da-h3\" in Balena Cloud (or config.txt) so the overlay is loaded at boot."
    # Remind which file is the custom image (use newest by mtime, not arbitrary glob order)
    LATEST_IMG=$(ls -t "${BUILD_SPACE}"/balena-image-*.balenaos-img* 2>/dev/null | head -1)
    [[ -n "${LATEST_IMG}" ]] && echo "[brisby] Custom image to flash: ${LATEST_IMG}"
    echo "[brisby] See brisby_extras/FLASH_VERIFY.md if the device still shows stock OS after flash."
else
    echo "[brisby] WARNING: deploy dir not found at ${DEPLOY_DIR}. Image path may differ for this device."
fi
