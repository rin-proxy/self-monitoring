#!/bin/bash
# monitor.sh — self-monitoring watchdog for an OpenClaw agent.
# Detects SILENT DEGRADATION an "is it up?" probe misses: gateway/process down,
# CPU/RAM/disk over threshold, error-rate spikes, subsystem error floods,
# stale logs, and failed / restart-looping (zombie) units. Prints a single
# pass/⚠️ report with dedup-friendly output (stable lines → safe to hash for
# alert-once-per-state). Adapted from Rin's live health-monitor.sh +
# monitor-resources.sh; generalized so paths/thresholds are overridable.
#
# Usage:
#   ./monitor.sh                 # one-shot report → exit 0 healthy, 1 if issues
#   ./monitor.sh --quiet         # print ONLY the ⚠️ issue lines (cron/alert mode)
#   ./monitor.sh --state FILE    # write a dedup signature; re-run = "unchanged" if same
#   ./monitor.sh --help
#
# Override via env (defaults shown):
#   SERVICE=openclaw-gateway      # systemd --user unit (host-specific; comment if N/A)
#   WORKSPACE=$HOME/.openclaw/workspace
#   CPU_MAX=80 RAM_MAX=85 DISK_MAX=90   # percent thresholds
#   ERR_MAX=60                    # error log lines/hr before it's a spike
#   WINDOW="60 min ago"           # log scan window
#   STALE_LOGS="health-monitor.log:120"  # space-sep list of name:max_age_minutes under $WORKSPACE
#   SUB_PATTERN="No API key|unavailable|sync failed"  # subsystem-flood signatures
set -uo pipefail
# systemctl --user / journalctl --user need these from a non-login (cron) env.
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:${PATH:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"   # REQUIRED for --user from cron

# ── config (all overridable) ────────────────────────────────────────────────
SERVICE="${SERVICE:-openclaw-gateway}"           # host-specific: the gateway unit
WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
CPU_MAX="${CPU_MAX:-80}"; RAM_MAX="${RAM_MAX:-85}"; DISK_MAX="${DISK_MAX:-90}"
ERR_MAX="${ERR_MAX:-60}"; WINDOW="${WINDOW:-60 min ago}"
STALE_LOGS="${STALE_LOGS:-health-monitor.log:120}"   # name:max_minutes (Rin default; override per host)
SUB_PATTERN="${SUB_PATTERN:-No API key|unavailable|sync failed}"

QUIET=0; STATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet|-q) QUIET=1 ;;
    --state)    STATE="${2:-}"; shift ;;
    --help|-h)  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1 (try --help)" >&2; exit 2 ;;
  esac; shift
done

issues=()   # each entry = one stable, dedup-friendly line (no timestamps inside)
add(){ issues+=("$1"); }
have(){ command -v "$1" >/dev/null 2>&1; }

# ── 1. gateway / process liveness ───────────────────────────────────────────
# Prefer the systemd --user unit; fall back to the CLI, then a process match.
alive=""
if have systemctl && systemctl --user cat "$SERVICE" >/dev/null 2>&1; then
  systemctl --user is-active --quiet "$SERVICE" && alive=1 || add "Gateway DOWN ($SERVICE not active)"
elif have openclaw; then
  openclaw gateway status >/dev/null 2>&1 && alive=1 || add "Gateway DOWN (openclaw gateway status failed)"
elif pgrep -f "openclaw" >/dev/null 2>&1; then
  alive=1
else
  add "Gateway state UNKNOWN (no systemd unit / CLI / process found)"
fi

# ── 2. error-rate spike + 3. subsystem flood (only if we can read the journal)
if have journalctl && [ -n "$alive" ]; then
  errs=$(journalctl --user -u "$SERVICE" --since "$WINDOW" --no-pager 2>/dev/null \
         | grep -icE "error|fatal|exception|unhandled" || true)
  # Empty journal output is SUSPICIOUS (often a missing XDG_RUNTIME_DIR), not healthy.
  if [ -z "$errs" ]; then
    add "Journal unreadable for $SERVICE (check XDG_RUNTIME_DIR / unit name)"
  else
    [ "$errs" -gt "$ERR_MAX" ] && add "High error-rate: ${errs}/hr (> $ERR_MAX)"
    sub=$(journalctl --user -u "$SERVICE" --since "$WINDOW" --no-pager 2>/dev/null \
          | grep -cE "$SUB_PATTERN" || true)
    [ "${sub:-0}" -gt 0 ] && add "Subsystem error flood: ${sub}/hr [$SUB_PATTERN]"
  fi
