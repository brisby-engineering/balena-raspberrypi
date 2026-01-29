# Uploading and Cloning the Brisby Repo (with downstream changes)

Your repo has:

- **Main repo content**: `brisby_extras/`, `layers/meta-brisby/`, and any top-level changes.
- **Modified submodules** (“downstream elements”):
  - `balena-yocto-scripts` (e.g. `prepare-and-start.sh`, `balena-lib.inc`)
  - `layers/poky` (e.g. `sanity.bbclass` for `SANITY_SKIP_CASE_INSENSITIVE_FS`)

Below: how to upload from a “new folder” and how others (or a build box) can clone everything.

---

## 1. Get your “new folder” into a proper Git repo

If your “new folder” is a **copy** of the project (not a clone):

- **Option A – Prefer this:** Use a fresh clone of your fork and copy your changes in.
  1. Fork **balena-raspberrypi** on GitHub (if you haven’t):  
     https://github.com/balena-os/balena-raspberrypi → “Fork”.
  2. Clone your fork and go into it:
     ```bash
     git clone --recursive https://github.com/YOUR_USER/balena-raspberrypi.git brisby-upload
     cd brisby-upload
     git checkout -b brisby
     ```
  3. Copy from your “new folder” into this clone:
     - `brisby_extras/` → replace entire folder
     - `layers/meta-brisby/` → replace entire folder
     - `balena-yocto-scripts/` → only the files you changed (e.g. `automation/entry_scripts/prepare-and-start.sh`, `automation/include/balena-lib.inc`)
     - `layers/poky/` → only the files you changed (e.g. `meta/classes/sanity.bbclass`)
  4. Then follow **§2** and **§3** from this repo.

- **Option B – Your new folder is already a clone:**  
  If it already has `.git` and submodule `.git` dirs, add your fork as remote and push (see §2–3). If submodules are still pointing at upstream remotes, you’ll need to push submodule changes to your forks and update refs (§3).

---

## 2. Push the main repo (balena-raspberrypi)

From the **root** of the repo (your clone that has brisby_extras and meta-brisby):

```bash
cd /path/to/balena-raspberrypi   # or your "new folder" if it's a clone

git remote -v
# If 'origin' is balena-os/balena-raspberrypi, add your fork:
git remote add myfork https://github.com/YOUR_USER/balena-raspberrypi.git
# Or if origin is already your fork, use origin.

git checkout -b brisby   # or your branch name
git add brisby_extras layers/meta-brisby
git status              # check no unwanted files
git commit -m "Add brisby_extras and meta-brisby layer for CM5 JD9365DA-H3"
git push myfork brisby   # or: git push origin brisby
```

That uploads **only** the main repo (brisby_extras, meta-brisby, and any other top-level or layer changes you added). Submodules are separate (next step).

---

## 3. Push modified submodules and point the main repo at them

The main repo records **which commit** each submodule is at. To “upload” downstream changes you must:

1. Push those changes to **your forks** of the submodules.
2. In the **main repo**, update the submodule to that new commit and commit the updated reference.
3. Push the main repo again.

### 3.1 balena-yocto-scripts

```bash
cd balena-yocto-scripts
git remote -v
git remote add myfork https://github.com/YOUR_USER/balena-yocto-scripts.git   # if not already
git checkout -b brisby
git add automation/entry_scripts/prepare-and-start.sh automation/include/balena-lib.inc
git commit -m "Brisby: tolerate pull failure and avoid groupadd GID conflict"
git push myfork brisby
git rev-parse HEAD   # note this commit SHA (e.g. abc1234)
cd ..
```

### 3.2 layers/poky (if you changed sanity.bbclass)

```bash
cd layers/poky
git remote add myfork https://github.com/YOUR_USER/poky.git   # if not already (fork from balena-os/poky or Yocto’s poky)
git checkout -b brisby
git add meta/classes/sanity.bbclass
git commit -m "Brisby: allow SANITY_SKIP_CASE_INSENSITIVE_FS"
git push myfork brisby
git rev-parse HEAD   # note this SHA
cd ../..
```

### 3.3 Point main repo at your submodule commits

You have two ways to make the main repo use your forks and branches:

**Option A – Change .gitmodules to your forks (recommended for a permanent “brisby” setup)**

Edit `.gitmodules` in the repo root so the submodules pull from your forks:

```ini
# For balena-yocto-scripts, change url to your fork:
[submodule "balena-yocto-scripts"]
	path = balena-yocto-scripts
	url = https://github.com/YOUR_USER/balena-yocto-scripts.git
	branch = brisby

# For poky, if you forked it:
[submodule "layers/poky"]
	path = layers/poky
	url = https://github.com/YOUR_USER/poky.git
	branch = brisby
```

Then update the submodule refs to the commits you just pushed:

```bash
cd balena-yocto-scripts
git fetch myfork brisby
git checkout myfork/brisby   # or the SHA you noted
cd ..

cd layers/poky
git fetch myfork brisby
git checkout myfork/brisby   # or the SHA you noted
cd ../..

git add .gitmodules balena-yocto-scripts layers/poky
git commit -m "Use brisby forks for balena-yocto-scripts and poky"
git push myfork brisby
```

**Option B – Keep .gitmodules unchanged and document manual steps**

Leave `.gitmodules` pointing at upstream. In your README or `brisby_extras/setup-linux-build-box.sh` (or this file), document that after cloning, users must run:

```bash
git submodule update --init --recursive
cd balena-yocto-scripts && git fetch https://github.com/YOUR_USER/balena-yocto-scripts.git brisby && git checkout FETCH_HEAD && cd ..
cd layers/poky && git fetch https://github.com/YOUR_USER/poky.git brisby && git checkout FETCH_HEAD && cd ../..
```

Then you still need to **commit the submodule refs** in the main repo so the main repo “knows” which commit to use:

```bash
cd balena-yocto-scripts
git checkout <SHA or branch from your fork>
cd ..
cd layers/poky
git checkout <SHA or branch from your fork>
cd ../..
git add balena-yocto-scripts layers/poky
git commit -m "Pin submodules to brisby patches"
git push myfork brisby
```

So: “upload” = push main repo + push each changed submodule to your fork, then point the main repo at those commits (and optionally point .gitmodules at your forks).

---

## 4. Cloning on another machine (e.g. DigitalOcean build box)

If you used **Option A** (§3.3) and pushed everything:

```bash
git clone --recursive https://github.com/YOUR_USER/balena-raspberrypi.git -b brisby
cd balena-raspberrypi
# Submodules should already be on your brisby branches; verify:
git submodule status
```

If you used **Option B**, after `git clone --recursive ...` run the extra `git fetch` / `git checkout` commands you documented for each modified submodule.

Then run the build:

```bash
export BRISBY_BUILD_SPACE=$HOME/brisby_custom
./brisby_extras/build-brisby-compute5-image.sh
```

---

## Summary

| What you changed        | Where to push it              | What to do in main repo                    |
|-------------------------|-------------------------------|--------------------------------------------|
| brisby_extras, meta-brisby | Your fork of balena-raspberrypi | Commit and push (e.g. branch `brisby`)     |
| balena-yocto-scripts    | Your fork of balena-yocto-scripts | Push branch; update submodule ref + optional .gitmodules |
| layers/poky             | Your fork of poky             | Push branch; update submodule ref + optional .gitmodules |

“Upload” = push main repo + push each modified submodule to your fork, then commit updated submodule refs (and optionally .gitmodules) in the main repo and push again.
