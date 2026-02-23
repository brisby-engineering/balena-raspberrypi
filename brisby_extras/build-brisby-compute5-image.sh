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
    echo "  --clean-config         Remove build/conf so next build uses meta-brisby template (fixes stock image)"
    echo "  --cleansstate-kernel   Run only 'bitbake -c cleansstate linux-raspberrypi' (fix pseudo/inode errors), then exit"
    echo "  --cleansstate-panel    Clean sstate cache for panel-jd9365da-h3 to force rebuild with new driver"
    echo "  --rebuild-helper       Rebuild the Docker helper image (use if you see groupadd GID errors)"
    echo "  --diagnose             Check why build might produce stock image (template, bblayers, paths); then exit"
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
CLEAN_CONFIG=""
DIAGNOSE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)             DRY_RUN="1"; shift ;;
        -r|--refresh)             REFRESH_SOURCES="1"; shift ;;
        --clean-config)           CLEAN_CONFIG="1"; shift ;;
        --cleansstate-kernel)     CLEANSTATE_KERNEL="1"; shift ;;
        --cleansstate-panel)      CLEANSTATE_PANEL="1"; shift ;;
        --rebuild-helper)         REBUILD_HELPER="1"; shift ;;
        --diagnose)               DIAGNOSE="1"; shift ;;
        -h|--help)                usage ;;
        *)                        echo "Unknown option: $1"; usage ;;
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

# Optional: clean build config (fixes stock image when meta-brisby was not in bblayers).
# Yocto uses REPO_ROOT/build; we also clean BUILD_SPACE/build/conf if present.
if [[ -n "${CLEAN_CONFIG}" ]]; then
    echo "[brisby] Cleaning build config..."
    for conf_dir in "${REPO_ROOT}/build/conf" "${BUILD_SPACE}/build/conf"; do
        if [[ -d "${conf_dir}" ]]; then
            rm -rf "${conf_dir}"
            echo "[brisby] Removed ${conf_dir}"
        fi
    done
    echo "[brisby] Config cleaned. Re-run without --clean-config to build:"
    echo "[brisby]   $0"
    exit 0
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
if [[ ! -f "${META_BRISBY}/conf/samples/bblayers.conf.sample" ]]; then
    echo "[brisby] ERROR: meta-brisby template not found at ${META_BRISBY}/conf/samples/. Need bblayers.conf.sample."
    exit 1
fi

# Critical: if build/conf exists but doesn't include meta-brisby, we will build stock. Fail early.
# Note: Yocto build dir is always REPO_ROOT/build (balena-build.sh -s only provides shared-downloads/sstate).
BUILD_CONF_REPO="${REPO_ROOT}/build/conf/bblayers.conf"
BUILD_CONF_SPACE="${BUILD_SPACE}/build/conf/bblayers.conf"
for BUILD_CONF in "${BUILD_CONF_REPO}" "${BUILD_CONF_SPACE}"; do
    if [[ -f "${BUILD_CONF}" ]]; then
        if ! grep -q "meta-brisby" "${BUILD_CONF}"; then
            echo "[brisby] ERROR: bblayers.conf exists but does NOT include meta-brisby: ${BUILD_CONF}"
            echo "[brisby] The build would produce a stock image (no panel, no prevent-host-os-update)."
            echo "[brisby] Fix: run with --clean-config then build (no options):"
            echo "  $0 --clean-config"
            echo "  $0"
            exit 1
        fi
    fi
done

if [[ -n "${DIAGNOSE}" ]]; then
    echo "[brisby] === Diagnose: why build might produce stock image ==="
    echo "[brisby] Repo root:        ${REPO_ROOT}"
    echo "[brisby] Build space:      ${BUILD_SPACE}"
    echo "[brisby] Yocto build dir:  ${REPO_ROOT}/build (used by barys in container)"
    echo "[brisby] Deploy dir:       ${REPO_ROOT}/build/${DEPLOY_SUBDIR}"
    echo ""
    TEMPLATE_DIR="${REPO_ROOT}/layers/meta-brisby/conf/samples"
    if [[ -f "${TEMPLATE_DIR}/bblayers.conf.sample" ]]; then
        echo "[brisby] Template: ${TEMPLATE_DIR}/bblayers.conf.sample exists."
        if grep -q "meta-brisby" "${TEMPLATE_DIR}/bblayers.conf.sample"; then
            echo "[brisby]   Template includes meta-brisby in BBLAYERS."
        else
            echo "[brisby]   WARNING: template does NOT include meta-brisby."
        fi
    else
        echo "[brisby] WARNING: Template not found at ${TEMPLATE_DIR}/bblayers.conf.sample"
        echo "[brisby]   Container resolves -t layers/meta-brisby/conf/samples to this path."
    fi
    echo ""
    if [[ -f "${BUILD_CONF_REPO}" ]]; then
        echo "[brisby] Current build/conf: ${BUILD_CONF_REPO} exists."
        if grep -q "meta-brisby" "${BUILD_CONF_REPO}"; then
            echo "[brisby]   bblayers.conf includes meta-brisby (next build should be custom)."
        else
            echo "[brisby]   bblayers.conf does NOT include meta-brisby -> stock image. Run --clean-config then build."
        fi
    else
        echo "[brisby] No build/conf yet; next build will create it from template (good if template is meta-brisby)."
    fi
    echo ""
    echo "[brisby] Other possibilities if clean build still gives stock image:"
    echo "[brisby]   - meta-brisby missing on build host (different clone/worktree)"
    echo "[brisby]   - Template path (-t) not passed into container (check -g in script)"
    echo "[brisby]   - Build ran from different repo than this script (REPO_ROOT vs /work in Docker)"
    echo "[brisby] See: brisby_extras/TROUBLESHOOT_STOCK_IMAGE.md"
    exit 0
