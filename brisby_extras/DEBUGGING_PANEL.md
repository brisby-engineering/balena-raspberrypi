# Debugging JD9365DA-H3 Panel Issues on BalenaOS

## BalenaOS-Specific Notes

- **SSH Access**: `ssh root@<device-ip> -p 22222`
- **Boot Partition**: `/mnt/boot` (resin-boot partition)
- **Config Management**: Use `BALENA_HOST_CONFIG_*` variables in Balena Cloud, not direct config.txt editing
- **Service Dependencies**: panel-module-load.service should run before balena-supervisor.service

## Quick Diagnostic Commands

Run these commands on your Raspberry Pi device to diagnose panel issues:

### 1. Check if overlay is loaded
```bash
# Check if overlay file exists
ls -la /mnt/boot/overlays/jd9365da-h3.dtbo

# Check if overlay is enabled in config.txt (Balena manages this via BALENA_HOST_CONFIG_dtoverlay)
grep dtoverlay /mnt/boot/config.txt | grep jd9365da-h3

# Check all dtoverlay settings
grep "^dtoverlay" /mnt/boot/config.txt
```

### 2. Check if kernel module is loaded
```bash
# Check if module file exists
ls -la /usr/lib/panel/panel-jadard-jd9365da-h3.ko

# Check if module is loaded
lsmod | grep panel_jadard

# Check module dependencies
modinfo panel-jadard-jd9365da-h3
```

### 3. Check systemd service
```bash
# Check service status
systemctl status panel-module-load.service

# Check service logs
journalctl -u panel-module-load.service -n 50

# Verify service runs before balena-supervisor (important!)
systemctl list-dependencies panel-module-load.service --reverse | grep balena-supervisor

# Check boot order
systemd-analyze plot > /tmp/boot.svg  # Can download and view
```

### 4. Check device tree
```bash
# Check if panel node exists in device tree
find /proc/device-tree -name "*panel*" -o -name "*txw990002b0*"

# Check compatible string
grep -r "cw,txw990002b0" /proc/device-tree/ 2>/dev/null

# Check DSI interface
ls -la /sys/bus/platform/drivers/rp1-dsi/
```

### 5. Check kernel messages
```bash
# Look for panel-related messages
dmesg | grep -iE "(panel|jadard|jd9365da|txw990002b0|dsi|mipi)"

# Look for errors
dmesg | grep -iE "error|fail" | grep -iE "(panel|dsi|mipi)"

# Check for probe failures
dmesg | grep -iE "probe.*fail|failed to probe"
```

### 6. Check DRM/KMS
```bash
# List DRM devices
ls -la /sys/class/drm/

# Check connector status
cat /sys/class/drm/card*/status

# List displays
ls /dev/dri/
```

## Common Issues and Solutions

### Issue 1: Overlay not loading

**Symptoms:**
- Panel node not found in device tree
- No panel-related messages in dmesg

#### Issue 1a: Overlay file missing on boot partition

If `ls -la /mnt/boot/overlays/jd9365da-h3.dtbo` shows **No such file or directory** but `grep dtoverlay /mnt/boot/config.txt` shows `jd9365da-h3`, the config asks for the overlay but the overlay binary was never placed on the boot partition. That usually means:

- You are **not** running a custom image built from this repo (meta-brisby). Stock BalenaOS does not include `jd9365da-h3.dtbo`. Setting only `BALENA_HOST_CONFIG_dtoverlay=jd9365da-h3` is not enough; the overlay file must be on the boot partition.
- **Fix:** Build and flash the **custom BalenaOS image** from this repo (see `brisby_extras/build-brisby-compute5-image.sh` and `LINUX_BUILD_RUNBOOK.md`). The image recipe puts the overlay in the boot partition. After flashing that image, set `BALENA_HOST_CONFIG_dtoverlay` to `jd9365da-h3` and reboot.
- **Temporary test (if boot partition is writable):** Copy the overlay onto the device, e.g. `scp -P 22222 brisby_custom/overlays/jd9365da-h3.dtbo root@<device>:/mnt/boot/overlays/`, then reboot. The panel node may then appear, but the panel driver still must load (see Issue 2).

**Solutions (BalenaOS):**
1. Verify overlay file exists: `ls -la /mnt/boot/overlays/jd9365da-h3.dtbo`
2. **Configure via Balena Cloud** (not direct config.txt editing):
   - Go to Fleet/Device → Configuration
   - Add variable: `BALENA_HOST_CONFIG_dtoverlay`
   - Value: `"jd9365da-h3"` (or combine: `"vc4-kms-v3d,cma-320","jd9365da-h3"`)
   - Reboot device after setting
