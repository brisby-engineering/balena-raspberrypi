#!/bin/bash
# Script to add jd9365da-h3.dtbo overlay to boot partition
# Run this on the Raspberry Pi device

set -e

OVERLAY_SOURCE="/tmp/jd9365da-h3-overlay.dts"
OVERLAY_BINARY="/tmp/jd9365da-h3.dtbo"
BOOT_OVERLAY_DIR="/mnt/boot/overlays"
BOOT_OVERLAY_FILE="${BOOT_OVERLAY_DIR}/jd9365da-h3.dtbo"

echo "=========================================="
echo "Adding JD9365DA-H3 Overlay to Boot Partition"
echo "=========================================="
echo ""

# Check if overlay already exists
if [ -f "${BOOT_OVERLAY_FILE}" ]; then
    echo "✓ Overlay already exists: ${BOOT_OVERLAY_FILE}"
    ls -lh "${BOOT_OVERLAY_FILE}"
    exit 0
fi

# Method 1: Try to compile from source if dtc is available
if command -v dtc >/dev/null 2>&1; then
    echo "Method 1: Compiling overlay from source..."
    
    if [ ! -f "${OVERLAY_SOURCE}" ]; then
        echo "✗ Source file not found: ${OVERLAY_SOURCE}"
        echo ""
        echo "Please copy jd9365da-h3-overlay.dts to ${OVERLAY_SOURCE}"
        echo "Or use Method 2 to copy pre-compiled overlay"
        echo ""
        read -p "Do you have the .dts source file? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping compilation. Use Method 2 instead."
        else
            exit 1
        fi
    else
        echo "Compiling ${OVERLAY_SOURCE}..."
        dtc -@ -I dts -O dtb -o "${OVERLAY_BINARY}" "${OVERLAY_SOURCE}"
        
        if [ -f "${OVERLAY_BINARY}" ]; then
            echo "✓ Compiled successfully: ${OVERLAY_BINARY}"
            METHOD="compile"
        else
            echo "✗ Compilation failed"
            exit 1
        fi
    fi
else
    echo "Method 1: dtc not available, skipping compilation"
    METHOD="copy"
fi

# Method 2: Copy pre-compiled overlay
if [ "${METHOD}" != "compile" ]; then
    echo ""
    echo "Method 2: Copying pre-compiled overlay..."
    
    if [ ! -f "${OVERLAY_BINARY}" ]; then
        echo "✗ Pre-compiled overlay not found: ${OVERLAY_BINARY}"
        echo ""
        echo "Please copy jd9365da-h3.dtbo to ${OVERLAY_BINARY}"
        echo ""
        echo "You can get the overlay from:"
        echo "  1. Your build system: build/tmp/deploy/images/raspberrypi5/jd9365da-h3.dtbo"
        echo "  2. Or compile it on your build machine:"
        echo "     dtc -@ -I dts -O dtb -o jd9365da-h3.dtbo jd9365da-h3-overlay.dts"
        echo ""
        read -p "Do you have the .dtbo file ready? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

# Install overlay to boot partition
echo ""
echo "Installing overlay to boot partition..."

# Ensure overlays directory exists
if [ ! -d "${BOOT_OVERLAY_DIR}" ]; then
    echo "Creating overlays directory: ${BOOT_OVERLAY_DIR}"
    mkdir -p "${BOOT_OVERLAY_DIR}"
fi

# Copy overlay
echo "Copying ${OVERLAY_BINARY} to ${BOOT_OVERLAY_FILE}..."
cp "${OVERLAY_BINARY}" "${BOOT_OVERLAY_FILE}"

# Verify
if [ -f "${BOOT_OVERLAY_FILE}" ]; then
    echo "✓ Overlay installed successfully!"
    echo ""
    echo "File details:"
    ls -lh "${BOOT_OVERLAY_FILE}"
    echo ""
    echo "Next steps:"
    echo "1. Set BALENA_HOST_CONFIG_dtoverlay = \"jd9365da-h3\" in Balena Cloud"
    echo "2. Reboot the device"
    echo ""
    echo "To verify after reboot:"
    echo "  grep dtoverlay /mnt/boot/config.txt"
else
    echo "✗ Failed to install overlay"
    exit 1
fi
