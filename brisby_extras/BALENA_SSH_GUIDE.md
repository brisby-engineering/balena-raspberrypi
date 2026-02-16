# Balena Device SSH/SCP Guide

## Overview

Balena devices run SSH on port **22222** (not the default port 22). Use **standard SSH and SCP** to connect and copy files. The Balena CLI has `balena ssh` but **no `balena scp`** — use `scp -P 22222` for file transfers.

## Finding Your Device

### Option 1: Using mDNS (Local Network)
If your device is on the same local network, it advertises itself via mDNS:
```bash
# Device hostname is typically: <device-name>.local
ping mydevice.local
```

### Option 2: Using Device IP
Find the device IP from:
- Balena Cloud dashboard (Device → Summary)
- Your router's device list
- Network scanner

### Option 3: Using Device UUID
You can use the device UUID from Balena Cloud dashboard.

## Connecting via SSH

### Method 1: Balena CLI (Recommended)

**Install Balena CLI** (if not already installed):
```bash
npm install -g balena-cli
# OR
curl -L https://github.com/balena-io/balena-cli/releases/latest/download/balena-cli-v<version>-<os>.zip -o balena-cli.zip
```

**SSH into device:**
```bash
# Using device UUID (works from anywhere)
balena ssh <device-uuid>

# Using hostname (local network only)
balena ssh <hostname>.local

# Using IP address
balena ssh <device-ip>
```

**Note**: Balena CLI automatically handles port 22222 and authentication.

### Method 2: Standard SSH

**SSH connection:**
```bash
# Using IP address (port 22222 required)
ssh root@<device-ip> -p 22222

# Using mDNS hostname (local network)
ssh root@<hostname>.local -p 22222
```

**Authentication:**
- **Development images**: Passwordless root access (no password needed)
- **Production images**: Requires SSH key added via Balena Cloud

## Copying Files (SCP)

Balena CLI does **not** provide an `scp` command. Use standard `scp` with port **22222**:

**Copy file TO device:**
```bash
# Using IP address
scp -P 22222 <local-file> root@<device-ip>:<remote-path>

# Using mDNS hostname
scp -P 22222 <local-file> root@<hostname>.local:<remote-path>

# Example:
scp -P 22222 overlay.dtbo root@192.168.1.100:/tmp/overlay.dtbo
scp -P 22222 overlay.dtbo root@mydevice.local:/tmp/overlay.dtbo
```

**Copy file FROM device:**
```bash
# Using IP address
scp -P 22222 root@<device-ip>:<remote-path> <local-file>

# Using mDNS hostname
scp -P 22222 root@<hostname>.local:<remote-path> <local-file>

# Example:
scp -P 22222 root@mydevice.local:/mnt/boot/config.txt ./config.txt
```

**Important**: Always use `-P 22222` (capital P) with SCP — Balena uses port 22222, not the default 22.

## Examples for Panel Setup

### Copy Overlay File to Device
```bash
scp -P 22222 brisby_extras/jd9365da-h3-overlay.dts root@mydevice.local:/tmp/
# OR using IP:
scp -P 22222 brisby_extras/jd9365da-h3-overlay.dts root@192.168.1.100:/tmp/
```

### Copy Script to Device
```bash
scp -P 22222 brisby_extras/add-overlay.sh root@mydevice.local:/tmp/
```

### Run Commands on Device
```bash
# Interactive shell (Balena CLI or standard SSH)
balena ssh mydevice.local
# OR
ssh root@mydevice.local -p 22222

# Single command
ssh root@mydevice.local -p 22222 "ls -la /mnt/boot/overlays/"
```

## Troubleshooting

### Connection Refused
- Verify device is powered on and connected to network
- Check if device is on same network (for mDNS)
- Try using IP address instead of hostname
- Verify port 22222 is not blocked by firewall

### Authentication Failed (Production Images)
- Add your SSH public key via Balena Cloud:
  - Dashboard → Device → Configuration → SSH Keys
  - Or use: `balena keys add <key-name> <public-key-file>`

### mDNS Not Working
- Install Avahi/Bonjour on your computer:
  - macOS: Usually pre-installed
  - Linux: `sudo apt-get install avahi-daemon avahi-utils`
  - Windows: Install Bonjour Print Services
- Or use device IP address instead

### Finding Device IP
```bash
# From device (if you have console access)
ip addr show

# From Balena Cloud dashboard
# Device → Summary → Network Information
```

## Quick Reference

| Task | Command |
|------|---------|
| SSH | `balena ssh <device>` or `ssh root@<device> -p 22222` |
| Copy TO device | `scp -P 22222 file root@<device>:path` |
| Copy FROM device | `scp -P 22222 root@<device>:path file` |
| Port | **22222** (always use `-P 22222` with scp, `-p 22222` with ssh) |
| Auth | Root; passwordless on dev images, SSH key on production |

**Note:** There is no `balena scp` — use standard `scp -P 22222` for file copy.

## Additional Resources

- [Balena SSH Documentation](https://www.balena.io/docs/learn/manage/ssh-access/)
- [Balena CLI Documentation](https://www.balena.io/docs/reference/cli/)
- [Device Network Configuration](https://www.balena.io/docs/reference/OS/network/)