fi

# ── 4. failed / restart-looping units (zombies) ─────────────────────────────
if have systemctl; then
  uf=$(systemctl --user list-units --all --no-legend 2>/dev/null | grep -icE "failed|auto-restart" || true)
  sf=$(systemctl --failed --no-legend 2>/dev/null | grep -c "\.service" || true)
  { [ "${uf:-0}" -gt 0 ] || [ "${sf:-0}" -gt 0 ]; } && add "Failed/restart-looping units: user=$uf system=$sf"
fi

# ── 5. disk ─────────────────────────────────────────────────────────────────
dp=$(df / --output=pcent 2>/dev/null | tail -1 | tr -dc '0-9')
[ "${dp:-0}" -gt "$DISK_MAX" ] && add "Disk ${dp}% (> $DISK_MAX%)"

# ── 6. RAM ──────────────────────────────────────────────────────────────────
if have free; then
  read -r mt mu < <(free | awk '/^Mem:/{print $2, $3}')
  [ "${mt:-0}" -gt 0 ] && { mp=$((mu*100/mt)); [ "$mp" -gt "$RAM_MAX" ] && add "RAM ${mp}% (> $RAM_MAX%)"; }
fi

# ── 7. CPU load vs cores ────────────────────────────────────────────────────
if [ -r /proc/loadavg ] && have nproc; then
  l1=$(cut -d' ' -f1 /proc/loadavg); cores=$(nproc)
  cp=$(awk -v l="$l1" -v c="$cores" 'BEGIN{printf "%d", (l/c)*100}')
  [ "${cp:-0}" -gt "$CPU_MAX" ] && add "CPU load ${cp}% of ${cores} cores (> $CPU_MAX%)"
fi

# ── 8. stale logs (a cron that quietly stopped writing) ─────────────────────
now=$(date +%s)
for spec in $STALE_LOGS; do
  name="${spec%%:*}"; maxm="${spec##*:}"; lf="$WORKSPACE/memory/$name"
  [ -f "$lf" ] || { add "Log missing: memory/$name (cron may not be running)"; continue; }
  age=$(( (now - $(stat -c %Y "$lf" 2>/dev/null || echo "$now")) / 60 ))
  [ "$age" -gt "$maxm" ] && add "Stale log: memory/$name last written ${age}m ago (> ${maxm}m)"
done

# ── report (dedup-friendly: stable lines, timestamp only in the header) ──────
ts=$(date -u '+%Y-%m-%d %H:%M UTC')
if [ "${#issues[@]}" -eq 0 ]; then
  [ "$QUIET" -eq 1 ] || echo "✅ self-monitoring: all clear — $ts (gateway up, CPU/RAM/disk/logs/units nominal)"
  rc=0
else
  [ "$QUIET" -eq 1 ] || echo "⚠️  self-monitoring: ${#issues[@]} issue(s) — $ts"
  for i in "${issues[@]}"; do echo "• $i"; done
  rc=1
fi

# Dedup signature: "CLEAN" when healthy, else a hash of the SORTED issue lines
# (order- and time-independent). Compare to the previous run to decide whether a
# human should be paged — so a persistent problem alerts ONCE, not every run.
if [ -n "$STATE" ]; then
  if [ "${#issues[@]}" -eq 0 ]; then sig="CLEAN"
  else sig=$(printf '%s\n' "${issues[@]}" | sort | sha1sum 2>/dev/null | cut -d' ' -f1); fi
  prev=$(cat "$STATE" 2>/dev/null || echo CLEAN)
  printf '%s' "$sig" > "$STATE"
  if [ "$sig" != "CLEAN" ] && [ "$sig" = "$prev" ]; then
    echo "↳ same issue-set as last run — dedup: do NOT re-alert."
  elif [ "$sig" != "CLEAN" ]; then
    echo "↳ new/changed issue-set — ALERT the human once."
  elif [ "$prev" != "CLEAN" ]; then
    echo "↳ recovered since last run — send ONE '✅ recovered' notice."
  fi
fi
exit $rc
