# Get Brisby into version control and push to your fork

## Done already (in this repo)

- **Branch:** `brisby` (created from `master`)
- **Committed:** `brisby_extras/`, `layers/meta-brisby/`, and `.gitignore` (with `.DS_Store` ignored)
- **Commit:** `Add Brisby: brisby_extras and meta-brisby layer for CM5 JD9365DA-H3 panel`

So the main Brisby code is in version control locally.

---

## 1. Add your fork and push the main repo

`origin` is still the upstream repo. Add your fork and push the `brisby` branch:

```bash
cd /path/to/balena-raspberrypi   # your repo root

# Add Brisby fork (if not already origin)
git remote add myfork git@github.com:brisby-engineering/balena-raspberrypi.git

# Push the brisby branch to your fork
git push myfork brisby
```

After this, the fork will have the `brisby` branch with all of `brisby_extras` and `layers/meta-brisby`.

---

## 2. Optional: put submodule changes in version control

You also have **modified submodules**:

- **balena-yocto-scripts** – `prepare-and-start.sh`, `balena-lib.inc` (and optionally `Dockerfile_yocto-build-env`)
- **layers/poky** – `meta/classes/sanity.bbclass`

Right now those changes are only in your working tree. To put them in version control and have the main repo point to them:

### 2.1 Commit inside each submodule

```bash
# balena-yocto-scripts
cd balena-yocto-scripts
git checkout -b brisby   # if not already on it
git add automation/entry_scripts/prepare-and-start.sh automation/include/balena-lib.inc
git commit -m "Brisby: tolerate image pull failure; avoid groupadd GID conflict in container"
cd ..

# layers/poky
cd layers/poky
git checkout -b brisby
git add meta/classes/sanity.bbclass
git commit -m "Brisby: allow SANITY_SKIP_CASE_INSENSITIVE_FS for Docker on macOS"
cd ../..
```

### 2.2 Record the new submodule commits in the main repo

```bash
git add balena-yocto-scripts layers/poky
git commit -m "Pin submodules to Brisby patches (balena-yocto-scripts, poky)"
git push myfork brisby
```

### 2.3 Make submodule commits pushable (so clones get them)

The main repo will now reference new commits in the submodules. Those commits exist only on your machine until you push them. To do that you need your own copies of the submodule repos:

1. Fork **balena-yocto-scripts** and **poky** (e.g. from balena-os or YoctoProject) on GitHub.
2. In each submodule, add your fork and push the `brisby` branch:

   ```bash
   cd balena-yocto-scripts
   git remote add myfork https://github.com/YOUR_GITHUB_USER/balena-yocto-scripts.git
   git push myfork brisby
   cd ..

   cd layers/poky
   git remote add myfork https://github.com/YOUR_GITHUB_USER/poky.git
   git push myfork brisby
   cd ../..
   ```

3. Optionally update the main repo’s `.gitmodules` so the submodule URLs point to your forks and the branch to `brisby`; then run `git submodule update --remote`, commit any changed refs, and push again. Then a clone with `--recursive` will pull your submodule branches.

If you skip forking the submodules, the main repo will still have the correct refs locally and your builds will use the Brisby patches; but a fresh clone will not get those submodule commits until you push them somewhere and/or document manual steps.

---

## Summary

| Step | Command / action |
|------|-------------------|
| Push main Brisby code | `git remote add myfork git@github.com:brisby-engineering/balena-raspberrypi.git` then `git push myfork brisby` |
| (Optional) Commit submodule changes | In `balena-yocto-scripts` and `layers/poky`: create branch, add files, commit |
| (Optional) Record submodule refs | In main repo: `git add balena-yocto-scripts layers/poky`, commit, push |
| (Optional) Push submodule commits | Fork balena-yocto-scripts and poky, add remotes, push `brisby` branch |

Minimum to “get the new code into version control” and push: do **Step 1**; your fork will have the Brisby branch with `brisby_extras` and `meta-brisby`.
