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

## 4. Quick "am I on the right image?" check

```bash
# One-liner: custom image has this script and (usually) our service enabled
test -f /usr/libexec/prevent-host-os-update.sh && echo "Likely custom image" || echo "NOT custom image - stock?"
```

If you see "NOT custom image", you are still flashing the wrong file; use the custom image from your build and try again.

---

## 5. Build script reminder

After a successful build, the script prints:

```
[brisby] Custom image to flash: /path/to/balena-image-raspberrypi5-<timestamp>.balenaos-img
```

Use that exact file for flashing. See `brisby_extras/FLASH_VERIFY.md` if the device still shows stock OS after flash.
