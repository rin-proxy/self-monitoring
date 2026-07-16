# Changelog — self-monitoring

## 1.0.0 (2026-06-17)
- Initial release. Watchdog (`scripts/monitor.sh`) that detects silent degradation an up/down probe misses: gateway/process liveness, error-rate spikes, subsystem floods, failed/restart-looping units, disk/RAM/CPU thresholds, and stale logs.
- Dedup-by-state-file so a persistent issue alerts once (new → ALERT, same → dedup, cleared → recovered).
- All host-specific paths/thresholds overridable via env vars; deep reference in `references/monitoring-guide.md`.
- Derived from the `agent-self-monitoring-and-alerting` Tower book + Rin's live health-monitor / monitor-resources scripts. The authoritative contract is SKILL.md.
