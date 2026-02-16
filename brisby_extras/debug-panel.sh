#!/bin/bash
# Debug script for JD9365DA-H3 panel on BalenaOS
# Run this on the Raspberry Pi device to diagnose panel issues
# SSH access: ssh root@<device-ip> -p 22222

set -e

echo "=========================================="
echo "JD9365DA-H3 Panel Debug Script (BalenaOS)"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "1. Checking overlay file on boot partition..."
if [ -f /mnt/boot/overlays/jd9365da-h3.dtbo ]; then
    check_pass "Overlay file exists: /mnt/boot/overlays/jd9365da-h3.dtbo"
    ls -lh /mnt/boot/overlays/jd9365da-h3.dtbo
else
    check_fail "Overlay file missing: /mnt/boot/overlays/jd9365da-h3.dtbo"
fi
echo ""

echo "2. Checking config.txt for overlay..."
if grep -q "dtoverlay=jd9365da-h3" /mnt/boot/config.txt; then
    check_pass "Overlay enabled in config.txt"
    echo "Found:"
    grep "dtoverlay.*jd9365da-h3" /mnt/boot/config.txt
else
    check_fail "Overlay NOT found in config.txt"
    echo ""
    echo "NOTE: In BalenaOS, config.txt is managed via BALENA_HOST_CONFIG variables."
    echo "To enable the overlay, set in Balena Cloud:"
    echo "  Variable: BALENA_HOST_CONFIG_dtoverlay"
    echo "  Value: \"jd9365da-h3\""
    echo "  (or if you have other overlays: \"vc4-kms-v3d,cma-320\",\"jd9365da-h3\")"
    echo ""
    echo "Current dtoverlay settings in config.txt:"
    grep "^dtoverlay" /mnt/boot/config.txt || echo "  (none found)"
fi
echo ""

echo "3. Checking kernel module file..."
if [ -f /usr/lib/panel/panel-jadard-jd9365da-h3.ko ]; then
    check_pass "Kernel module file exists"
    ls -lh /usr/lib/panel/panel-jadard-jd9365da-h3.ko
else
    check_fail "Kernel module file missing: /usr/lib/panel/panel-jadard-jd9365da-h3.ko"
fi
echo ""

echo "4. Checking if kernel module is loaded..."
if lsmod | grep -q "panel_jadard"; then
    check_pass "Kernel module is loaded"
    lsmod | grep panel_jadard
else
    check_fail "Kernel module is NOT loaded"
    echo "Try loading manually:"
    echo "  sudo insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko"
fi
echo ""

echo "5. Checking panel-module-load service..."
if systemctl is-enabled panel-module-load.service >/dev/null 2>&1; then
    check_pass "panel-module-load service is enabled"
else
    check_warn "panel-module-load service is not enabled"
fi

if systemctl is-active panel-module-load.service >/dev/null 2>&1; then
    check_pass "panel-module-load service is active"
else
    check_fail "panel-module-load service is not active"
fi

echo "Service status:"
systemctl status panel-module-load.service --no-pager -l || true

echo "Service boot order (should run before balena-supervisor):"
systemctl list-dependencies panel-module-load.service --reverse --no-pager | head -10 || true
echo ""

echo "6. Checking device tree for panel node..."
if [ -d /sys/firmware/devicetree/base ]; then
    # Check for panel node in device tree
    if find /sys/firmware/devicetree/base -name "*panel*" -o -name "*txw990002b0*" -o -name "*jd9365da*" 2>/dev/null | grep -q .; then
        check_pass "Panel-related nodes found in device tree"
        echo "Found nodes:"
        find /sys/firmware/devicetree/base -name "*panel*" -o -name "*txw990002b0*" -o -name "*jd9365da*" 2>/dev/null | head -10
    else
        check_fail "No panel nodes found in device tree"
        echo "This suggests the overlay is not being applied"
    fi
    
    # Check for compatible string
    if grep -r "cw,txw990002b0" /sys/firmware/devicetree/base 2>/dev/null | head -1 | grep -q .; then
        check_pass "Panel compatible string 'cw,txw990002b0' found in device tree"
    else
        check_fail "Panel compatible string 'cw,txw990002b0' NOT found in device tree"
    fi
else
    check_warn "Cannot access /sys/firmware/devicetree/base (may need root)"
fi
echo ""

echo "7. Checking DSI interface..."
if [ -d /sys/bus/platform/drivers/rp1-dsi ]; then
    check_pass "RP1 DSI driver directory exists"
    echo "DSI devices:"
    ls -la /sys/bus/platform/drivers/rp1-dsi/ 2>/dev/null || echo "  (no devices bound)"
else
    check_warn "RP1 DSI driver directory not found"
fi
echo ""

echo "8. Checking for DSI devices in sysfs..."
if find /sys/devices -name "*dsi*" -o -name "*mipi*" 2>/dev/null | grep -q .; then
    check_pass "DSI/MIPI devices found"
    echo "Found:"
    find /sys/devices -name "*dsi*" -o -name "*mipi*" 2>/dev/null | head -5
else
    check_warn "No DSI/MIPI devices found in sysfs"
fi
echo ""

