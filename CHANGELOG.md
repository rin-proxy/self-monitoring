# Changelog — self-monitoring

## 1.1.0 (2026-07-17)
- Wired to the fleet blackboard: when the watchdog flags a real issue on cron, file it to proactive-partner's inbox (inbox.sh add self-monitoring ...) so a silent-turn finding survives to the next triage instead of evaporating.

## 1.0.0 (2026-06-17)
- Initial release. Watchdog (`scripts/monitor.sh`) that detects silent degradation an up/down probe misses: gateway/process liveness, error-rate spikes, subsystem floods, failed/restart-looping units, disk/RAM/CPU thresholds, and stale logs.
- Dedup-by-state-file so a persistent issue alerts once (new → ALERT, same → dedup, cleared → recovered).
- All host-specific paths/thresholds overridable via env vars; deep reference in `references/monitoring-guide.md`.
- Derived from the `agent-self-monitoring-and-alerting` Tower book + Rin's live health-monitor / monitor-resources scripts. The authoritative contract is SKILL.md.
