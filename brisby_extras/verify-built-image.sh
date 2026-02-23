#!/usr/bin/env bash
#
# Task 1: Verify Built Image Contents
# Run this on the build machine after a full image build to prove the artifact
# contains our packages and new panel driver.
#
# Usage:
#   ./brisby_extras/verify-built-image.sh [DEPLOY_DIR]
#
# If DEPLOY_DIR is omitted, uses build/tmp/deploy/images/raspberrypi5/
# (relative to repo root). When building in Docker, the build dir is at
# /work/build inside the container; on the host, run from repo root.
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_DIR="${1:-}"
DEVICE_TYPE="raspberrypi5"

# Default deploy locations
if [[ -z "${DEPLOY_DIR}" ]]; then
    if [[ -d "${REPO_ROOT}/build/tmp/deploy/images/${DEVICE_TYPE}" ]]; then
        DEPLOY_DIR="${REPO_ROOT}/build/tmp/deploy/images/${DEVICE_TYPE}"
    fi
fi

if [[ -z "${DEPLOY_DIR}" ]] || [[ ! -d "${DEPLOY_DIR}" ]]; then
    echo "Usage: $0 [DEPLOY_DIR]"
    echo ""
    echo "DEPLOY_DIR not found. Specify the deploy directory, e.g.:"
    echo "  build/tmp/deploy/images/raspberrypi5/"
    exit 1
fi

echo "=== Task 1: Verify Built Image Contents ==="
echo "Deploy dir: ${DEPLOY_DIR}"
echo ""

# 1. Find manifest
MANIFEST=""
for m in "${DEPLOY_DIR}"/balena-image-*.manifest; do
    [[ -e "$m" ]] && MANIFEST="$m" && break
done

if [[ -z "${MANIFEST}" ]]; then
    echo "RESULT: No balena-image-*.manifest found in ${DEPLOY_DIR}"
    echo "Manifest contains: N/A"
    exit 1
fi

echo "Manifest: ${MANIFEST}"
echo ""

# 2. Check manifest for packages
MANIFEST_OK=1
MISSING=""
grep -q "prevent-host-os-update" "${MANIFEST}" || { MANIFEST_OK=0; MISSING="${MISSING} prevent-host-os-update"; }
grep -qE "panel-jd9365da-h3|kernel-module-panel-jadard-jd9365da-h3" "${MANIFEST}" || { MANIFEST_OK=0; MISSING="${MISSING} panel-jd9365da-h3"; }

if [[ ${MANIFEST_OK} -eq 1 ]]; then
    echo "Manifest contains: YES (prevent-host-os-update, panel-jd9365da-h3)"
else
    echo "Manifest contains: NO - missing:${MISSING}"
fi
echo ""

# 3. Optionally inspect rootfs (if .rootfs.tar or .balenaos-img available)
ROOTFS_TAR=""
for f in "${DEPLOY_DIR}"/balena-image-*.rootfs.tar; do
    [[ -e "$f" ]] && ROOTFS_TAR="$f" && break
done

ROOTFS_OK="N/A (no rootfs.tar to inspect)"
DRIVER_VER="N/A"

if [[ -n "${ROOTFS_TAR}" ]] && [[ -f "${ROOTFS_TAR}" ]]; then
    echo "Inspecting rootfs: ${ROOTFS_TAR}"
    TMPDIR=$(mktemp -d)
    trap "rm -rf ${TMPDIR}" EXIT

    # Extract and check
    tar -xf "${ROOTFS_TAR}" -C "${TMPDIR}" usr/libexec/prevent-host-os-update.sh 2>/dev/null && ROOTFS_SCRIPT=1 || ROOTFS_SCRIPT=0
    tar -xf "${ROOTFS_TAR}" -C "${TMPDIR}" lib/systemd/system/prevent-host-os-update.service 2>/dev/null && ROOTFS_SVC=1 || ROOTFS_SVC=0

    # Find panel .ko (path varies by kernel version)
    KO_PATH=$(tar -tf "${ROOTFS_TAR}" 2>/dev/null | grep -E "panel-jadard-jd9365da-h3\.ko$" | head -1)
    if [[ -n "${KO_PATH}" ]]; then
        tar -xf "${ROOTFS_TAR}" -C "${TMPDIR}" "${KO_PATH}" 2>/dev/null
        EXTRACTED_KO="${TMPDIR}/${KO_PATH}"
        if [[ -f "${EXTRACTED_KO}" ]]; then
            grep -aq "mipi_dsi" "${EXTRACTED_KO}" && grep -aq "mipi_dsi_multi" "${EXTRACTED_KO}" && DRIVER_VER="NEW (mipi_dsi_multi)" || DRIVER_VER="OLD (no mipi_dsi_multi)"
        fi
    else
        DRIVER_VER="N/A (panel .ko not found in rootfs)"
    fi

    if [[ ${ROOTFS_SCRIPT} -eq 1 ]] && [[ ${ROOTFS_SVC} -eq 1 ]]; then
        ROOTFS_OK="YES (script + service present)"
    else
        ROOTFS_OK="NO (script=${ROOTFS_SCRIPT}, service=${ROOTFS_SVC})"
    fi
fi

echo "Rootfs contains: ${ROOTFS_OK}"
echo "Driver in .ko: ${DRIVER_VER}"
echo ""
echo "=== Summary ==="
echo "Manifest contains: $([[ ${MANIFEST_OK} -eq 1 ]] && echo "yes" || echo "no")"
echo "Rootfs contains: ${ROOTFS_OK}"
echo "Driver in .ko: ${DRIVER_VER}"
