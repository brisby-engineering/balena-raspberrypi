# Multi-Agent Prompt: Custom BalenaOS Image Not Reaching Device

Use this prompt to split work across multiple agents. Each section can be assigned to a different agent; share this file and the repo path so agents have full context.

---

## Goal

Get a **custom BalenaOS image** for **Raspberry Pi 5 / CM5** to run on the device with:

1. **JD9365DA-H3 (TXW990002B0)** 720×1600 panel support (new `mipi_dsi_*_multi` driver + overlay).
2. **prevent-host-os-update** service active so the fleet does not overwrite the custom image with a host OS update.

The device currently shows **stock** BalenaOS (VERSION=6.10.22+rev1, old panel driver, prevent-host-os-update inactive). We need to determine whether the cause is **build** (image never contained our packages), **flash** (wrong file flashed), or **runtime** (e.g. HUP overwriting after boot).

---

## Current Evidence

- **On device after flash:**  
  - `systemctl is-active prevent-host-os-update.service` → **inactive**  
  - `cat /etc/os-release` → VERSION="6.10.22+rev1"  
  - `grep -a "mipi_dsi.*multi" $(modinfo -n panel-jadard-jd9365da-h3)` → **OLD** driver (no match)  
  - So: either the **image flashed is stock**, or the **built image never contained** our packages.

- **Build side:**  
  - We added `IMAGE_INSTALL:append` in **two** places: `layers/meta-brisby/conf/samples/local.conf.sample` (only used when build dir is first created) and **`layers/meta-brisby/recipes-core/images/balena-image.bbappend`** (source of truth).  
  - Post-build script checks the image **manifest** in the deploy dir and prints "Verified: image manifest contains prevent-host-os-update and panel packages" or a WARNING.

---

## Repo Layout (relevant paths)

- **Panel driver:** `layers/meta-brisby/recipes-kernel/panel-jd9365da/files/panel-jadard-jd9365da-h3.c`  
- **Panel recipe:** `layers/meta-brisby/recipes-kernel/panel-jd9365da/panel-jd9365da-h3_0.2.bb`  
- **Image recipe (packages in image):** `layers/meta-brisby/recipes-core/images/balena-image.bbappend`  
- **prevent-host-os-update:** `layers/meta-brisby/recipes-core/prevent-host-os-update/`  
- **Build script:** `brisby_extras/build-brisby-compute5-image.sh`  
- **Template (local + bblayers):** `layers/meta-brisby/conf/samples/`  
- **Docs:** `brisby_extras/BALENA_PANEL_SETUP.md`, `brisby_extras/FLASH_VERIFY.md`, `brisby_extras/DEBUGGING_PANEL.md`

---

## Task 1: Verify Built Image Contents (build server / host)

**Owner:** Agent 1  
**Goal:** Prove whether the artifact we build actually contains our packages and new driver.

- On the **machine that runs the build** (or where the build output is copied):
  1. After a full image build, locate the deploy dir:  
     `build/tmp/deploy/images/raspberrypi5/` (relative to repo root, or `$BRISBY_BUILD_SPACE` if artifacts are copied there).
  2. Find the rootfs **manifest**: `balena-image-*.manifest` in that directory.
  3. Confirm the manifest lists:  
     - `prevent-host-os-update`  
     - `panel-jd9365da-h3` and/or `kernel-module-panel-jadard-jd9365da-h3*`
  4. Optionally: inspect the **rootfs** (e.g. extract from `balena-image-*.balenaos-img` or use a `.rootfs.tar` if present) and check for:  
     - `/usr/libexec/prevent-host-os-update.sh`  
     - `/lib/systemd/system/prevent-host-os-update.service`  
     - `/lib/modules/<kernel>/updates/panel-jadard-jd9365da-h3.ko`  
     - and that the .ko contains the string `mipi_dsi` / `mipi_dsi_multi` (new driver).
- **Deliverable:** Short report: “Manifest contains yes/no; rootfs contains yes/no; driver in .ko is new/old.”

---

## Task 2: Trace Build Configuration and Template Usage

**Owner:** Agent 2  
**Goal:** Ensure the build always uses meta-brisby and that our image recipe is applied.