3. Verify config.txt was updated: `grep dtoverlay /mnt/boot/config.txt`
4. Check for overlay compilation errors: `dtc -I dtb -O dts /mnt/boot/overlays/jd9365da-h3.dtbo`
5. Ensure overlay is compatible with your Pi model (should be `brcm,bcm2712` for Pi 5/CM5)

### Issue 2: Kernel module not loading

**Symptoms:**
- `lsmod | grep panel_jadard` shows nothing
- Module file exists but isn't loaded

**Solutions:**
1. Check if module file exists: `ls -la /usr/lib/panel/panel-jadard-jd9365da-h3.ko`
2. Try manual load: `sudo insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko`
3. Check for load errors: `dmesg | tail -20`
4. Verify systemd service is enabled: `systemctl is-enabled panel-module-load.service`
5. Check service logs: `journalctl -u panel-module-load.service`

#### Issue 2a: Service fails with "Invalid module format"

**Symptoms:**
- `panel-module-load.service` is failed; journal shows: `insmod: ERROR: could not insert module /usr/lib/panel/panel-jadard-jd9365da-h3.ko: Invalid module format`
- `lsmod | grep panel_jadard` may still show the module loaded (from a different path)
- `modinfo panel-jadard-jd9365da-h3` shows `filename: .../lib/modules/$(uname -r)/updates/panel-jadard-jd9365da-h3.ko.zst` (not `/usr/lib/panel/`)

**Cause:** The service loads the `.ko` in `/usr/lib/panel/`, which may be an older or wrong-kernel build. The kernel actually uses the module from `/lib/modules/$(uname -r)/updates/`. Loading the wrong `.ko` with `insmod` fails due to vermagic/ABI mismatch.

**Solutions:**
1. **Use modprobe in the service** (recommended): Change the service to run `modprobe panel-jadard-jd9365da-h3` instead of `insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko` so the correct module from the kernel’s module path is loaded. See `layers/meta-brisby/recipes-core/panel-module-load/panel-module-load/panel-module-load.service`.
2. Ensure the recipe that installs the panel module places a kernel-matching build in `/usr/lib/panel/` (same build as in `/lib/modules/.../updates/`), or rely on modprobe and remove the dependency on `/usr/lib/panel/`.

### Issue 3: Module loads but panel doesn't probe

**Symptoms:**
- Module is loaded (`lsmod` shows it)
- No panel device appears
- dmesg shows no probe attempt

**Possible causes:**
1. **Device tree mismatch**: The compatible string in device tree doesn't match driver
   - Check: `grep -r "cw,txw990002b0" /proc/device-tree/`
   - Driver expects: `cw,txw990002b0`

2. **DSI host not ready**: DSI interface might not be initialized
   - Check: `ls -la /sys/bus/platform/drivers/rp1-dsi/`
   - Check: `dmesg | grep -i dsi`

3. **Module loaded too late**: DSI host probes before panel module is available
   - Solution: Ensure `panel-module-load.service` runs early (Before=balena-supervisor.service)
   - Check boot order: `systemd-analyze plot > /tmp/boot.svg`
   - Verify service dependency: `systemctl list-dependencies panel-module-load.service --reverse`
   - In BalenaOS, the service should be in `WantedBy=sysinit.target` and `Before=balena-supervisor.service`

### Issue 4: Probe fails with error

**Symptoms:**
- dmesg shows probe errors
- Specific error messages about GPIO, regulator, or backlight

**Common errors:**

#### GPIO error:
```
failed to get our reset GPIO
```
- Check GPIO pin assignment (should be GPIO14 for reset)
- Verify GPIO is not used by another driver
- Check: `cat /sys/kernel/debug/gpio` (if available)

#### Regulator error:
```
failed to get vdd regulator
failed to get vccio regulator
```
- Regulators are defined in overlay but might not be enabled
- Check: `ls -la /sys/class/regulator/`
- Verify regulator names match: `panel_vdd_3v3` and `panel_vccio`

#### Backlight error:
```
drm_panel_of_backlight failed
```
- **This is a known issue**: The driver returns error if backlight is not found
- **Potential fix**: Make backlight optional in driver (modify `jadard_dsi_probe` to not return on backlight error)
- Check: `ls -la /sys/class/backlight/`

### Issue 5: Panel probes but display doesn't work (DRM says connected, panel stays black)

