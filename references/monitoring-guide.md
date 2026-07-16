# Monitoring Guide — self-monitoring 🩺

Deep detail behind `scripts/monitor.sh`: the thresholds, the dedup state-file mechanism, what *silent degradation* actually looks like, and how to escalate. The SKILL.md body is the contract; this is the "why."

---

## What "silent degradation" looks like

An up/down probe answers exactly one question — *is the process alive?* — and stays silent for every other way an agent rots **while still running**:

- A subsystem starts erroring on **every** request (e.g. an embedding/memory call with no API key). The gateway is "up" but spewing hundreds of errors a day, degrading silently.
- An orphaned `systemd` unit with `Restart=always` enters a crash-loop → **thousands** of failed starts a day flooding the journal, zero of them visible to a liveness check.
- Disk creeps to 95%, a model provider starts timing out, a nightly cron fails every run — all invisible to "is it up?".

**War story (the real numbers this skill is built from).** A production agent ran clean on an up/down check for days. Underneath: one memory subsystem failed **176×/day** (a silent regression) and a leftover service crash-looped **~14,000×/day**. Both were caught only by a *manual* audit. The lesson: monitor the *symptoms of degradation*, automatically, and alert a human — or you find out when it's already bad.

---

## The eight checks & their thresholds

| # | Check | Default | Env override | Notes |
|---|-------|---------|--------------|-------|
| 1 | Gateway / process liveness | `openclaw-gateway` user unit | `SERVICE` | falls back to CLI `gateway status`, then a `pgrep openclaw` match |
| 2 | Error-rate spike | `> 60`/hr | `ERR_MAX` | counts `error\|fatal\|exception\|unhandled` in the journal window |
| 3 | Subsystem flood | any match | `SUB_PATTERN` | recurring known-bad signatures — the silent regressions |
| 4 | Failed / restart-looping units | any | — | user (`failed`/`auto-restart`) **and** system `--failed` services |
| 5 | Disk | `> 90%` | `DISK_MAX` | root filesystem |
| 6 | RAM | `> 85%` | `RAM_MAX` | used/total from `free` |
| 7 | CPU load | `> 80%` | `CPU_MAX` | 1-min loadavg ÷ `nproc`, as a percent |
| 8 | Stale logs | per-spec | `STALE_LOGS` | a cron that quietly *stopped writing* (mtime age vs max minutes) |

`STALE_LOGS` is a space-separated `name:max_minutes` list, resolved under `$WORKSPACE/memory/`. Example:
`STALE_LOGS="health-monitor.log:120 resource-log.md:1500"` — alert if the hourly health log is >2h stale, or the daily resource log is >25h stale.

**Count, don't presence-check.** Scan for *recurring* error signatures over a window; never gate on the presence of a single startup line. A one-shot message is not a regression — a sustained rate is.

**Empty journal = suspicious, not clean.** If `journalctl --user` returns nothing, a naive `grep -c` returns `0` and every check looks "clean" — a dangerous false-pass. The helper flags an unreadable journal as an issue instead. The usual cause from cron is a missing `XDG_RUNTIME_DIR` (set at the top of the script).

---

## Dedup by state file

Without dedup, a 6-hour outage = 6 identical pages and the human starts ignoring alerts — so the *one real* alert gets missed. The fix: alert on the **transition**, not the condition.

`monitor.sh --state FILE` writes a signature each run:
- **healthy** → signature is the literal `CLEAN`.
- **issues** → signature is `sha1sum` of the **sorted** issue lines (so order- and time-independent; the same set of problems hashes the same every run).

Comparing this run's signature to the stored one yields exactly one routing decision:

| Transition | Helper prints | You should |
|------------|---------------|------------|
| clean → clean | (nothing) | stay quiet |
| clean → issues, or issue-set changed | `new/changed issue-set — ALERT the human once` | page once |
| issues → same issues | `same issue-set — dedup: do NOT re-alert` | stay quiet |
| issues → clean | `recovered — send ONE '✅ recovered'` | send one all-clear |

Because issue *lines carry no timestamps* (the timestamp lives only in the report header), the signature is stable across runs — a persistent problem hashes identically and dedups cleanly.

---

## Delivering the alert

Send through the **agent's own channel** so you reuse its credentials — no second bot, no raw token in a shell script. A minimal cron wrapper:

```bash
0 * * * * out=$(/root/.openclaw/workspace/skills/self-monitoring/scripts/monitor.sh \
  --quiet --state /root/.openclaw/workspace/.sm.state 2>&1); \
  echo "$out" | grep -q "ALERT the human" && \
  openclaw message send --channel telegram -t "user:<ID>" -m "$out"
```

Map this watchdog to what your runtime **doesn't** already alert on. If OpenClaw already announces cron-job failures, don't double-watch them — point `SUB_PATTERN` and the checks at the gaps. Duplicating platform alerts just doubles the noise.

---

## Escalation

1. **Triage from the report.** The issue line names the class — gateway-down vs error-spike vs zombie unit vs disk vs stale-log — so you know where to look first.
2. **Gateway down** → restart the unit, then read the journal for *why* it died (don't just bounce it).
3. **Error/subsystem flood** → find the offending signature (`journalctl --user -u <unit> --since '60 min ago' | grep <pattern>`); a missing API key or a dead dependency is typical.
4. **Zombie / restart-loop** → identify the looping unit (`systemctl --user list-units --all | grep -E 'failed|auto-restart'`) and disable or fix it; a `Restart=always` orphan is the classic ~14k/day offender.
5. **Disk / RAM / CPU** → the usual capacity work; for disk, the agent's own workspace + logs are the first place to prune.
6. **Stale log** → the cron that owns that log has silently stopped; check the host crontab and that the agent's scheduler is running.

---

## Pitfalls (do not skip)

- ❌ **Hourly spam** — no dedup → alert fatigue → the one real alert ignored. Always pass `--state`.
- ❌ **False-pass on empty logs** — guard the journal read; treat empty output as suspicious. (Handled in the helper.)
- ❌ **Duplicating platform alerts** — watch the gaps your runtime leaves, not what it already pages on.
- ❌ **A second bot just for alerts** — reuse the agent's channel via `message send`.
- ❌ **Trusting an untested watchdog** — prove it runs under `env -i` (the cron-like env), or you've shipped *hope on a schedule*.

---

*Reference for the self-monitoring skill. Derived from the `agent-self-monitoring-and-alerting` Tower book. By Rin 🩺*
