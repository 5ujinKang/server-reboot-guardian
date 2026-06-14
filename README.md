# server-reboot-guardian

A shared-server safety tool that intercepts `sudo reboot`, notifies all logged-in users, shows pending system changes, collects votes, and reports hardware differences after a reboot.

---

## Overview

On a shared server, an unannounced reboot can interrupt other users' work. This tool:

1. **Intercepts** `sudo reboot` before anything happens
2. **Broadcasts** a `wall` message to every logged-in terminal identifying who requested the reboot
3. **Shows** what will change after the reboot (kernel upgrade, packages, firmware, etc.)
4. **Waits** for other users to approve or object (5-minute timeout)
5. **Detects** hardware differences the next time each user logs in

---

## Files

```
server-reboot-guardian/
├── server-reboot-guardian   # Main guardian — intercepts sudo reboot
├── reboot-vote              # Per-user voting tool
├── check-reboot-changes     # Login-time hardware diff checker
└── install.sh               # Installs everything system-wide (run as root)
```

---

## Installation

```bash
sudo bash install.sh
```

What the installer does:

| Action | Path |
|--------|------|
| Install guardian binary | `/usr/local/sbin/server-reboot-guardian` |
| Install vote binary | `/usr/local/bin/reboot-vote` |
| Install hardware checker | `/usr/local/bin/check-reboot-changes` |
| Symlink `reboot` → guardian | `/usr/local/sbin/reboot` |
| Block direct `sudo /sbin/reboot` | `/etc/sudoers.d/server-reboot-guardian` |
| Run checker at every login | `/etc/profile.d/reboot-check.sh` |
| Pre-reboot snapshot directory | `/var/lib/server-reboot-guardian/` |

---

## Usage

### Requesting a reboot

```bash
sudo reboot
```

The guardian fires automatically. You will see (and all other users will receive via `wall`):

```
========================================================================
  REBOOT REQUEST — myserver
========================================================================
  Requested by : alice
  Time         : 2026-06-14 03:44:01
  Uptime       : 12d 7h 33m
  Running kernel: 6.8.0-51-generic
  Logged-in users: alice, bob, carol

  CHANGES THAT TAKE EFFECT AFTER REBOOT:
    [Kernel upgrade]  6.8.0-51-generic  →  6.8.0-124-generic
    [Packages needing reboot]  linux-image-generic, nvidia-driver-550

  Other users online: bob, carol

  To APPROVE this reboot:  reboot-vote yes
  To OBJECT  this reboot:  reboot-vote no
  To see current status:   reboot-vote status

  Reboot proceeds in 5m if no one objects.
========================================================================
```

Press **Ctrl+C** at any time to cancel the reboot before it executes.

### Voting (other users)

```bash
reboot-vote yes      # approve — reboot proceeds once all respond or timeout
reboot-vote no       # object  — reboot is cancelled immediately
reboot-vote status   # show current vote tally and time remaining
```

### Decision rules

| Condition | Outcome |
|-----------|---------|
| Any user votes `no` | Reboot **cancelled immediately** |
| All eligible users vote `yes` | Reboot **proceeds immediately** |
| 5-minute timeout, no objections | Reboot **proceeds** |
| No other users logged in | Reboot proceeds after a **15-second** countdown |
| Requester presses Ctrl+C | Reboot **cancelled** |

---

## Hardware change detection

`check-reboot-changes` runs automatically at login (via `/etc/profile.d/reboot-check.sh`). It compares the current hardware state to a snapshot saved at your previous login and reports any differences if the server was rebooted in between.

You can also run it manually at any time:

```bash
check-reboot-changes
```

### Example output

```
====================================================================
  SERVER WAS REBOOTED since your last login
====================================================================
  Your last login : 2026-06-13 22:15
  Server rebooted : 2026-06-14 03:44

  HARDWARE / SYSTEM CHANGES (pre-reboot snapshot from 2026-06-14T03:43):
  ~ Kernel:         6.8.0-51-generic  →  6.8.0-124-generic
  + PCI device:     01:00.0 "NVIDIA Corporation" "GA102 [GeForce RTX 3090]"
  ~ Firmware/DMI / bios_version:  F5  →  F7
  - Block device:   sdb  500G  disk  SAMSUNG MZ7L3480  sata

  Current kernel : 6.8.0-124-generic
  CPU            : Intel(R) Xeon(R) Gold 6154 CPU @ 3.00GHz
  Memory total   : 263827528 kB
====================================================================
```

### What is compared

| Category | Details |
|----------|---------|
| Kernel | Running kernel version (`uname -r`) |
| CPU | Model, core/socket/NUMA count, frequency (`lscpu`) |
| Memory | Total RAM and swap (`/proc/meminfo`) |
| PCI devices | All PCI device entries — NICs, GPUs, storage controllers (`lspci`) |
| Block devices | Disks, sizes, models, transport (`lsblk`) |
| Network interfaces | Interface names, types, MAC addresses (`ip link`) |
| BIOS / firmware | Version, date, board name, product name (`/sys/class/dmi/id/`) |

### How snapshots work

- **Pre-reboot snapshot** — saved by the guardian to `/var/lib/server-reboot-guardian/pre_reboot_snapshot.json` in the seconds before the actual reboot command runs. This is the preferred baseline for hardware diffs.
- **Per-user login snapshot** — saved to `~/.cache/server-reboot-guardian/hw_snapshot.json` at each login. Used as fallback if no pre-reboot snapshot exists (e.g. emergency reboot bypassing the guardian).

If no baseline exists yet (first login after install), the snapshot is saved silently and no diff is shown.

---

## Requirements

- Python 3.10+ (for `X | Y` union type hints)
- Standard Linux utilities: `who`, `last`, `wall`, `lscpu`, `lspci`, `lsblk`, `ip`
- `fwupdmgr` (optional — for firmware update detection)
- `sudo` with drop-in sudoers support (`/etc/sudoers.d/`)