**Symptoms:**
- Panel/DSI appears in dmesg and `rp1dsi_bind succeeded`
- `/sys/class/drm/` shows card2-DSI-1 and one connector may show "connected"
- Physical panel stays black / no image

**Run these on the device (SSH port 22222) and fix the first thing that fails:**

#### 5a. Backlight is off (most common)

```bash
# List backlight devices
ls -la /sys/class/backlight/

# If empty, the panel driver may have failed to get backlight (see Issue 4 backlight error).
# If present (e.g. panel0 or gpio_backlight):
cat /sys/class/backlight/*/brightness    # often 0
cat /sys/class/backlight/*/max_brightness

# Turn backlight on (replace 0 with your device name if different)
echo 255 > /sys/class/backlight/*/brightness
# or explicitly:
echo 255 > /sys/class/backlight/gpio_backlight/brightness
```

If there is no `/sys/class/backlight/` entry, the driver may have failed during probe on backlight; then either fix the overlay (backlight node, GPIO15) or make backlight optional in the driver (see "Potential Driver Fix" below). If you have a backlight with `brightness=1` and `max_brightness=1`, that is normal for GPIO on/off backlight and means "on"; if the panel is still black, the usual cause is that nothing is driving the DSI output (5b).

#### 5b. Nothing is driving the DSI output

The panel only shows an image when something (compositor, X, Wayland, or a direct KMS app) uses the DSI connector. If the system only outputs to HDMI or no app is using the display, the panel can stay black even though it’s "connected".

- Ensure your app or UI is configured to use the DSI display (e.g. set `DISPLAY`, use `card2` or the DSI connector name).
- On a minimal OS, you may need to set the mode and enable the connector (e.g. with `modetest` from libdrm-tests, or your application using KMS/DRM).

#### 5c. Check connector status and which card is DSI

```bash
# Which cards exist and their status
for c in /sys/class/drm/card*-*/status; do echo "$c: $(cat $c)"; done

# DSI is usually card2 on Pi 5. Confirm:
ls -la /sys/class/drm/ | grep DSI
```

Use the DSI card (e.g. card2) and connector (e.g. DSI-1) when configuring your display stack.

#### 5d. Power and reset (overlay)

Overlay defines fixed regulators and GPIO reset. If the panel never powers or resets, you’d typically see probe or prepare errors in dmesg. If probe succeeded but the screen is black, try:

- Turning backlight up first (5a).
- Ensuring something is actually using the DSI connector (5b).

#### 5e. fb0 is DSI but screen still black (no splash, no console)

If `ls /sys/class/graphics/fb0` shows fb0 under `.../1f00118000.dsi/...` and `card2-DSI-1` is connected, the framebuffer is the DSI panel but nothing may have set a mode or drawn to it.

**Test 1 – Force a mode (if modetest is available):**
```bash
modetest -M drm-rp1-dsi 2>/dev/null || modetest
# Find the DSI connector id and a mode (e.g. 720x1600), then:
modetest -M drm-rp1-dsi -s <connector_id>:720x1600
```

**Test 2 – Write to the framebuffer:** Fill fb0 to see if the panel shows a change (e.g. flash or color). Panel is typically 720×1600 RGB (720×1600×4 bytes per frame). `dd if=/dev/zero of=/dev/fb0 bs=720 count=6400` or similar may show something if the mode is already set.

**Splash / boot logo:** BalenaOS splash may be bound to another DRM card (e.g. card0/HDMI). With `console=null` and only DSI connected, the kernel may still treat card0 as primary. There is no standard Pi 5 cmdline to force DSI as primary; getting the Balena boot screen on the panel may require custom splash configuration or a Balena/device setting that selects the DSI connector.

#### 5f. modetest and dd to fb0 show nothing

If forcing a mode and writing to `/dev/fb0` still give no visible response:

**1. Confirm a mode is actually in use**
```bash
cat /sys/class/drm/card2-DSI-1/status
cat /sys/class/drm/card2-DSI-1/modes
# If 'modes' is empty or no mode is set, the panel may never be enabled. modetest -s should set one; check dmesg after:
modetest -M drm-rp1-dsi -s <id>:720x1600
dmesg | tail -20
```

**2. Backlight polarity**  
Some panels need backlight **active-low** (GPIO low = on). The overlay uses `gpios = <&rp1_gpio 15 0>` (active-high). If the panel is active-low, try inverting: in the overlay DTS change to `GPIO_ACTIVE_LOW` (e.g. `gpios = <&rp1_gpio 15 GPIO_ACTIVE_LOW>;`), rebuild the overlay, and reflash. On device you can’t change the overlay; only test by toggling:
```bash
echo 0 > /sys/class/backlight/*/brightness
sleep 1
echo 1 > /sys/class/backlight/*/brightness
```
If the screen briefly appears when you set 0, the backlight may be inverted.

