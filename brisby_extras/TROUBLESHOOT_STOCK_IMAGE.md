# Troubleshooting: Build Succeeds but Image Is Stock

If you already run `--clean-config` before building and the image manifest still misses `prevent-host-os-update` and `panel-jd9365da-h3`, consider these other possibilities.

## 1. Stale build/conf (most common)

- **Symptom:** Manifest missing our packages after a “clean” build.
- **Cause:** `build/conf` was recreated from a template that does **not** include meta-brisby (e.g. an earlier run without our `-t` path, or conf left from a different clone).
- **Check:**  
  `grep meta-brisby REPO_ROOT/build/conf/bblayers.conf`  
  If empty, meta-brisby is not in the build.
- **Fix:**  
  `./brisby_extras/build-brisby-compute5-image.sh --clean-config`  
  then run the script again with no options.

---

## 2. meta-brisby missing on the build host

- **Symptom:** Build runs but uses the default meta-balena template instead of meta-brisby.
- **Cause:** On the machine that runs the build (e.g. remote server), the repo has no `layers/meta-brisby` or the path is wrong. Barys resolves `-t layers/meta-brisby/conf/samples` relative to the repo (e.g. `/work` in Docker). If that directory does not exist, barys can fall back to finding another `bblayers.conf.sample` (e.g. under meta-balena-raspberrypi), so the build still runs but **without** meta-brisby.
- **Check (on build host):**  
  `ls -la REPO_ROOT/layers/meta-brisby/conf/samples/bblayers.conf.sample`  
  and  
  `grep -l meta-brisby REPO_ROOT/layers/meta-brisby/conf/samples/bblayers.conf.sample`
- **Fix:** Clone/pull the repo so it includes `layers/meta-brisby` and `brisby_extras` (no sparse checkout or branch that omits them).

---

## 3. Template path not passed into the container

- **Symptom:** You pass `-g "-t layers/meta-brisby/conf/samples ..."` but the build still uses another template.
- **Cause:** The `-g` string is passed to `prepare-and-start.sh`, which passes all arguments to barys. If the string is mangled (e.g. quoting/shell differences), barys might not see `-t layers/meta-brisby/conf/samples` and will use its default template search (meta-balena*).
- **Check:** After a build, inspect the generated conf:  
  `grep meta-brisby REPO_ROOT/build/conf/bblayers.conf`  
  If empty, the template path was not used. You can also run the build script with `--diagnose` to verify template path and conf.
- **Fix:** Ensure the build script is unchanged and you run it from the repo root so `-g "-t layers/meta-brisby/conf/samples -a ..."` is passed verbatim. If you wrap the script or call `balena-build.sh` yourself, pass the same `-g` argument.

---

## 4. Build dir is not the repo’s build dir

- **Symptom:** You delete `build/conf` and rebuild but the manifest is still stock.
- **Cause:** The Yocto build directory is always `REPO_ROOT/build` (barys uses `BUILD_DIR=build` under the repo). If you run the script from another clone or worktree, or if `REPO_ROOT` is different from the directory actually mounted as `/work` in Docker, then the “clean” conf and the conf used by the build may be in different places.
- **Check:** From the host, after a build:  
  `ls REPO_ROOT/build/conf/bblayers.conf`  
  and  
  `grep meta-brisby REPO_ROOT/build/conf/bblayers.conf`  
  Use the same `REPO_ROOT` as the script (parent of `brisby_extras`). If that file doesn’t exist or doesn’t contain meta-brisby, the build you’re inspecting is not the one that ran in the container.
- **Fix:** Run the script from the repo root that is actually used for the Docker build (the one mounted as `/work`), and use `--clean-config` + full build from that same repo.

---

## 5. Conf created once from wrong template, then reused

- **Symptom:** You ran without our template once (e.g. forgot `-g`, or ran upstream script), then added `-g` later. Builds still produce a stock image.
- **Cause:** `build/conf` is created only when it doesn’t exist. If it was first created from a template without meta-brisby, later runs do not overwrite it.
- **Check:**  
  `grep meta-brisby REPO_ROOT/build/conf/bblayers.conf`
- **Fix:**  
  `./brisby_extras/build-brisby-compute5-image.sh --clean-config`  
  then run the script again (no options).

---

## 6. Repo / worktree mismatch (e.g. Cursor worktree vs server)

- **Symptom:** You changed the build script or meta-brisby in a worktree or on your Mac, but the build runs on a server or in a different clone.
- **Cause:** The build uses whatever is in the repo on the **build host** (e.g. server). If that repo doesn’t have the latest `brisby_extras` and `layers/meta-brisby`, the container will not use our template or layer.
- **Check:** On the **build host**, run:  
  `./brisby_extras/build-brisby-compute5-image.sh --diagnose`  
  and confirm that meta-brisby and template path are present and that (if `build/conf` exists) `bblayers.conf` includes meta-brisby.
- **Fix:** Sync the repo on the build host (git pull, or copy `brisby_extras` and `layers/meta-brisby` from your worktree) and run `--clean-config` then build again.

---

## Quick checklist

1. Run `--clean-config` then build (no options) from the **same** repo that is used for the Docker build.
2. On the **build host**: `grep meta-brisby REPO_ROOT/build/conf/bblayers.conf` → should print a line containing `meta-brisby`.
3. On the **build host**: `ls REPO_ROOT/layers/meta-brisby/conf/samples/bblayers.conf.sample` → should exist.
4. Use `./brisby_extras/build-brisby-compute5-image.sh --diagnose` to run these checks and see a short summary of other possibilities.
