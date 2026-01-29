# Brisby overrides (submodule patches in the main repo)

These files are **copied over the upstream submodules** at build time so you only need to clone and push **this fork**. You do not need access to (or forks of) balena-yocto-scripts or poky.

- **balena-yocto-scripts/** – `prepare-and-start.sh` (GID/UID 0 fix so container runs as root when host is root), `balena-lib.inc` (tolerate image pull failure).
- **poky/** – `meta/classes/sanity.bbclass` (allow `SANITY_SKIP_CASE_INSENSITIVE_FS=1` for Docker on macOS).

The build script applies them automatically before building or rebuilding the helper image.
