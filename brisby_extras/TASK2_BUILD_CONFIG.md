# Task 2: Build Configuration and Template Usage

## Summary

**Conclusion:** The image is guaranteed to include our packages (panel-jd9365da-h3, panel-module-load, prevent-host-os-update) **only when meta-brisby is in the build**. The critical dependency is **bblayers.conf** including meta-brisby. If the build directory was created with a template that does not include meta-brisby, our packages will never be in the image.

---

## 1. How balena-build.sh and barys Use Templates

### balena-build.sh

- Passes `-g "-t layers/meta-brisby/conf/samples -a SANITY_SKIP_CASE_INSENSITIVE_FS=1"` to barys.
- The `-g` flag forwards arguments to barys; `-t` sets the templates path.

### barys (from balena-yocto-scripts)

- **`-t | --templates-path`**: Path to the directory containing `local.conf.sample` and `bblayers.conf.sample`.
- When provided (e.g. `layers/meta-brisby/conf/samples`), barys sets:
  ```bash
  TEMPLATECONF_PATH="${SCRIPTPATH}/../../layers/meta-brisby/conf/samples"
  export TEMPLATECONF="${TEMPLATECONF_PATH}"
  source .../oe-init-build-env build
  ```
- **oe-init-build-env** (from Poky) creates `build/conf/local.conf` and `build/conf/bblayers.conf` **only when they do not exist**. It copies from the templates in `TEMPLATECONF`.

### When is local.conf / bblayers.conf Created?

- **First run** (no `build/conf/`): Templates are copied. Our meta-brisby template provides:
  - `bblayers.conf.sample` with meta-brisby in `BBLAYERS`
  - `local.conf.sample` with `IMAGE_INSTALL:append` (redundant with bbappend but ensures fresh builds get it)
- **Subsequent runs** (build/conf/ already exists): **Templates are NOT overwritten.** The existing `local.conf` and `bblayers.conf` are used as-is.

---

## 2. Critical Finding: Stale Build Directory

**If the build directory was originally created without the meta-brisby template** (e.g. default meta-balena-raspberrypi template or a manual setup):

1. `bblayers.conf` will **not** include meta-brisby.
2. The meta-brisby layer is never parsed.
3. `balena-image.bbappend` in meta-brisby is **never applied**.
4. The image will be **stock** (no panel-jd9365da-h3, no prevent-host-os-update).

**Recommendation:** If you suspect a stale build, delete `build/conf` and re-run the build script so that `oe-init-build-env` recreates conf from the meta-brisby template:

```bash
rm -rf build/conf
./brisby_extras/build-brisby-compute5-image.sh
```

---

## 3. balena-image.bbappend is the Source of Truth

- **Location:** `layers/meta-brisby/recipes-core/images/balena-image.bbappend`
- **Content:** `IMAGE_INSTALL:append = " panel-jd9365da-h3 panel-module-load prevent-host-os-update"`
- **When applied:** Only when meta-brisby is in `BBLAYERS` (bblayers.conf).
- **Relationship to local.conf.sample:** The template's `IMAGE_INSTALL:append` in local.conf.sample is redundant; the bbappend guarantees packages are in the image as long as the layer is in the build. The template ensures a **fresh** build dir gets the same config.

---

## 4. bblayers.conf Must Include meta-brisby

The meta-brisby template's `bblayers.conf.sample` must add meta-brisby to `BBLAYERS`. Verify in your build:

```bash
grep meta-brisby build/conf/bblayers.conf
```

If this returns nothing, meta-brisby is not in the build and the custom packages will not be included.

---

## 5. Checklist for Correct Build

1. **First-time setup or after changing templates:** Delete `build/conf` before building.
2. **Build script:** Always use `-g "-t layers/meta-brisby/conf/samples ..."` (the build script does this).
3. **Verify:** After build, run `./brisby_extras/verify-built-image.sh` and confirm manifest contains our packages.
