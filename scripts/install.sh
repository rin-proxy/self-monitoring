#!/usr/bin/env bash
# <skill> — activation script (run ONCE after install). Idempotent + reversible.
# State is written OUTSIDE the skill folder (into the workspace) so reinstall/upgrade
# never destroys your data. Slug is read automatically from SKILL.md `name:`.
#
# Usage: bash scripts/install.sh [--workspace DIR] [--no-agents] [--force]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
SLUG="$(sed -n 's/^name:[[:space:]]*//p' "$SKILL_DIR/SKILL.md" | head -1 | sed 's/[[:space:]]*#.*//;s/[[:space:]]*$//')"; SLUG="${SLUG:-my-skill}"
DO_AGENTS=1; FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WS="$2"; shift 2;;
    --no-agents) DO_AGENTS=0; shift;;
    --force)     FORCE=1; shift;;
    -h|--help)   grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

ok(){   printf '  \033[32m[ok]\033[0m   %s\n' "$*"; }
skip(){ printf '  \033[33m[skip]\033[0m %s\n' "$*"; }
hr(){   printf '\033[1m== %s ==\033[0m\n' "$*"; }

[ -d "$WS" ] || { echo "Workspace not found: $WS  (pass --workspace DIR)" >&2; exit 1; }
chmod +x "$SKILL_DIR/scripts/"*.sh 2>/dev/null || true

echo; hr "$SLUG -> $WS"

# ── 1) (EDIT) scaffold any workspace state your skill needs ────────────────────
# State lives in the WORKSPACE so upgrades never wipe it. Uncomment + adjust:
# for d in "memory/$SLUG"; do
#   if [ -d "$WS/$d" ]; then skip "$d/"; else mkdir -p "$WS/$d"; ok "$d/"; fi
# done

# ── 2) (EDIT, optional) enable a hook your skill ships ─────────────────────────
# if command -v openclaw >/dev/null 2>&1; then
#   openclaw hooks enable <your-hook-id> >/dev/null 2>&1 && ok "hook enabled" \
#     || skip "enable manually: openclaw hooks enable <your-hook-id>"
# fi

# ── 3) wire a usage pointer into AGENTS.md (idempotent, marker-fenced, backed up)
if [ "$DO_AGENTS" = 1 ]; then
  AGENTS="$WS/AGENTS.md"
  BEGIN="<!-- BEGIN:$SLUG (managed — do not edit between markers) -->"
  END="<!-- END:$SLUG -->"
  BLOCK="$BEGIN
## $SLUG
- **self-monitoring** — Watchdog for an OpenClaw agent that catches the silent degradation an "is it up?" check misses — gateway/process down, CPU/RAM/disk over threshold, error-rate spikes,… (details in `skills/self-monitoring/SKILL.md`)
$END"
  touch "$AGENTS"
  if grep -qF "$BEGIN" "$AGENTS" 2>/dev/null; then
    if [ "$FORCE" = 1 ]; then
      cp "$AGENTS" "$AGENTS.bak.$(date -u +%Y%m%d%H%M%S 2>/dev/null || echo bak)"
      awk -v b="$BEGIN" -v e="$END" -v repl="$BLOCK" '
        $0==b {print repl; skip=1; next} $0==e {skip=0; next} !skip {print}' \
        "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS"
      ok "AGENTS.md block refreshed (--force)"
    else
      skip "AGENTS.md already wired (use --force to refresh)"
    fi
  else
    printf '\n%s\n' "$BLOCK" >> "$AGENTS"; ok "AGENTS.md block appended"
  fi
fi

echo; hr "done"
echo "Undo: bash $SKILL_DIR/scripts/uninstall.sh --workspace $WS"