- In the repo:
  1. Trace how **balena-build.sh** and **barys** use `-t layers/meta-brisby/conf/samples`:  
     - When is `TEMPLATECONF` set and when is `build/conf/local.conf` created/copied from the template?  
     - If the build dir already exists from a previous run with a **different** template, does `local.conf` get overwritten? (Expect: no; only first-time creation.)
  2. Confirm that **balena-image.bbappend** in meta-brisby is the **only** place we need to add `IMAGE_INSTALL:append` so that the image gets our packages regardless of `local.conf`.
  3. Check that **bblayers.conf** (or the template) includes `meta-brisby` and that the image recipe actually uses the bbappend (layer priority, no overrides).
- **Deliverable:** Confirmation that “the image is guaranteed to include our packages when meta-brisby is in the build,” plus any recommendation (e.g. document “delete build/conf and re-run to force template” if someone ever builds without our template).

---

## Task 3: Flash and Device Path Verification

**Owner:** Agent 3  
**Goal:** Ensure the user is flashing the correct file and that we can tell custom vs stock on device.

- Using **brisby_extras/FLASH_VERIFY.md** and the build script output:
  1. Document the **exact** steps: which file to take from the build (e.g. `balena-image-raspberrypi5-<timestamp>.balenaos-img`), how to use `balena os configure` with that file, and how to flash (Etcher / `balena os flash` / etc.).
  2. Add or refine **on-device one-liners** that definitively show “custom image” vs “stock” (e.g. presence of `/usr/libexec/prevent-host-os-update.sh`, service enabled, driver grep).
  3. Optional: provide a small **checklist** (copy-paste commands) the user runs **after** flash to confirm they are on the custom image.
- **Deliverable:** Updated FLASH_VERIFY.md (or a short “Post-flash checklist”) and any edits to the build script’s final echo messages so the user knows which file to flash.

---

## Task 4: Runtime / HUP Behavior (if build and flash are verified)

**Owner:** Agent 4  
**Goal:** Only relevant if we first confirm the **built** image contains our packages and the user has **flashed that image**. Then: determine whether Balena supervisor applies a host OS update after boot and overwrites the custom OS.

- Using Balena docs and, if available, supervisor or OS code in the repo:
  1. When does the supervisor check for and apply a **host OS update** (HUP)? (e.g. before/after our `prevent-host-os-update.service` runs?)
  2. What lock or flag does it respect (e.g. `/tmp/balena/updates.lock` or other)? Confirm path and mechanism for the OS version in use (e.g. kirkstone / 6.10.22).
  3. Verify that **prevent-host-os-update** service:  
     - Starts early enough (`Before=balena-supervisor.service`, `After=local-fs.target`),  
     - Holds the correct lock (e.g. `flock` on the right file),  
     - And that the service is **enabled** and **starts** (not masked or failed).
- **Deliverable:** Short “HUP and lock” summary and, if needed, a recommendation to adjust service order or lock path, or to set fleet target OS to avoid HUP.

---

## Coordination Notes

- **Order:** Tasks 1 and 2 can run in parallel. Task 3 can run in parallel with 1 and 2. Task 4 should run **after** we have evidence that the built image is correct and the flashed file is the custom image.
- **Shared output:** Each agent should report: (1) what was checked, (2) what was found, (3) any code/doc changes made (file paths and a one-line summary).
- **Workspace:** All agents use the same repo: `balena-raspberrypi` (meta-brisby, brisby_extras, balena-yocto-scripts, etc.). Paths in this prompt are relative to the repo root.

---

## Copy-Paste Prompt for Each Agent

You can paste the following, after filling in **TASK_N** and **TASK_TITLE**:

```
Context: We are debugging why a custom BalenaOS image for Raspberry Pi 5 (with JD9365DA-H3 panel and prevent-host-os-update) does not appear on the device—the device shows stock OS and old driver.

Repo: balena-raspberrypi (meta-brisby layer, brisby_extras scripts and docs).

Your task: **TASK_N — TASK_TITLE**

Follow the instructions for that task in the file: brisby_extras/AGENT_PROMPT_MULTI_AGENT.md. Perform the checks and code/doc edits described there. Report: (1) what you checked, (2) what you found, (3) any file changes (path + one-line summary). If you need to run builds or flash, assume the user runs those; your job is to implement verification steps, trace code, or document the process.
```

Fill in:
- **TASK_1** — Verify built image contents (manifest + rootfs/driver)
- **TASK_2** — Trace build configuration and template usage
- **TASK_3** — Flash and device path verification (docs + checklist)
- **TASK_4** — Runtime / HUP behavior (only after 1–3 confirm build and flash)