# Task 4: Runtime / HUP Behavior

**Use this only after confirming:** (1) the built image contains our packages, and (2) the user has flashed that custom image. If the device still shows stock, the cause is build or flash, not HUP.

---

## When does the supervisor apply a host OS update (HUP)?

- The Balena supervisor checks for host OS updates based on the **fleet's target OS version** in Balena Cloud.
- If the fleet target OS differs from the device's current OS, the supervisor can trigger a host OS update.
- HUP runs as part of the supervisor's update flow; it stops the supervisor, applies the update to the spare root partition, and reboots.

---

## Update lock mechanism

- **Lock path (Supervisor v7.22.0+):** `/tmp/balena/updates.lock`
- **Legacy path:** `/tmp/resin/resin-updates.lock` (older devices)
- The lock must be created with **exclusive access** (e.g. `flock` or `lockfile` with `O_EXCL`/`O_CREAT`). Simply touching the file is insufficient.
- Host OS updates **respect** update locks and will not proceed if an exclusive lock is held.
- Locks are cleared on reboot.

---

## prevent-host-os-update service verification

Our service is configured as:

```ini
[Unit]
Description=Hold Balena update lock (prevent host OS overwrite of custom image)
DefaultDependencies=no
Before=balena-supervisor.service
After=local-fs.target

[Service]
Type=simple
ExecStart=/usr/libexec/prevent-host-os-update.sh

[Install]
WantedBy=sysinit.target
```

The script holds the lock:

```sh
mkdir -p /tmp/balena
exec flock -x /tmp/balena/updates.lock sleep infinity
```

**Verification:**
- **Order:** `Before=balena-supervisor.service` ensures we acquire the lock before the supervisor starts. This is correct.
- **Lock:** `flock -x` creates an exclusive lock on `/tmp/balena/updates.lock`, which HUP respects.
- **Enabled:** The service must be **enabled** (e.g. `WantedBy=sysinit.target`) and **started**. If it is masked or failed, the lock is never held.

**Check on device:**
```bash
systemctl is-enabled prevent-host-os-update.service   # should be enabled
systemctl is-active prevent-host-os-update.service    # should be active
```

---

## Recommendations

1. **If build and flash are verified but device still gets overwritten:**
   - Ensure the service is enabled: `systemctl enable prevent-host-os-update.service`
   - Ensure it starts: `systemctl start prevent-host-os-update.service`
   - Check it holds the lock: `lsof /tmp/balena/updates.lock` (should show the sleep process)

2. **Fleet target OS:** In Balena Cloud, set the fleet's target OS version to match your custom image (or a version that won't trigger HUP). This reduces the chance of HUP being attempted.

3. **Override:** Balena allows overriding update locks via the API/dashboard. Ensure no one has overridden the lock for your fleet.
