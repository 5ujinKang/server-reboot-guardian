# server-manager

A shared-server safety toolkit:

1. **Contention awareness** — see who is running what and whether the server is free
2. **Server lock** — announce performance-critical work so others know to wait
3. **Safe reboots** — intercept `sudo reboot`, notify all users, collect votes, report hardware changes

---

## Files

```
server-manager/
├── show-contention        # Who is running what + hardware contention verdict
├── server-lock            # Announce / clear a performance-critical session
├── shell-integration.bash # Shell functions + PS1 indicator (source in ~/.bashrc)
├── check-reboot-changes   # Login-time: server status + post-reboot hardware diff
├── server-reboot          # Intercepts sudo reboot, runs the vote
├── reboot-vote            # Per-user vote tool (yes / no / status)
└── install.sh             # System-wide install (run as root)
```

---

## Quick start (personal setup, no root)

Add to `~/.bashrc`:

```bash
# server-manager: server status at login + lock-on/off commands
source "$HOME/server-manager/shell-integration.bash"
```

Add to `~/.profile` (or `~/.bash_profile`):

```bash
# Show server contention at every SSH login
if [ -t 1 ]; then
    python3 "$HOME/server-manager/show-contention" --no-disk 2>/dev/null
fi
```

Then reload: `source ~/.bashrc`

---

## Server lock

Announce that you are running something performance-critical so teammates know before starting a heavy job.

### Commands

```bash
server-lock-on                               # set lock with default message
server-lock-on "training ResNet — 4h ETA"   # set lock with custom message
server-lock-off                              # clear your lock
server-lock status                           # show all active locks
```

### What you see (your own terminal)

Your prompt shows a red indicator while the lock is active:

```
[server-lock]==ON  sujin@thoth:~$
```

### What others see at login

When another user logs in while your lock is active, they see a notice in the server status block:

```
====================================================================
  SERVER STATUS — thoth
====================================================================
  ⚠  NOTICE from Sujin Kang (sujin) — since 07:00
     "training ResNet — 4h ETA — please avoid heavy jobs or contact me"

  Load   : 2.3 / 144 CPUs  [LOW]
  ...
====================================================================
```

It also appears in `show-contention` output:

```
========================================================================
  ✓  CLEAR — no compute jobs from others
========================================================================

  ⚠  Sujin Kang (sujin) has a server lock — since 2026-06-24 07:00
     "training ResNet — 4h ETA — please avoid heavy jobs or contact me"
```

### Shell integration setup

`server-lock-on` / `server-lock-off` and the PS1 indicator are shell functions that must be loaded into your shell session.

**Personal (no root):** add to `~/.bashrc`:
```bash
source "$HOME/server-manager/shell-integration.bash"
```

**System-wide (all users):** run `sudo bash install.sh` — it adds the source line to `/etc/bash.bashrc` automatically.

---

## Contention checker (`show-contention`)

Shows a verdict at the top — **CLEAR**, **CAUTION**, or **BUSY** — based on what other users are actually running, followed by a full per-user process table and hardware utilisation report.

The tool excludes its own process from the report so it never inflates your own CPU numbers.

**CLEAR example:**
```
========================================================================
  ✓  CLEAR — no compute jobs from others  (hjx (VSCode), zlr (tmux/idle))
========================================================================
```

**CAUTION — AI agent running:**
```
========================================================================
  !  CAUTION — AI agent active; low now, but can spike without warning
  hjx: CPU:5%  MEM:186MB  AI-agent  [codex — up 38m 20s]  /usr/lib/node_modules/...
  → Judge by the load numbers below, not this banner alone.
========================================================================
```

**CAUTION — compute job running:**
```
========================================================================
  !  CAUTION — compute jobs running; check load below before heavy work
  hjx: CPU:1728%  MEM:70.3GB  [gemm.fastpath.r — up 1m 36s]  output/runnable_gemm_local/...
========================================================================
```

**BUSY:**
```
========================================================================
  ✗  BUSY — significant load from others; coordinate before starting heavy work
  hjx: CPU:4500%  MEM:120GB  [python3 — up 2h 14m]  python3 train.py --epochs 100
========================================================================
```

### Verdict levels

| Verdict | When | What to do |
|---------|------|------------|
| `✓ CLEAR` | Others have only idle sessions (editors, tmux, shells) | Go ahead |
| `! CAUTION` (agent) | An AI agent is running — low CPU now, but may spike without warning | Check the load numbers below the banner; usually safe to proceed |
| `! CAUTION` (compute) | A compute job is active but below 20% of server capacity | Check load below; coordinate if your job is heavy |
| `✗ BUSY` | Others consume ≥ 20% of total CPU capacity (≥ 29 cores here), or GPU is in use | Coordinate before starting heavy work |

### What counts as "compute" vs "idle"

**Ignored (idle):** VS Code / Cursor / JetBrains remote server, `tmux`/`screen`, shells, `(sd-pam)`, processes < 5 seconds old.

**Flagged as compute** — any non-idle process that matches at least one rule:

