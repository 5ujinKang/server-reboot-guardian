# server-reboot-guardian

A shared-server safety toolkit with two purposes:

1. **Contention awareness** — see who is running what and whether the server is free before starting a heavy job
2. **Safe reboots** — intercept `sudo reboot`, notify all logged-in users, collect votes, and report hardware changes after the reboot

---

## Files

```
server-reboot-guardian/
├── show-contention          # Who is running what + hardware contention verdict
├── check-reboot-changes     # Login-time: server status + post-reboot hardware diff
├── server-reboot-guardian   # Intercepts sudo reboot, runs the vote
├── reboot-vote              # Per-user vote tool (yes / no / status)
└── install.sh               # System-wide install (run as root)
```

---

## Contention checker (`show-contention`)

Shows a verdict at the top — **CLEAR**, **CAUTION**, or **BUSY** — based on what other users are actually running (ignoring idle editors and shells), followed by a full per-user process table and hardware utilisation report.

```
========================================================================
  ✓  CLEAR — no compute jobs from others  (hjx (VSCode), zlr (tmux/idle))
========================================================================

========================================================================
  USER PROCESS & HARDWARE CONTENTION REPORT
  thoth  |  2026-06-24 06:41:15  |  144 CPUs
========================================================================
  Load avg : 0.6, 0.4, 0.3  (0% of 144 CPUs)
  Memory   : 24.3GB / 251.3GB (10% used)

  ACTIVE USER WORKLOADS
  --------------------------------------------------------------------
  hjx   8 proc(s)  CPU: 0.2%  MEM:880MB
    PID 1196366  node   CPU: 0.2%  MEM:559MB  up:2h 55m  /home/hjx/.vscode-server/...

  HARDWARE CONTENTION ANALYSIS
  --------------------------------------------------------------------
  CPU  [LOW]    Load 0.6 on 144 CPUs = 0% utilization
  Memory [LOW]  24.3GB / 251.3GB (10%)
  GPU  [N/A]    (nvidia-smi not found)
  Disk I/O [LOW]
========================================================================
```

### Verdict levels

| Verdict | Meaning |
|---------|---------|
| `✓ CLEAR` | Other users have no active compute jobs (idle editors, tmux sessions only) |
| `! CAUTION` | Someone has an active job but the server is not saturated |
| `✗ BUSY` | Heavy CPU, GPU, or memory load from other users — coordinate before starting |

### What counts as "compute work" vs "idle"

The verdict ignores:
- VS Code / Cursor / JetBrains remote server processes
- `tmux`, `screen`, shell sessions with no CPU
- `(sd-pam)` and other kernel/PAM helpers
- Processes running for less than 5 seconds (transient shell helpers)

The verdict flags:
- Python, R, Julia, MATLAB, compilers, MPI jobs at ≥ 5% CPU
- Any process at ≥ 20% CPU that is not a shell or editor
- Long-running processes (≥ 10 min) with ≥ 2 GB loaded and active CPU
- Any process with GPU memory allocated

### Usage

```bash
show-contention              # full report for all logged-in users
show-contention --no-disk    # skip disk I/O check (faster)
show-contention alice bob    # filter to specific users
show-contention -n 10        # show up to 10 processes per user
```

---

## Show at every login

### Personal setup (no root required)

Add to `~/.profile` (or `~/.bash_profile` if that exists):

```bash
# Show server contention at every login
if [ -t 1 ]; then
    python3 "$HOME/server-reboot-guardian/show-contention" --no-disk 2>/dev/null
fi
```

`--no-disk` skips the 1-second iostat sample, making the login instant.

This shows the contention block right before your first prompt every time you SSH in.

### System-wide setup (all users, requires root)

```bash
sudo bash ~/server-reboot-guardian/install.sh
```

This installs a leaner summary into `/etc/update-motd.d/90-server-contention` so it appears inside Ubuntu's SSH welcome screen for every user automatically, without any per-user configuration.

---

## Installation (full system-wide)

```bash
sudo bash install.sh
```

What the installer does:

| Action | Path |
|--------|------|
| Install guardian binary | `/usr/local/sbin/server-reboot-guardian` |
| Install vote binary | `/usr/local/bin/reboot-vote` |
| Install hardware checker | `/usr/local/bin/check-reboot-changes` |
| Install contention checker | `/usr/local/bin/show-contention` |
| Symlink `reboot` → guardian | `/usr/local/sbin/reboot` |
| Block direct `sudo /sbin/reboot` | `/etc/sudoers.d/server-reboot-guardian` |
| Contention summary in SSH welcome | `/etc/update-motd.d/90-server-contention` |
| Post-reboot hardware diff at login | `/etc/profile.d/reboot-check.sh` |
| Pre-reboot snapshot directory | `/var/lib/server-reboot-guardian/` |

---

## Safe reboots

### Requesting a reboot

```bash
sudo reboot
```

The guardian fires automatically. All logged-in users receive a `wall` broadcast:

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

  ACTIVE WORKLOADS (will be interrupted by reboot):
    bob   CPU: 98.0%  MEM:12.4GB
      python3  CPU: 98.0%  MEM:12.4GB  up:2h14m  python3 train.py --epochs 100

  Hardware status: CPU:MODERATE(45%)  Memory:LOW(18%)

  Other users online: bob, carol

  To APPROVE this reboot:  reboot-vote yes
  To OBJECT  this reboot:  reboot-vote no
  To see current status:   reboot-vote status

  Reboot proceeds in 5m if no one objects.
========================================================================
```

Press **Ctrl+C** to cancel before the reboot executes.

### Voting (other users)

```bash
reboot-vote yes      # approve
reboot-vote no       # object — cancels immediately
reboot-vote status   # show vote tally and time remaining
```

### Decision rules

| Condition | Outcome |
|-----------|---------|
| Any user votes `no` | Reboot **cancelled immediately** |
| All eligible users vote `yes` | Reboot **proceeds immediately** |
| 5-minute timeout, no objections | Reboot **proceeds** |
| No other users logged in | Reboot proceeds after **15-second** countdown |
| Requester presses Ctrl+C | Reboot **cancelled** |

---

## Hardware change detection

`check-reboot-changes` runs at login via `/etc/profile.d/reboot-check.sh`. If the server was rebooted since your last session it prints a hardware diff. Run manually at any time:

```bash
check-reboot-changes
```

### Example output (after a reboot)

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

- **Pre-reboot snapshot** — saved by the guardian to `/var/lib/server-reboot-guardian/pre_reboot_snapshot.json` just before shutdown. Preferred baseline for diffs.
- **Per-user login snapshot** — saved to `~/.cache/server-reboot-guardian/hw_snapshot.json` at each login. Fallback if no pre-reboot snapshot exists (e.g. emergency reboot bypassing the guardian).

---

## Requirements

- Python 3.10+
- Standard Linux utilities: `who`, `last`, `wall`, `lscpu`, `lspci`, `lsblk`, `ip`, `ps`
- `nvidia-smi` (optional — for GPU contention detection)
- `iostat` (optional — for disk I/O utilisation; skipped with `--no-disk`)
- `fwupdmgr` (optional — for firmware update detection)
- `sudo` with drop-in sudoers support (`/etc/sudoers.d/`)
