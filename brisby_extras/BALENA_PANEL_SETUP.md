# Quick Setup Guide: JD9365DA-H3 Panel on BalenaOS

## Prerequisites

- Raspberry Pi 5 or Compute Module 5 running BalenaOS
- Panel kernel module and overlay included in your custom image
- SSH access to device (port 22222)

## Step 1: Verify Overlay File

### Connecting to Your Balena Device

Balena devices can be accessed via SSH in several ways:

#### Option 1: Using Balena CLI (Recommended)
```bash
# SSH into device (uses mDNS or IP automatically)
balena ssh eb5ef0a

# Or if device is on local network:
balena ssh <hostname>.local
```

#### Option 2: Using Standard SSH
```bash
# Using device IP address
ssh root@<device-ip> -p 22222

# Using mDNS hostname (if on local network)
ssh root@<hostname>.local -p 22222
```

**Note**: Balena devices use port **22222** for SSH (not 22). For copying files, use **`scp -P 22222`** — there is no `balena scp` command.

### Check Overlay File

Once connected, check if overlay exists:
```bash
ls -la /mnt/boot/overlays/jd9365da-h3.dtbo
```

### If Overlay File is Missing

If the overlay file doesn't exist, you have three options:

#### Option A: Use the Helper Script (Easiest)

1. **Copy the overlay source or binary to your device** (use `scp -P 22222` — there is no `balena scp` command):
   ```bash
   # Copy .dts source (replace <device> with IP e.g. 192.168.1.100 or hostname.local)
   scp -P 22222 brisby_extras/jd9365da-h3-overlay.dts root@<device>:/tmp/jd9365da-h3-overlay.dts
   
   # OR copy pre-compiled .dtbo from your build:
   scp -P 22222 <build-path>/jd9365da-h3.dtbo root@<device>:/tmp/jd9365da-h3.dtbo
   ```

2. **Copy and run the helper script:**
   ```bash
   scp -P 22222 brisby_extras/add-overlay.sh root@<device>:/tmp/
   ssh root@<device> -p 22222
   chmod +x /tmp/add-overlay.sh
   /tmp/add-overlay.sh
   ```

#### Option B: Manual Copy

1. **Compile overlay on your build machine** (if you have the source):
   ```bash
   dtc -@ -I dts -O dtb -o jd9365da-h3.dtbo jd9365da-h3-overlay.dts
   ```

2. **Copy to device:**
   ```bash
   scp -P 22222 jd9365da-h3.dtbo root@<device>:/tmp/
   ```

3. **Install on device:**
   ```bash
   ssh root@<device> -p 22222
   mkdir -p /mnt/boot/overlays
   cp /tmp/jd9365da-h3.dtbo /mnt/boot/overlays/
   sync
   ```

#### Option C: Rebuild Image with Overlay

If you want the overlay included in future images:
1. The `jd9365da-overlay` recipe must be in your build (meta-brisby layer).
2. The `balena-image.bbappend` must add the overlay to `RPI_KERNEL_DEVICETREE_OVERLAYS` **and** add a dependency so the overlay is deployed before the boot partition is assembled (see below).
3. Rebuild and flash the image.

**Why wasn’t the overlay in my image?**  
The overlay is compiled by the `jd9365da-overlay` recipe and was already listed in `RPI_KERNEL_DEVICETREE_OVERLAYS`, but the **Balena** image does not use `RPI_SDIMG_EXTRA_DEPENDS` (that’s for the standard Raspberry Pi SD image). The Balena image uses `do_resin_boot_dirgen_and_deploy`, which did not depend on `jd9365da-overlay:do_deploy`, so the overlay was not always deployed before the boot partition was built. The bbappend was updated to add `do_resin_boot_dirgen_and_deploy[depends] += "jd9365da-overlay:do_deploy"` for `raspberrypi5`, so after pulling the fix and rebuilding, the overlay will be in the image.

**For now, use Option A or B to get the panel working on an existing image.**

## Step 2: Configure Overlay in Balena Cloud

**Important**: Don't edit `/mnt/boot/config.txt` directly - Balena will overwrite it!

### Via Dashboard:
1. Go to your **Fleet** or **Device** in Balena Cloud
2. Navigate to **Configuration** tab
3. Click **Add variable**
4. Set:
   - **Variable name**: `BALENA_HOST_CONFIG_dtoverlay`
   - **Value**: `"jd9365da-h3"`
5. If you already have `dtoverlay=vc4-kms-v3d,cma-320`, use array format:
   - **Value**: `["vc4-kms-v3d,cma-320","jd9365da-h3"]`