echo "9. Checking GPIO pins (GPIO14 for reset, GPIO15 for backlight)..."
if [ -d /sys/class/gpio ]; then
    # Note: GPIO numbers may need to be calculated based on RP1 GPIO mapping
    check_warn "GPIO sysfs exists (may need to check RP1 GPIO mapping)"
    echo "RP1 GPIO info:"
    ls -la /sys/class/gpio/ 2>/dev/null | head -10 || echo "  (may need root access)"
else
    check_warn "GPIO sysfs not accessible"
fi
echo ""

echo "10. Checking regulators..."
if [ -d /sys/class/regulator ]; then
    if find /sys/class/regulator -name "*panel*" 2>/dev/null | grep -q .; then
        check_pass "Panel regulators found"
        echo "Found:"
        find /sys/class/regulator -name "*panel*" 2>/dev/null
    else
        check_warn "No panel regulators found (may be normal if not probed)"
    fi
else
    check_warn "Regulator sysfs not accessible"
fi
echo ""

echo "11. Checking DRM/KMS devices..."
if [ -d /sys/class/drm ]; then
    check_pass "DRM class exists"
    echo "DRM devices:"
    ls -la /sys/class/drm/ | grep -E "^d" | awk '{print $9, $10, $11}'
    
    # Check for DSI connector
    if ls /sys/class/drm/card*/status 2>/dev/null | grep -q .; then
        echo "Display connectors:"
        for status in /sys/class/drm/card*/status; do
            connector=$(dirname "$status")
            echo "  $(basename $connector): $(cat $status 2>/dev/null || echo 'unknown')"
        done
    fi
else
    check_fail "DRM class not found"
fi
echo ""

echo "12. Checking dmesg for panel-related messages..."
echo "Recent panel-related kernel messages:"
dmesg | grep -iE "(panel|jadard|jd9365da|txw990002b0|dsi|mipi)" | tail -20 || echo "  (no messages found)"
echo ""

echo "13. Checking dmesg for errors..."
echo "Recent errors/warnings:"
dmesg | grep -iE "(error|fail|warn)" | grep -iE "(panel|dsi|mipi|jadard)" | tail -10 || echo "  (no relevant errors found)"
echo ""

echo "14. Checking if panel appears in /proc/device-tree..."
if [ -d /proc/device-tree ]; then
    if find /proc/device-tree -name "*panel*" -o -name "*txw990002b0*" 2>/dev/null | grep -q .; then
        check_pass "Panel found in /proc/device-tree"
        echo "Found:"
        find /proc/device-tree -name "*panel*" -o -name "*txw990002b0*" 2>/dev/null | head -5
    else
        check_fail "Panel NOT found in /proc/device-tree"
    fi
else
    check_warn "/proc/device-tree not accessible"
fi
echo ""

echo "15. Checking VC4/KMS status..."
if dmesg | grep -q "vc4"; then
    check_pass "VC4 driver messages found in dmesg"
    echo "VC4 related messages:"
    dmesg | grep -i vc4 | tail -5
else
    check_warn "No VC4 messages found"
fi
echo ""

echo "16. Checking Balena configuration..."
echo "Checking for BALENA_HOST_CONFIG variables (if accessible):"
if [ -d /mnt/boot/config.json ] || [ -f /mnt/boot/config.json ]; then
    check_warn "config.json found (Balena uses this for some config)"
fi

# Check if we can see supervisor environment
if [ -f /etc/balena-supervisor/balena-supervisor.conf ] || [ -d /var/lib/balena ]; then
    check_pass "Balena supervisor detected"
else
    check_warn "Balena supervisor not detected (may be normal in some setups)"
fi
echo ""

echo "=========================================="
echo "Summary and Recommendations (BalenaOS)"
echo "=========================================="
echo ""
echo "If the panel is still not working, check:"
echo ""
echo "1. OVERLAY CONFIGURATION (Balena Cloud):"
echo "   - Go to Fleet/Device → Configuration"
echo "   - Set BALENA_HOST_CONFIG_dtoverlay = \"jd9365da-h3\""
echo "   - Or combine with existing: \"vc4-kms-v3d,cma-320\",\"jd9365da-h3\""
echo "   - Reboot device after setting"
echo ""
echo "2. OVERLAY FILE:"
echo "   - Ensure /mnt/boot/overlays/jd9365da-h3.dtbo exists"
echo "   - If missing, copy from build or deploy directory"
echo ""
echo "3. KERNEL MODULE:"
echo "   - Check if loaded: lsmod | grep panel_jadard"
echo "   - If not loaded, check service: systemctl status panel-module-load.service"
echo "   - Try manual load: insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko"
echo ""
echo "4. BOOT ORDER:"
echo "   - panel-module-load.service should run BEFORE balena-supervisor.service"
echo "   - Check: systemctl list-dependencies panel-module-load.service"
echo ""
echo "5. KERNEL MESSAGES:"
echo "   - Check dmesg for errors: dmesg | grep -iE '(panel|jadard|dsi|error)'"
echo "   - Look for probe failures or GPIO/regulator errors"
echo ""
echo "6. HARDWARE:"
echo "   - Verify GPIO14 (reset) and GPIO15 (backlight) connections"
echo "   - Check power/regulators are working"
echo ""
echo "7. DEVICE TREE:"
echo "   - Verify overlay is applied: find /proc/device-tree -name '*panel*'"
echo "   - Check compatible string: grep -r 'cw,txw990002b0' /proc/device-tree/"
echo ""
echo "For more details, see: brisby_extras/DEBUGGING_PANEL.md"
echo ""
