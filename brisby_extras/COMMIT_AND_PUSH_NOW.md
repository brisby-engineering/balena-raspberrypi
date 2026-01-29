# Update the fork (run these, then push)

We **no longer commit submodules**. All Brisby changes to balena-yocto-scripts and poky live in **`brisby_extras/overrides/`** and are applied at build time. You only push this repo (myfork).

## 1. Commit and push from repo root

```bash
cd /path/to/balena-raspberrypi   # or your clone

git add brisby_extras/
git status   # check what’s included
git commit -m "Your message (e.g. Brisby overrides and build script updates)"
git push myfork brisby
```

(If you haven’t added the fork: `git remote add myfork git@github.com:brisby-engineering/balena-raspberrypi.git`)

---

**How it works:** The build script copies `brisby_extras/overrides/balena-yocto-scripts/*` and `brisby_extras/overrides/poky/*` over the submodules before building, and builds the helper image from the repo when overrides are present. So cloning only this fork and running the build is enough; no other repos or forks are needed.
