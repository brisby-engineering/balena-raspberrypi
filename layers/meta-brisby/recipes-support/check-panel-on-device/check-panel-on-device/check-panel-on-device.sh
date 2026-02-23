#!/bin/sh
# Run on device (balena ssh <device> or ssh root@<device> -p 22222)
# Comprehensive panel diagnostic: driver, overlay, device tree, DSI, DRM, dmesg.

echo "=============================================="
echo "  Panel diagnostic (JD9365DA-H3 / TXW990002B0)"
echo "=============================================="
echo ""

# --- 1. Driver file ---
KO_PATH=$(modinfo -n panel-jadard-jd9365da-h3 2>/dev/null)
echo "1. Driver file:"
if [ -n "$KO_PATH" ]; then
    echo "   Path: $KO_PATH"
    [ -f "$KO_PATH" ] && echo "   [OK] exists" || echo "   [FAIL] missing"
else
    echo "   [FAIL] modinfo could not find panel-jadard-jd9365da-h3"
fi
echo ""

# --- 2. Driver loaded ---
echo "2. Module loaded:"
if lsmod 2>/dev/null | grep -q panel_jadard; then
    echo "   [OK]"
    lsmod | grep panel_jadard
else
    echo "   [NO]"
fi
echo ""

# --- 3. Driver variant ---
echo "3. Driver variant:"
if [ -n "$KO_PATH" ] && [ -f "$KO_PATH" ]; then
    if grep -aq "mipi_dsi_multi" "$KO_PATH" 2>/dev/null; then
        echo "   NEW (mipi_dsi_multi) - required for Pi5 RP1 DSI"
    else
        echo "   OLD (legacy DSI API) - may not probe on Pi5 RP1 DSI"
    fi
else
    echo "   [N/A]"
fi
echo ""

# --- 4. Overlay in config.txt ---
echo "4. Overlay (config.txt):"
BOOT_CFG="/mnt/boot/config.txt"
if [ -f "$BOOT_CFG" ]; then
    grep -E "dtoverlay|dtparam" "$BOOT_CFG" 2>/dev/null | grep -v "^#" || echo "   (no overlays)"
    if grep -q "jd9365da-h3" "$BOOT_CFG" 2>/dev/null; then
        echo "   [OK] jd9365da-h3 overlay present"
    else
        echo "   [MISSING] jd9365da-h3 overlay - add: dtoverlay=jd9365da-h3"
    fi
else
    echo "   [N/A] $BOOT_CFG not found (check /mnt/boot or /boot)"
fi
echo ""

# --- 5. Overlay file on boot partition ---
echo "5. Overlay file on boot:"
for d in /mnt/boot /boot; do
    [ -f "$d/overlays/jd9365da-h3.dtbo" ] && echo "   [OK] $d/overlays/jd9365da-h3.dtbo" && break
done
[ ! -f "/mnt/boot/overlays/jd9365da-h3.dtbo" ] && [ ! -f "/boot/overlays/jd9365da-h3.dtbo" ] && echo "   [MISSING] jd9365da-h3.dtbo"
echo ""

# --- 6. Device tree - panel node ---
echo "6. Device tree (panel / txw990002b0):"
find /proc/device-tree -type d -name "*panel*" 2>/dev/null | head -5
find /proc/device-tree -type d -name "*txw990002b0*" 2>/dev/null | head -5
if find /proc/device-tree -type f -name "compatible" -exec grep -l "cw,txw990002b0" {} \; 2>/dev/null | head -1 | grep -q .; then
    echo "   [OK] panel node with cw,txw990002b0 found"
else
    echo "   [MISSING?] no panel node with cw,txw990002b0 - overlay may not be loaded"
fi
echo ""

# --- 7. RP1 DSI host ---
echo "7. RP1 DSI (Pi5):"
ls -la /sys/bus/platform/drivers/rp1-dsi/ 2>/dev/null || echo "   (rp1-dsi driver not found)"
ls -la /sys/bus/platform/devices/*dsi* 2>/dev/null | head -5
echo ""

# --- 8. DRM / KMS ---
echo "8. DRM connectors (card0):"
for c in /sys/class/drm/card0-*; do
    [ -d "$c" ] && [ -f "$c/status" ] && echo "   $(basename $c): $(cat $c/status 2>/dev/null)"
done 2>/dev/null
echo ""

# --- 9. panel-module-load service ---
echo "9. panel-module-load.service:"
systemctl is-active panel-module-load.service 2>/dev/null || echo "   inactive/missing"
systemctl is-enabled panel-module-load.service 2>/dev/null || true
echo "   Journal (last 20 lines):"
journalctl -u panel-module-load.service -n 20 --no-pager 2>/dev/null || echo "   (no journal)"
echo ""

# --- 10. Boot order (panel before DSI?) ---
echo "10. Service order (panel-module-load vs balena-supervisor):"
systemctl list-dependencies panel-module-load.service 2>/dev/null | head -15
echo ""

# --- 11. All dmesg for panel/DSI ---
echo "11. dmesg (panel|jadard|jd9365da|dsi|mipi|rp1|txw990002b0):"
dmesg 2>/dev/null | grep -iE "panel|jadard|jd9365da|dsi|mipi|rp1_dsi|txw990002b0" || echo "   (none)"
echo ""

# --- 12. Panel-related errors ---
echo "12. dmesg errors (panel/DSI only):"
dmesg 2>/dev/null | grep -iE "panel|jadard|jd9365da|dsi|mipi|rp1" | grep -iE "error|fail|warn" || echo "   (none)"
echo ""

# --- 13. modprobe / probe ---
echo "13. Module dependencies:"
modinfo panel-jadard-jd9365da-h3 2>/dev/null | grep -E "depends|alias|parm"
echo ""

echo "=============================================="
echo "  Done"
echo "=============================================="