| Rule | Threshold | Rationale |
|------|-----------|-----------|
| Known compute tool | CPU ≥ 2% | `python3`, `R`, `julia`, `gcc`, `cargo`, MPI, etc. Real jobs briefly dip here between epochs |
| AI coding agent | CPU ≥ 0.1% | `codex`, `aider`, `opencode`, `claude`, `gemini` — active API sessions that can spawn builds at any moment |
| Any unknown binary | CPU ≥ 10% | Catches compiled research code with arbitrary names (`gemm.fastpath.r`, `a.out`, `train`) |
| Long-running with loaded data | ≥ 10 min + ≥ 512 MB + CPU ≥ 0.5% | Training job between epochs, Jupyter kernel with dataset loaded |
| GPU allocated | any | Direct allocation conflict |
| Multi-worker aggregate | total non-idle CPU ≥ 15% | Catches 10 × Python workers at 2% that individually look trivial |

**BUSY vs CAUTION:** BUSY requires others to consume ≥ 20% of total server CPU capacity, or any GPU allocation. On a 144-core server that means ≥ 29 fully loaded cores; on a smaller server the bar scales down accordingly. Below that threshold: CAUTION.

### Usage

```bash
show-contention              # full report for all logged-in users
show-contention --no-disk    # skip disk I/O check (faster, good for login hooks)
show-contention alice bob    # filter to specific users
show-contention -n 10        # show up to 10 processes per user
```

---

## Show at every login

### Personal setup (no root)

Add to `~/.profile`:

```bash
if [ -t 1 ]; then
    python3 "$HOME/server-manager/show-contention" --no-disk 2>/dev/null
fi
```

`--no-disk` skips the 1-second iostat sample so the login is instant.

### System-wide (all users, requires root)

```bash
sudo bash ~/server-manager/install.sh
```

Installs into `/etc/update-motd.d/90-server-contention` so the summary appears in Ubuntu's SSH welcome screen for every user.

---

## Installation (full system-wide)

```bash
sudo bash install.sh
```

| Action | Path |
|--------|------|
| Reboot guardian | `/usr/local/sbin/server-reboot` |
| Vote tool | `/usr/local/bin/reboot-vote` |
| Hardware checker | `/usr/local/bin/check-reboot-changes` |
| Contention checker | `/usr/local/bin/show-contention` |
| Lock manager | `/usr/local/bin/server-lock` |
| Shell functions | `/usr/local/lib/server-manager/shell-integration.bash` |
| Symlink `reboot` → guardian | `/usr/local/sbin/reboot` |
| Block direct `sudo /sbin/reboot` | `/etc/sudoers.d/server-manager` |
| Server status in SSH welcome | `/etc/update-motd.d/90-server-contention` |
| Post-reboot hardware diff at login | `/etc/profile.d/reboot-check.sh` |
| Shell functions for all users | appended to `/etc/bash.bashrc` |
| Data & snapshot directory | `/var/lib/server-manager/` |
| Lock files directory | `/var/lib/server-manager/locks/` (mode 1777) |

---

## Safe reboots

### Requesting a reboot

```bash
sudo reboot
```

The guardian fires automatically. All users receive a `wall` message showing active workloads, pending kernel/package changes, and voting instructions:

```
========================================================================
  REBOOT REQUEST — myserver
========================================================================
  Requested by : alice
  Running kernel: 6.8.0-51-generic
  Logged-in users: alice, bob

  CHANGES THAT TAKE EFFECT AFTER REBOOT:
    [Kernel upgrade]  6.8.0-51-generic  →  6.8.0-124-generic

  ACTIVE WORKLOADS (will be interrupted by reboot):
    bob  CPU: 98%  MEM:12.4GB  [python3 — up 2h14m]  python3 train.py

  To APPROVE:  reboot-vote yes
  To OBJECT:   reboot-vote no
  Reboot proceeds in 5m if no one objects.
========================================================================
```

Press **Ctrl+C** to cancel.

### Voting (other users)

```bash
reboot-vote yes      # approve
reboot-vote no       # object — cancels immediately
reboot-vote status   # show tally and time remaining
```

### Decision rules

| Condition | Outcome |
|-----------|---------|
| Any user votes `no` | Reboot **cancelled immediately** |
| All eligible users vote `yes` | Reboot **proceeds immediately** |
| 5-minute timeout, no objections | Reboot **proceeds** |
| No other users logged in | Reboot after **15-second** countdown |
| Requester presses Ctrl+C | Reboot **cancelled** |

---

## Hardware change detection

`check-reboot-changes` runs at login via `/etc/profile.d/reboot-check.sh`. If the server was rebooted since your last session it prints a hardware diff:

```
====================================================================
  SERVER WAS REBOOTED since your last login
====================================================================
  Your last login : 2026-06-13 22:15
  Server rebooted : 2026-06-14 03:44

  HARDWARE / SYSTEM CHANGES (pre-reboot snapshot from 2026-06-14T03:43):
  ~ Kernel:  6.8.0-51-generic  →  6.8.0-124-generic
  + PCI device:  NVIDIA GA102 [GeForce RTX 3090]
  ~ Firmware/DMI / bios_version:  F5  →  F7
====================================================================
```

Snapshots are saved to `~/.cache/server-manager/hw_snapshot.json` at each login, and to `/var/lib/server-manager/pre_reboot_snapshot.json` just before shutdown.

---

## Requirements

- Python 3.10+
- Standard Linux utilities: `who`, `last`, `wall`, `lscpu`, `lspci`, `lsblk`, `ip`, `ps`
- `nvidia-smi` (optional — GPU contention detection)
- `iostat` (optional — disk I/O utilisation; skipped with `--no-disk`)
- `fwupdmgr` (optional — firmware update detection)
- `sudo` with `/etc/sudoers.d/` support
