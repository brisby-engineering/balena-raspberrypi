# Making Sure You Flash the Custom Image

If the device shows **VERSION="6.10.22+rev1"**, **prevent-host-os-update.service inactive**, and the **old panel driver**, it is running the **stock BalenaOS image**, not your custom build.

---

## 1. Use the image from *your* build

Your custom image is produced by:

```bash
./brisby_extras/build-brisby-compute5-image.sh
```

- **On the build server** the image is in:
  - `$BRISBY_BUILD_SPACE/` (e.g. `/root/brisby_custom/` or `/Volumes/BRISBY/brisby_custom/`) — copied there by the script
  - or `build/tmp/deploy/images/raspberrypi5/` inside the repo
- **Filename pattern:** `balena-image-raspberrypi5-<timestamp>.balenaos-img` (sometimes `.gz`).
- **Do not** flash a generic "BalenaOS for raspberrypi5" download from the Balena dashboard or elsewhere; that is stock and will show 6.10.22+rev1.

**Before flashing:** Run `./brisby_extras/verify-built-image.sh` to confirm the built image contains our packages. If it reports "Manifest contains: no", fix the build (see TASK2_BUILD_CONFIG.md) before flashing.

---

## 2. Exact flash steps

### Option A: balena os configure (recommended for fleet provisioning)

```bash
# 1. Copy the custom image from build server to this machine
# 2. Use the file that came from YOUR build (see step 1)
balena os configure /path/to/balena-image-raspberrypi5-<timestamp>.balenaos-img \
  --fleet <your-fleet/slug> \
  --config-wifi-ssid "YourSSID" \
  --config-wifi-key "YourKey"
```

- This produces a configured image. Flash that output file (or the original .balenaos-img if you configure on-device later).
- If the path points to a **stock** image (e.g. downloaded from Balena), the device will boot stock.

### Option B: Etcher or balena os flash

- **Flash the same file** you would pass to `balena os configure`: the custom `balena-image-raspberrypi5-<timestamp>.balenaos-img` from your build.
- If you first run `balena os configure ...`, flash the **output** of that command (still based on your custom image).
- Do **not** select a stock BalenaOS image from the Balena website or dashboard.

---

## 3. Post-flash checklist (run on device)

Run over SSH (e.g. `balena ssh <device>` or `ssh root@<device> -p 22222`):

```bash
# === Copy-paste checklist ===

# 1) Our lock service must be present and active
systemctl is-active prevent-host-os-update.service
# Expected: active

# 2) Script must exist (if missing, image is not our build)
ls -l /usr/libexec/prevent-host-os-update.sh

# 3) OS version should NOT be stock
cat /etc/os-release | grep VERSION
# If you see 6.10.22+rev1 with no extra suffix, you are on stock.

# 4) Panel module should be the new driver
grep -a "mipi_dsi.*multi" $(modinfo -n panel-jadard-jd9365da-h3) && echo "NEW driver" || echo "OLD driver"
```

**Interpretation:**
- **prevent-host-os-update active** + **script exists** + **NEW driver** → Custom image confirmed.
- **prevent-host-os-update inactive** or **missing** + **VERSION=6.10.22+rev1** → Stock image. Re-flash using the image from **your** build.

---

## 4. Where is the panel diagnostic script? (on device)

- **Build-host “diagnose”** (checks why the *build* might produce stock image): run on your **build machine**, not on the device:
  ```bash
  ./brisby_extras/build-brisby-compute5-image.sh --diagnose
  ```
- **On-device panel check** (driver, overlay, DSI, dmesg): only present if the **custom** image is flashed. On the device it is installed at:
  ```text
  /usr/bin/check-panel-on-device.sh
  ```
  So over SSH on the device run:
  ```bash
  /usr/bin/check-panel-on-device.sh
  ```
  or (if `/usr/bin` is in PATH):
  ```bash
  check-panel-on-device.sh
  ```
- **If that file is missing** on the device, the device is almost certainly running the **stock** image (our image installs this script). Re-flash with the custom image from your build. To still run the same panel diagnostic, run it **from your Mac/laptop** and pipe it to the device:
  ```bash
  # From repo root on your machine (run against the device over SSH)
  balena ssh <device> 'sh -s' < brisby_extras/check-panel-on-device.sh
  ```
  Or with regular SSH: `ssh root@<device> -p 22222 'sh -s' < brisby_extras/check-panel-on-device.sh`

---

## 5. Quick "am I on the right image?" check

```bash
# One-liner: custom image has this script and (usually) our service enabled
test -f /usr/libexec/prevent-host-os-update.sh && echo "Likely custom image" || echo "NOT custom image - stock?"
```

If you see "NOT custom image", you are still flashing the wrong file; use the custom image from your build and try again.

---

## 6. Build script reminder

After a successful build, the script prints:

```
[brisby] Custom image to flash: /path/to/balena-image-raspberrypi5-<timestamp>.balenaos-img
```

Use that exact file for flashing. See `brisby_extras/FLASH_VERIFY.md` if the device still shows stock OS after flash.

---

## 7. Screen still not working after flash

1. **Confirm custom image is on the device** (see §5):  
   `test -f /usr/libexec/prevent-host-os-update.sh && echo custom || echo stock`  
   If "stock", re-flash with the image from your build.

2. **Run the panel diagnostic** (from device if script exists, otherwise from host):
   - On device: `/usr/bin/check-panel-on-device.sh`
   - From host: `balena ssh <device> 'sh -s' < brisby_extras/check-panel-on-device.sh`
   Check the output: driver present, module loaded, overlay in config.txt, overlay file on boot, dmesg for panel/DSI.

3. **Ensure overlay is enabled**: In Balena Cloud → Fleet → Device → Device configuration, set  
   `BALENA_HOST_CONFIG_dtoverlay` = `jd9365da-h3`  
   (or on device: add `dtoverlay=jd9365da-h3` to `/mnt/boot/config.txt` and reboot).

4. **Hardware**: Correct DSI connector and cable for your panel; panel powered; backlight if separate.

**If dmesg shows `rp1dsi_bind succeeded` but the screen stays black:**  
- The kernel and panel have bound; the usual cause is **backlight**. The overlay uses `gpio-backlight` on GPIO15. On device run the diagnostic again (it now includes section 8b Backlight). If a backlight device exists and `brightness` is 0, try:  
  `echo $(cat /sys/class/backlight/*/max_brightness) > /sys/class/backlight/*/brightness`  
  (replace `*` with the actual device name if needed).  
- On Pi5, the DSI display can be **card1** (HDMI is card0). The diagnostic now lists all DRM cards. If you need to force output to the panel, you may need to use the correct DRM device/card.