fi

if [[ ! -f "${REPO_ROOT}/balena-yocto-scripts/build/balena-build.sh" ]]; then
    echo "[brisby] ERROR: balena-build.sh not found. Run from balena-raspberrypi repo root."
    exit 1
fi

# Apply overrides from brisby_extras/overrides/ onto submodules (no need to push to other repos)
# This way only the fork needs to be cloned; balena-yocto-scripts, poky, meta-balena-raspberrypi stay upstream.
if [[ -d "${BRISBY_EXTRAS}/overrides" ]]; then
    echo "[brisby] Applying overrides (balena-yocto-scripts, poky, meta-balena-raspberrypi)..."
    [[ -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/entry_scripts/prepare-and-start.sh" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/entry_scripts/prepare-and-start.sh" \
              "${REPO_ROOT}/balena-yocto-scripts/automation/entry_scripts/"
    [[ -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/include/balena-lib.inc" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/balena-yocto-scripts/automation/include/balena-lib.inc" \
              "${REPO_ROOT}/balena-yocto-scripts/automation/include/"
    [[ -f "${BRISBY_EXTRAS}/overrides/poky/meta/classes/sanity.bbclass" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/poky/meta/classes/sanity.bbclass" \
              "${REPO_ROOT}/layers/poky/meta/classes/"
    # meta-balena-raspberrypi: enable console=tty1 and firmware splash for raspberrypi5 (DSI boot text/splash)
    [[ -f "${BRISBY_EXTRAS}/overrides/meta-balena-raspberrypi/recipes-bsp/bootfiles/rpi-cmdline.bbappend" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/meta-balena-raspberrypi/recipes-bsp/bootfiles/rpi-cmdline.bbappend" \
              "${REPO_ROOT}/layers/meta-balena-raspberrypi/recipes-bsp/bootfiles/"
    [[ -f "${BRISBY_EXTRAS}/overrides/meta-balena-raspberrypi/recipes-bsp/bootfiles/rpi-config_git.bbappend" ]] && \
        cp -f "${BRISBY_EXTRAS}/overrides/meta-balena-raspberrypi/recipes-bsp/bootfiles/rpi-config_git.bbappend" \
              "${REPO_ROOT}/layers/meta-balena-raspberrypi/recipes-bsp/bootfiles/"
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

    # Verify the built image manifest contains our packages (proof we did not build stock).
    # Use newest manifest by mtime so we check the image we just built (deploy dir may have older files).
    BRISBY_MANIFEST=""
    for m in "${DEPLOY_DIR}"/balena-image-*.manifest; do
        [[ -e "$m" ]] || continue
        if [[ -z "${BRISBY_MANIFEST}" ]] || [[ "$m" -nt "${BRISBY_MANIFEST}" ]]; then
            BRISBY_MANIFEST="$m"
        fi
    done
    if [[ -n "${BRISBY_MANIFEST}" ]] && [[ -f "${BRISBY_MANIFEST}" ]]; then
        MISSING=""
        grep -q "prevent-host-os-update" "${BRISBY_MANIFEST}" || MISSING="${MISSING} prevent-host-os-update"
        grep -qE "panel-jd9365da-h3|kernel-module-panel-jadard-jd9365da-h3" "${BRISBY_MANIFEST}" || MISSING="${MISSING} panel-jd9365da-h3"
        if [[ -n "${MISSING}" ]]; then
            echo "[brisby] WARNING: image manifest missing expected packages:${MISSING}"
            echo "[brisby] Checked: ${BRISBY_MANIFEST}"
            echo "[brisby] DO NOT FLASH - this is a stock image. Run with --clean-config then rebuild:"
            echo "[brisby]   $0 --clean-config"
            echo "[brisby]   $0"
            echo "[brisby] If that still fails, run $0 --diagnose and see brisby_extras/TROUBLESHOOT_STOCK_IMAGE.md"
        else
            echo "[brisby] Verified: image manifest contains prevent-host-os-update and panel packages."
        fi
    else
        echo "[brisby] Note: no balena-image-*.manifest found in ${DEPLOY_DIR}; skipping package verification."
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