**3. Hardware**  
- Confirm power (3.3 V) and DSI cable seating.  
- Confirm GPIO 14 (reset) and 15 (backlight) match your carrier board.  
- Try another known-good panel or cable if available.

**4. Driver enable sequence**  
The panel’s `prepare`/`enable` run when a mode is set and the pipeline is committed. If dmesg shows no errors and `rp1dsi_bind succeeded`, the link is up; lack of image with mode set + fb write points to backlight or hardware.

## Using the Debug Script

A comprehensive debug script is available at `brisby_extras/debug-panel.sh`.

To use it on BalenaOS:
1. Copy to device: `scp -P 22222 debug-panel.sh root@<device-ip>:/tmp/`
2. SSH to device: `ssh root@<device-ip> -p 22222`
3. Make executable: `chmod +x /tmp/debug-panel.sh`
4. Run: `sudo /tmp/debug-panel.sh`

The script checks all components and provides a summary of issues specific to BalenaOS.

## Manual Testing Steps

If automated debugging doesn't reveal the issue, try these manual steps:

### Step 1: Verify overlay manually
```bash
# Check overlay syntax
dtc -I dtb -O dts /mnt/boot/overlays/jd9365da-h3.dtbo > /tmp/overlay.dts
cat /tmp/overlay.dts

# Verify compatible string
grep compatible /tmp/overlay.dts
```

### Step 2: Load module manually with debug
```bash
# Load with verbose logging
sudo insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko dyndbg="+p"

# Check immediate dmesg output
dmesg | tail -30
```

### Step 3: Check DSI host status
```bash
# List DSI devices
find /sys/devices -name "*dsi*" -o -name "*mipi*"

# Check DSI driver binding
cat /sys/bus/platform/drivers/rp1-dsi/*/uevent 2>/dev/null
```

### Step 4: Verify hardware connections
- GPIO14: Reset pin (active-low)
- GPIO15: Backlight enable (active-high)
- DSI data lanes: Connected to DSI0
- Power: 3.3V regulators

## Potential Driver Fix

If the backlight is causing probe to fail, you may need to modify the driver to make backlight optional:

In `jadard_dsi_probe`, change:
```c
ret = drm_panel_of_backlight(&jadard->panel);
if (ret)
    return ret;
```

To:
```c
ret = drm_panel_of_backlight(&jadard->panel);
if (ret && ret != -ENODEV) {
    DRM_DEV_WARN(dev, "failed to get backlight: %d\n", ret);
    // Continue without backlight
}
```

This allows the panel to probe even if backlight is not found.

## BalenaOS-Specific Configuration

### Setting dtoverlay via Balena Cloud

1. **Via Balena Cloud Dashboard:**
   - Navigate to your Fleet or Device
   - Go to **Configuration** tab
   - Add new variable:
     - **Name**: `BALENA_HOST_CONFIG_dtoverlay`
     - **Value**: `"jd9365da-h3"` (JSON string format)
   - If you have multiple overlays, use array format:
     - **Value**: `["vc4-kms-v3d,cma-320","jd9365da-h3"]`
   - Save and reboot device

2. **Via Balena CLI:**
   ```bash
   balena env add BALENA_HOST_CONFIG_dtoverlay "jd9365da-h3" --device <uuid>
   ```

3. **Verify after reboot:**
   ```bash
   grep dtoverlay /mnt/boot/config.txt
   ```

### Important Notes for BalenaOS

- **Don't edit config.txt directly** - Balena will overwrite it
- **Always use BALENA_HOST_CONFIG_* variables** for persistent configuration
- **Reboot required** after changing BALENA_HOST_CONFIG variables
- **Service timing**: Ensure panel-module-load.service runs before balena-supervisor

## Getting Help

When reporting issues, include:
1. Output of `debug-panel.sh`
2. Full dmesg: `dmesg > dmesg.log`
3. Service logs: `journalctl -u panel-module-load.service > service.log`
4. Device tree dump: `dtc -I fs /proc/device-tree > device-tree.dts`
5. Kernel version: `uname -r`
6. Pi model: `cat /proc/device-tree/model`
7. BalenaOS version: `cat /etc/os-release`
8. Current config.txt: `cat /mnt/boot/config.txt`
9. BALENA_HOST_CONFIG variables: Check Balena Cloud dashboard