6. **Save** and **reboot** the device

### Via CLI:
```bash
balena env add BALENA_HOST_CONFIG_dtoverlay "jd9365da-h3" --device <uuid>
balena device reboot <uuid>
```

## Step 3: Verify Configuration

After reboot, SSH back in and verify:
```bash
# Check config.txt was updated
grep dtoverlay /mnt/boot/config.txt

# Should show:
# dtoverlay=jd9365da-h3
# (or combined with other overlays)
```

## Step 4: Check Kernel Module

```bash
# Check if module file exists
ls -la /usr/lib/panel/panel-jadard-jd9365da-h3.ko

# Check if module is loaded
lsmod | grep panel_jadard

# If not loaded, check service
systemctl status panel-module-load.service
journalctl -u panel-module-load.service -n 50
```

## Step 5: Verify Device Tree

```bash
# Check if panel node exists
find /proc/device-tree -name "*panel*" -o -name "*txw990002b0*"

# Check compatible string
grep -r "cw,txw990002b0" /proc/device-tree/ 2>/dev/null
```

## Step 6: Check Kernel Messages

```bash
# Look for panel-related messages
dmesg | grep -iE "(panel|jadard|jd9365da|txw990002b0|dsi|mipi)"

# Look for errors
dmesg | grep -iE "error|fail" | grep -iE "(panel|dsi|mipi)"
```

## Troubleshooting

### Overlay not in config.txt
- Verify `BALENA_HOST_CONFIG_dtoverlay` is set correctly in Balena Cloud
- Check variable value format (must be JSON string: `"jd9365da-h3"`)
- Ensure device was rebooted after setting variable

### Module not loading
- Check service status: `systemctl status panel-module-load.service`
- Verify service runs before supervisor: `systemctl list-dependencies panel-module-load.service --reverse | grep balena-supervisor`
- Try manual load: `insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko`
- Check for errors: `dmesg | tail -30`

### Panel not probing
- Verify device tree has panel node (Step 5)
- Check DSI interface: `ls -la /sys/bus/platform/drivers/rp1-dsi/`
- Look for probe errors in dmesg
- Verify GPIO pins (GPIO14 reset, GPIO15 backlight)

### Run Full Diagnostic

Use the debug script:
```bash
# Copy script to device
scp -P 22222 brisby_extras/debug-panel.sh root@<device-ip>:/tmp/

# Run on device
ssh root@<device-ip> -p 22222
chmod +x /tmp/debug-panel.sh
sudo /tmp/debug-panel.sh
```

## Expected Results

When working correctly, you should see:

1. ✅ Overlay file exists: `/mnt/boot/overlays/jd9365da-h3.dtbo`
2. ✅ config.txt contains: `dtoverlay=jd9365da-h3`
3. ✅ Kernel module loaded: `lsmod | grep panel_jadard`
4. ✅ Panel node in device tree: `find /proc/device-tree -name "*panel*"`
5. ✅ Compatible string found: `grep -r "cw,txw990002b0" /proc/device-tree/`
6. ✅ DRM connector appears: `ls /sys/class/drm/card*/status`

## Common Issues

### Issue: Backlight causes probe failure
If you see errors about backlight in dmesg, the driver may need modification to make backlight optional. See `DEBUGGING_PANEL.md` for details.

### Issue: Module loads too late
Ensure `panel-module-load.service` has:
- `Before=balena-supervisor.service`
- `WantedBy=sysinit.target`

### Issue: DSI host probes before panel module
This is why the early-load service is critical. Verify service boot order with:
```bash
systemd-analyze plot > /tmp/boot.svg
```

### Issue: Fleet overwrites custom image (host OS update)
If you flash a **custom** image and add the device to a fleet, Balena can push a **host OS update** so the device matches the fleet’s target OS. That replaces your rootfs and you lose the new panel driver.

**Fix:** The Brisby image includes **prevent-host-os-update**: a service that holds the Balena update lock at boot so the supervisor cannot apply host OS updates. Your custom image then stays in place.

- Service: `prevent-host-os-update.service`
- It runs before `balena-supervisor` and holds `/tmp/balena/updates.lock`.

If you build with meta-brisby’s sample config, this service is already in the image. After flashing, confirm:
```bash
systemctl is-active prevent-host-os-update.service   # should be active
cat /etc/os-release   # VERSION should reflect your build, not stock 6.10.22+rev1
```

## Additional Resources

- Full debugging guide: `DEBUGGING_PANEL.md`
- Debug script: `debug-panel.sh`
- Build documentation: `BUILD_CUSTOM_BALENA_IMAGE.md`
