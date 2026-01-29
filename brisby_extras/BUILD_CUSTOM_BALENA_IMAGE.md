# Building Your Own BalenaOS Image with meta-balena

This guide explains how to build a **custom BalenaOS image** using meta-balena so you can:

1. **Load the JD9365DA-H3 panel kernel module at boot** (before the DSI host probes, fixing EBUSY).
2. **Include the device tree overlay** `jd9365da-h3.dtbo` on the boot partition.
3. **Run an early systemd service** that runs `insmod` for the panel module before the supervisor starts.

Official references:

- [Building Your Own Image (balena docs)](https://www.balena.io/os/docs/custom-build/)
- [balena-raspberrypi](https://github.com/balena-os/balena-raspberrypi) – device repo for Raspberry Pi (including Pi 5)
- [meta-balena](https://github.com/balena-os/meta-balena) – Yocto layers for balenaOS

---

## 1. Prerequisites

- **Linux host** – Yocto/bitbake builds are supported on [Yocto-supported Linux distributions](https://docs.yoctoproject.org/singleindex.html#supported-linux-distributions) (e.g. Ubuntu 20.04/22.04, Fedora, etc.).
- **Docker** – for containerized builds (recommended).
- **cgroups v1** – BalenaOS builds with cgroups v1. If your host uses cgroups v2, boot with:
  ```text
  systemd.unified_cgroup_hierarchy=0
  ```
  or use a VM/container that uses cgroups v1.
- **Build host packages** – for native builds, install [Yocto host packages](https://docs.yoctoproject.org/brief-yoctoprojectqs/#build-host-packages) (e.g. on Ubuntu: `build-essential`, `chrpath`, `diffstat`, `gawk`, `libssl-dev`, `python3`, etc.).
- **Disk space** – tens of GB free (build artifacts and shared state cache).

### Building on macOS

**Native Yocto/BitBake on macOS is not supported.** The build system relies on Linux (e.g. `pseudo` for fakeroot, kernel behavior). You cannot run `bitbake` or `barys` directly on a Mac.

**You can build on macOS by using the containerized build.** The `balena-build.sh` script runs the whole build inside a **Linux Docker container**. With Docker Desktop installed on your Mac, you run the script on the host; the build runs inside the container (Linux), so the build itself is on a supported OS.

- **Use only the containerized method** (Option A in §3). Do not try a native build on macOS.
- **Apple Silicon (M1/M2/M3):** The build image is usually amd64 (x86_64). Docker Desktop runs it via emulation (Rosetta 2 / QEMU), so the build will be **slower** but should complete. Give it plenty of time and RAM.
- **Shared directory (`-s`):** Use a path on your Mac (e.g. `-s $(pwd)/build`). Docker Desktop will bind-mount it into the container. If you hit permission or filesystem errors, try a **Docker named volume** instead and copy the image out after the build (see Docker docs for volume usage).
- **Resources:** In Docker Desktop, increase **Memory** and **Disk** for the build (e.g. 8 GB+ RAM, 80 GB+ disk). The build is large and I/O-heavy.

**Summary:** On macOS, use **containerized build only**; the build runs in a Linux container. Native bitbake on the Mac is not supported.

---

## 2. Clone and Initialize balena-raspberrypi

Use the **Raspberry Pi** device repository. For **Raspberry Pi 5** and **Compute Module 5 (CM5)** use the same device type `raspberrypi5` (Balena uses one image for the whole Pi 5 family, including CM5):

```bash
git clone --recursive https://github.com/balena-os/balena-raspberrypi.git
cd balena-raspberrypi
```

If you cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

This pulls in `meta-balena`, `poky`, `meta-raspberrypi`, and other layers used by the build.

---

## 3. Build Options

### Option A: Containerized build (recommended)

Uses Docker so the host stays clean. From the repo root:

```bash
./balena-yocto-scripts/build/balena-build.sh -d raspberrypi5 -s /path/to/build
```

- **Device type** (`-d`): use `raspberrypi5` for Raspberry Pi 5 or **Compute Module 5 (CM5)** (same slug). See [Device type slugs](https://docs.balena.io/reference/hardware/devices/) for other boards.
- **Shared directory** (`-s`): absolute path to the build directory (created if missing).

The script will run the build inside a container and place outputs in the shared directory.

### Option B: Native build

Requires Yocto host packages and a supported Linux distro:

```bash
# Dry run to create an empty build directory
./balena-yocto-scripts/build/barys --remove-build --dry-run

# Edit build/conf/local.conf if needed (see below)

# Set up the build environment (run in the repo root)
source layers/poky/oe-init-build-env build

# Build the image (example for Raspberry Pi 5)
bitbake balena-image
```

After `oe-init-build-env`, the current directory will be `build/`; use the path that the script prints for `bitbake` if it differs.

### local.conf (for custom layer and machine)

If you add a **custom layer** (e.g. for the panel module and overlay), add it in `build/conf/local.conf`:

```bash
# In build/conf/local.conf, add your layer to BBLAYERS, e.g.:
BBLAYERS:append = " /path/to/balena-raspberrypi/layers/meta-brisby"
```

And set the machine if not already set:

```bash
MACHINE ??= "raspberrypi5"   # same for Pi 5 and Compute Module 5
```

---

## 4. Custom Layer: Panel Module, Service, and Overlay

To load the panel module at boot and include your overlay, add a **custom Yocto layer** to the balena-raspberrypi repo (or your own fork). Below we assume a layer named **meta-brisby** inside `layers/`.

### 4.1 Layer structure

Create a new layer, e.g.:

```bash
cd layers
mkdir -p meta-brisby/conf
mkdir -p meta-brisby/recipes-kernel/panel-jd9365da
mkdir -p meta-brisby/recipes-kernel/panel-jd9365da/files
mkdir -p meta-brisby/recipes-bsp/jd9365da-overlay
mkdir -p meta-brisby/recipes-bsp/jd9365da-overlay/files
mkdir -p meta-brisby/recipes-core/panel-module-load
mkdir -p meta-brisby/recipes-core/panel-module-load/panel-module-load
```

### 4.2 Layer configuration

**`meta-brisby/conf/layer.conf`:**

```bash
# We have a conf and classes directory, add to BBPATH
BBPATH .= ":${LAYERDIR}"

# We have recipes-* directories, add to BBFILES
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "brisby"
BBFILE_PATTERN_brisby = "^${LAYERDIR}/"
BBFILE_PRIORITY_brisby = "10"

LAYERDEPENDS_brisby = "balena"
LAYERSERIES_COMPAT_brisby = "dunfell kirkstone"
```

Adjust `LAYERSERIES_COMPAT_brisby` to match the Yocto versions used by your meta-balena (e.g. dunfell, kirkstone).

### 4.3 Panel kernel module recipe (out-of-tree)

This recipe builds `panel-jadard-jd9365da-h3.ko` from your C source using the image kernel.

**`meta-brisby/recipes-kernel/panel-jd9365da/panel-jd9365da-h3_0.1.bb`:**

```bash
SUMMARY = "JD9365DA-H3 panel kernel module"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit module

SRC_URI = "file://panel-jadard-jd9365da-h3.c file://Makefile"

S = "${WORKDIR}"

# Also install to a fixed path so the early systemd service can find it
do_install:append() {
    install -d ${D}/usr/lib/panel
    install -m 0644 ${S}/panel-jadard-jd9365da-h3.ko ${D}/usr/lib/panel/
}

FILES:${PN} += "/usr/lib/panel/panel-jadard-jd9365da-h3.ko"
```

Copy your module source and Makefile into the recipe’s `files/` directory:

```bash
cp /path/to/brisby-web/kernel-module-build/module/src/panel-jadard-jd9365da-h3.c meta-brisby/recipes-kernel/panel-jd9365da/files/
cp /path/to/brisby-web/kernel-module-build/module/src/Makefile meta-brisby/recipes-kernel/panel-jd9365da/files/
```

The **Makefile** in `kernel-module-build/module/src/` should look like:

```makefile
obj-m += panel-jadard-jd9365da-h3.o
```

The `module` class will set `KERNEL_SRC` (or equivalent) so the recipe builds against the kernel used by the image. If your layer or machine uses a different kernel package, you may need to set `KERNEL_MODULE_AUTOLOAD` or dependencies; for “load at boot via systemd” you don’t need autoload.

### 4.4 Early-load systemd service

This service runs early and loads the panel module before the supervisor (and ideally before the DSI host probes).

**`meta-brisby/recipes-core/panel-module-load/panel-module-load/panel-module-load.service`:**

```ini
[Unit]
Description=Load JD9365DA-H3 panel kernel module before DSI host probes
DefaultDependencies=no
Before=balena-supervisor.service
After=local-fs.target
ConditionPathExists=/usr/lib/panel/panel-jadard-jd9365da-h3.ko

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/insmod /usr/lib/panel/panel-jadard-jd9365da-h3.ko

[Install]
WantedBy=sysinit.target
```

**`meta-brisby/recipes-core/panel-module-load/panel-module-load_%.bbappend`** (or **`panel-module-load_0.1.bb`** if you prefer a new recipe):

If you’re appending to an existing systemd recipe, use a `.bbappend`. Otherwise create a new recipe that installs the unit and depends on the panel module. Example as a **new recipe**:

**`meta-brisby/recipes-core/panel-module-load/panel-module-load_0.1.bb`:**

```bash
SUMMARY = "Systemd service to load JD9365DA-H3 panel module at boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit systemd

SRC_URI = "file://panel-module-load.service"
S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "panel-module-load.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${S}/panel-module-load.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} += "${systemd_system_unitdir}/panel-module-load.service"

RDEPENDS:${PN} = "kernel-module-panel-jd9365da-h3"
```

Put the service file in the recipe’s `files/` directory:

```bash
# From meta-brisby root
mkdir -p recipes-core/panel-module-load/files
# then copy or create recipes-core/panel-module-load/files/panel-module-load.service
```

This way the service is enabled at boot and depends on the panel module package so the `.ko` is installed.

### 4.5 Device tree overlay (jd9365da-h3.dtbo) on boot partition

The boot partition (on device `/mnt/boot`) must contain `overlays/jd9365da-h3.dtbo`. Two approaches:

**A) Compile the overlay in the build and add to Raspberry Pi boot**

- Add a recipe that compiles `jd9365da-h3-overlay.dts` to `jd9365da-h3.dtbo` (using `dtc`) and deploys it.
- Raspberry Pi images typically take boot files from a deploy directory. In balena-raspberrypi/meta-balena-raspberrypi, boot files are often assembled from kernel and other recipes. Append a recipe that adds your overlay into the boot partition content (e.g. by adding it to the image’s boot file list or deploy task).

Example **minimal** recipe that builds the overlay and deploys it:

**`meta-brisby/recipes-bsp/jd9365da-overlay/jd9365da-overlay.bb`:**

```bash
SUMMARY = "Device tree overlay for JD9365DA-H3 panel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

inherit deploy

SRC_URI = "file://jd9365da-h3-overlay.dts"
S = "${WORKDIR}"

do_compile() {
    dtc -@ -I dts -O dtb -o jd9365da-h3.dtbo jd9365da-h3-overlay.dts
}

do_deploy() {
    install -d ${DEPLOYDIR}/overlays
    install -m 0644 ${S}/jd9365da-h3.dtbo ${DEPLOYDIR}/overlays/
}
addtask deploy after do_compile before do_build
```

Copy your overlay source:

```bash
cp /path/to/brisby-web/jd9365da-h3-overlay.dts meta-brisby/recipes-bsp/jd9365da-overlay/files/
```

Getting this overlay **into** the actual Raspberry Pi boot partition in the image usually requires appending to the device’s image or boot recipe so that `DEPLOYDIR/overlays/jd9365da-h3.dtbo` is copied into the boot partition. In balena-raspberrypi, look for how other overlays are included (e.g. variables like `RPI_KERNEL_DEVICETREE_OVERLAYS` in meta-raspberrypi, or image/boot recipe `do_image`/deploy steps). You may need a **bbappend** on the image or the boot partition recipe that copies `${DEPLOYDIR}/overlays/jd9365da-h3.dtbo` into the boot partition’s `overlays/` directory.

**B) Manual copy before first boot**

If integrating into the build is cumbersome at first, you can:

1. Build the image without the overlay in the recipe.
2. After flashing, mount the `resin-boot` partition, create `overlays` if needed, and copy `jd9365da-h3.dtbo` into `overlays/`.
3. Set `BALENA_HOST_CONFIG_dtoverlay` so `config.txt` contains `dtoverlay=jd9365da-h3`.

Then the only custom image requirement is the panel module + early-load service; the overlay is added manually.

### 4.6 Add the layer and packages to the image

In **`build/conf/local.conf`** (or in a layer conf that’s included):

```bash
# Add custom layer
BBLAYERS:append = " /path/to/balena-raspberrypi/layers/meta-brisby"

# Include panel module and early-load service in the image
IMAGE_INSTALL:append = " kernel-module-panel-jd9365da-h3 panel-module-load"
```

If you have a separate recipe for the overlay that deploys only (and doesn’t install to rootfs), you may need to add a dependency or image type append so the deploy runs and the boot partition picks up the overlay (device-specific).

---

## 5. Build and Output

- **Containerized:** run `balena-build.sh` as above; the script will produce the image in the shared build directory.
- **Native:** run `bitbake balena-image` (or the image target your device uses).

Output is typically under `build/tmp/deploy/images/raspberrypi5/` (or your `MACHINE` name): a disk image or artifacts you can flash with Etcher or `dd`.

---

## 6. Flash and Configure

1. **Flash** the built image to the SD card (e.g. balenaEtcher or `dd`).
2. **Configure dtoverlay** so the panel overlay is loaded:
   - In Balena Cloud: **Fleet (or Device) → Configuration**.
   - Add variable **`BALENA_HOST_CONFIG_dtoverlay`** with value including the overlay, e.g.  
     `"jd9365da-h3"`  
     or, if you have other overlays:  
     `"i2c-rtc,ds1307","jd9365da-h3"`.
3. **Boot** the device. The early systemd service should load `panel-jadard-jd9365da-h3.ko` before the supervisor and before the DSI host probes, avoiding EBUSY.

---

## 7. Verify

- SSH into the device (port 22222).
- Check that the panel module is loaded early:
  ```bash
  lsmod | grep panel_jadard
  ```
- Check that the overlay is present and configured:
  ```bash
  ls -la /mnt/boot/overlays/jd9365da-h3.dtbo
  grep dtoverlay /mnt/boot/config.txt
  ```
- Check service and boot order:
  ```bash
  systemctl status panel-module-load.service
  ```

---

## 8. Summary

| Goal                         | How in custom image                                      |
|-----------------------------|-----------------------------------------------------------|
| Panel module loaded at boot | Out-of-tree kernel module recipe + systemd service        |
| Service runs before DSI     | `Before=balena-supervisor.service`, `WantedBy=sysinit.target` |
| Overlay on boot partition   | Recipe that builds + deploys `jd9365da-h3.dtbo` and/or manual copy |
| config.txt dtoverlay        | `BALENA_HOST_CONFIG_dtoverlay` in Balena Cloud            |

Building your own image with meta-balena gives you full control over the host OS so the panel module and overlay are present and the module is loaded early enough to fix the EBUSY probe error.
