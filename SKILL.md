---
name: self-monitoring
description: Watchdog for an OpenClaw agent that catches the silent degradation an "is it up?" check misses — gateway/process down, CPU/RAM/disk over threshold, error-rate spikes, subsystem error floods, stale logs, and failed/restart-looping units. Ships a helper that prints a dedup-friendly pass/⚠️ report so a persistent problem alerts once. Use when checking agent health, wiring an hourly watchdog, or debugging a process that's "up" but rotting.
version: 1.0.0
metadata:
  openclaw:
    emoji: "🩺"
    requires:
      bins: ["bash", "df", "systemctl", "journalctl"]
triggers:
  - "check agent health"
  - "is it still running"
  - "monitor resources"
  - "set up a watchdog"
  - "why is the gateway slow"
  - "is the agent degrading"
author: Rin
license: UNLICENSED
lastUpdated: 2026-06-17
---

# Self-Monitoring 🩺

A watchdog for an OpenClaw agent that watches the *blind spots* an up/down probe misses — and pages a human **once** when something rots, not every hour.

> **Why this exists.** A production agent ran clean on an "is it up?" check for days. Underneath: one memory subsystem failed **176×/day** and a zombie unit crash-looped **~14,000×/day**. Both were "up." Both were invisible until a manual audit. This skill encodes the watchdog that would have caught them.

## 🚀 Quick Start

```bash
./scripts/monitor.sh                  # one-shot report → exit 0 healthy, 1 if issues
./scripts/monitor.sh --quiet          # print ONLY ⚠️ issue lines (cron / alert mode)
./scripts/monitor.sh --state /root/.openclaw/workspace/.sm.state   # dedup across runs
./scripts/monitor.sh --help           # usage + every overridable env var
```

## 🔍 What it checks

One helper, eight blind-spots — liveness is only the first:

1. **Gateway / process** — systemd `--user` unit → CLI `gateway status` → process match (whichever exists).
2. **Error-rate spike** — error/fatal/exception lines per hour in the journal.
3. **Subsystem flood** — recurring known-bad signatures (e.g. `No API key`, `sync failed`) — the silent regressions.
4. **Zombie units** — `failed` / `auto-restart` user + system units (the crash-loopers).
5. **Disk · 6. RAM · 7. CPU load** — each vs an overridable percent threshold.
8. **Stale logs** — a cron that quietly *stopped writing* (last-modified age vs a max).

Empty journal output is treated as **suspicious** (usually a missing `XDG_RUNTIME_DIR`), never as "clean" — the classic false-pass.

## 🔁 The watchdog + dedup pattern

Run it **hourly from system cron** (survives even if the agent's own scheduler is wedged), and pass `--state` so it alerts on the *transition*, not every tick:

```cron
0 * * * * /root/.openclaw/workspace/skills/self-monitoring/scripts/monitor.sh \
  --quiet --state /root/.openclaw/workspace/.sm.state \
  >> /root/.openclaw/workspace/memory/self-monitoring.log 2>&1
```

The `--state` file holds a signature of the *sorted issue set*. On each run the helper prints exactly one routing hint:

- **new/changed issue-set** → `ALERT the human once`
- **same issue-set** → `dedup: do NOT re-alert` (a 6-hour outage = **1** page, not 6)
- **back to clean** → `send ONE '✅ recovered'`

Pipe the issue lines to the agent's own channel (`openclaw message send …`) so you reuse its credentials — **no second bot, no raw token in a script**.

## ⚙️ Tuning (env overrides)

Defaults are Rin's; every host-specific value is overridable, no edits needed:

```bash
SERVICE=my-gateway WORKSPACE=$HOME/.openclaw/workspace \
CPU_MAX=80 RAM_MAX=85 DISK_MAX=90 ERR_MAX=60 \
SUB_PATTERN="No API key|timeout|sync failed" \
STALE_LOGS="health-monitor.log:120 resource-log.md:1500" \
./scripts/monitor.sh
```

Host-specific bits (the `--user` unit name, the `SUB_PATTERN` signatures) stay sensible-by-default and are commented at the top of the script.

## 🧪 Verify the chain (not just the code)

```bash
./scripts/monitor.sh --state /tmp/s            # healthy → all clear, exit 0
DISK_MAX=0 ./scripts/monitor.sh --state /tmp/s # forced issue → "ALERT … once"
DISK_MAX=0 ./scripts/monitor.sh --state /tmp/s # same issue → "dedup"
./scripts/monitor.sh --state /tmp/s            # back to clean → "recovered"
env -i HOME="$HOME" PATH=/usr/bin:/bin ./scripts/monitor.sh   # must run clean from a cron-like env
```

If it passes in your shell but not under `env -i`, you have the `XDG_RUNTIME_DIR` bug — fix it before trusting the watchdog.

## 📎 When to use & deeper detail

Use it ad-hoc ("is my agent OK?"), as the hourly cron watchdog above, or while chasing an agent that's *technically up* but misbehaving — pair it with `cron-automation` to schedule it. Thresholds, dedup-by-state-file, what *silent degradation* looks like, and escalation: [`references/monitoring-guide.md`](references/monitoring-guide.md) · deep theory: `tower/agent-self-monitoring-and-alerting.md`.

---
*Derived from the `agent-self-monitoring-and-alerting` Tower book. By Rin 🩺*
