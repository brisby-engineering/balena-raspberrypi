# Brisby image build – Linux box (one-time setup + build)

Use this on your Linux build box (e.g. DigitalOcean Ubuntu 22.04) where you have GitHub access. Brisby fork: **brisby-engineering/balena-raspberrypi**.

If you see a GUI prompt about **restarting old daemons**, the setup script now sets `DEBIAN_FRONTEND=noninteractive` to suppress it. Re-run the script after pulling the latest; or run `export DEBIAN_FRONTEND=noninteractive` before any manual `apt-get install` commands.

---

## 1. One-time setup

From your home directory (or anywhere), run the setup script with the Brisby fork URL. It will install Docker and git (if needed), clone the fork on the **brisby** branch, and create the build directory.

```bash
export REPO_URL="git@github.com:brisby-engineering/balena-raspberrypi.git"
curl -sSL https://raw.githubusercontent.com/brisby-engineering/balena-raspberrypi/brisby/brisby_extras/setup-linux-build-box.sh | bash -s -- "$REPO_URL"
```

**Or**, if you already have the repo (e.g. cloned manually), run the script from inside the repo:

```bash
cd ~/balena-raspberrypi   # or wherever you cloned
./brisby_extras/setup-linux-build-box.sh git@github.com:brisby-engineering/balena-raspberrypi.git
```

**If you haven’t cloned yet and prefer to clone by hand:**

```bash
git clone -b brisby --recursive git@github.com:brisby-engineering/balena-raspberrypi.git ~/balena-raspberrypi
cd ~/balena-raspberrypi
```

Then install Docker if needed (Ubuntu). Use `DEBIAN_FRONTEND=noninteractive` to avoid the "restart old daemons?" GUI prompt:

```bash
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME:-$UBUNTU_CODENAME}") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

If Docker was just installed, **log out and back in** (or run `newgrp docker`) so your user is in the `docker` group.

---

## 2. Set build directory and run the build

```bash
export BRISBY_BUILD_SPACE="${BRISBY_BUILD_SPACE:-$HOME/brisby_custom}"
cd ~/balena-raspberrypi
./brisby_extras/build-brisby-compute5-image.sh
```

The build runs in Docker and can take **4–8 hours**. The script will copy the image and overlay into `$BRISBY_BUILD_SPACE` when done.

**Running as root (e.g. `ssh root@...`):** The script will chown the repo and build space to 1000:1000 so the container’s builder user can write; no extra step needed.

---

## 3. After the build

- Image: `$BRISBY_BUILD_SPACE/balena-image-raspberrypi5.balenaos-img` (and optional `.xz`)
- Overlay: `$BRISBY_BUILD_SPACE/overlays/jd9365da-h3.dtbo`

Download to your Mac (from your Mac):

```bash
scp user@YOUR_LINUX_BOX:$HOME/brisby_custom/balena-image-raspberrypi5.balenaos-img* .
```

Flash the image to your CM5, then in Balena Cloud set:

`BALENA_HOST_CONFIG_dtoverlay` = `jd9365da-h3`

---

## Quick reference (all in one)

```bash
# One-time: clone and setup (Brisby fork)
git clone -b brisby --recursive git@github.com:brisby-engineering/balena-raspberrypi.git ~/balena-raspberrypi
# If Docker not installed, install it then: newgrp docker (or log out/in)

# Build
export BRISBY_BUILD_SPACE=$HOME/brisby_custom
cd ~/balena-raspberrypi
./brisby_extras/build-brisby-compute5-image.sh
```
