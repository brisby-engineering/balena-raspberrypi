# Debug Prompt: JD9365DA-H3 Panel Not Working on BalenaOS

**Quick use:** Copy this entire file, then add: *"Here is the terminal output from the device:"* and paste the output of `debug-panel.sh` (or the raw commands listed below). Give that to a new agent to diagnose the panel issue.

Use this prompt when handing off to a new agent to debug the panel. Paste it **together with** the terminal output from the device.

---

## Your task

Debug why the **JD9365DA-H3** MIPI-DSI panel is not working on a **Raspberry Pi 5 or Compute Module 5** running **BalenaOS**. You will be given terminal output from the device; analyze it and identify the cause, then suggest concrete fixes.

## Context

- **Hardware**: Raspberry Pi 5 or CM5 with a JD9365DA-H3 panel (e.g. TXW990002B0). Panel is 720×1600, 4-lane MIPI DSI. Reset GPIO 14, backlight GPIO 15 (RP1 GPIO numbering).
- **OS**: BalenaOS. Boot partition is at `/mnt/boot`. SSH is on port **22222**. Config is driven by `BALENA_HOST_CONFIG_*` in Balena Cloud, not by editing config.txt by hand.
- **Software stack**:
  1. **Device tree overlay** `jd9365da-h3.dtbo` must be present at `/mnt/boot/overlays/jd9365da-h3.dtbo` and enabled in config (e.g. `dtoverlay=jd9365da-h3`).
  2. **Kernel module** `panel-jadard-jd9365da-h3.ko` must be loaded early (e.g. by `panel-module-load.service` before the DSI host probes).
  3. **Driver** matches device tree node with compatible `cw,txw990002b0` and drives RP1 DSI0.

## What “working” looks like

- `/mnt/boot/overlays/jd9365da-h3.dtbo` exists.
- `grep dtoverlay /mnt/boot/config.txt` shows `jd9365da-h3` (or equivalent).
- `lsmod | grep panel_jadard` shows the module loaded.
- Device tree contains a panel node with compatible `cw,txw990002b0` (e.g. under `/proc/device-tree` or in dmesg).
- No probe/attach errors in dmesg for the panel or DSI host.
- A DRM connector appears (e.g. under `/sys/class/drm/`) and the display can be used.

## Terminal output to analyze

The user will provide one or more of the following (paste it after this prompt):

1. **Full output of the debug script**  
   If they ran it: output of `debug-panel.sh` from this repo (from “JD9365DA-H3 Panel Debug Script” to the end).

2. **Or raw command output**, e.g.:
   - `ls -la /mnt/boot/overlays/jd9365da-h3.dtbo`
   - `grep dtoverlay /mnt/boot/config.txt`
   - `ls -la /usr/lib/panel/panel-jadard-jd9365da-h3.ko`
   - `lsmod | grep panel`
   - `systemctl status panel-module-load.service`
   - `find /proc/device-tree -name '*panel*' -o -name '*txw990002b0*'`
   - `dmesg | grep -iE '(panel|jadard|jd9365da|txw990002b0|dsi|mipi|error|fail)'`
   - `ls -la /sys/class/drm/` and `cat /sys/class/drm/card*/status` (if available)

## Instructions for the agent

1. **Parse the provided terminal output** and determine, for each of the following, whether it passes or fails and what the output shows:
   - Overlay file present at `/mnt/boot/overlays/jd9365da-h3.dtbo`
   - Overlay enabled in config (e.g. `dtoverlay=jd9365da-h3` in config.txt)
   - Panel kernel module file present and module loaded
   - `panel-module-load.service` enabled and run successfully
   - Panel node (or compatible `cw,txw990002b0`) present in device tree
   - DSI/panel-related messages in dmesg (and absence of probe/attach errors)
   - DRM connector present and status

2. **Identify the most likely cause** from common failure modes:
   - **Overlay missing**: file not in `/mnt/boot/overlays/` → add overlay to image or copy manually (see `BALENA_PANEL_SETUP.md`).
   - **Overlay not enabled**: no `dtoverlay=jd9365da-h3` in config.txt → set `BALENA_HOST_CONFIG_dtoverlay` in Balena Cloud and reboot.
   - **Module not loaded**: service failed or runs too late → check `journalctl -u panel-module-load.service`, boot order, and manual `insmod`.
   - **Probe failure**: dmesg shows GPIO/regulator/backlight errors → driver or DT fix (e.g. make backlight optional; see `DEBUGGING_PANEL.md`).
   - **DSI/panel not in device tree**: overlay not applied or wrong board → verify overlay and `compatible` (e.g. `brcm,bcm2712` for Pi 5).

3. **Suggest concrete next steps** (commands or config changes) the user can run on the device or in Balena Cloud. If the output is incomplete, say what extra commands to run and paste back.

4. **Use the repo** when needed:
   - `brisby_extras/DEBUGGING_PANEL.md` – detailed checks and fixes.
   - `brisby_extras/BALENA_PANEL_SETUP.md` – overlay/config and Balena-specific steps.
   - `brisby_extras/jd9365da-h3-overlay.dts` – overlay source (reset/backlight/DSI).
   - `brisby_extras/panel-jadard-jd9365da-h3.c` – driver (probe, backlight, compatible `cw,txw990002b0`).

## How the user should invoke you

Copy this entire prompt, then add a line like:

**“Here is the terminal output from the device:”**

and paste the debug script output and/or the raw command outputs below it. The agent will use that to diagnose and recommend fixes.
