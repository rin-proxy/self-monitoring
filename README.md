# 🩺 self-monitoring

> 🔒 **Diaudit & aman** — lolos skill-gate 100/100 · berjalan **lokal-saja**: tanpa panggilan jaringan, tanpa `eval`/kode ter-obfuscate. Semua kode terbuka & bisa kamu verifikasi sendiri. _(Audit keamanan: 2026-07-17)_

Watchdog for an OpenClaw agent that catches the silent degradation an "is it up?" check misses — gateway/process down, CPU/RAM/disk over threshold, error-rate spikes, subsystem error floods, stale logs, and failed/restart-looping units. Ships a helper that prints a dedup-friendly pass/⚠️ report so a persistent problem alerts once. Use when checking agent health, wiring an hourly watchdog, or debugging a process that's "up" but rotting.

**Version:** 1.0.0 · **Triggers:** check agent health, is it still running, monitor resources, set up a watchdog, why is the gateway slow, is the agent degrading

## Usage
Full guide and procedure: see **SKILL.md**. Bundled scripts (if any) live in **scripts/**; deep reference material in **references/** (loaded on demand).

## Install
    openclaw skills install git:rin-proxy/self-monitoring

Or copy this folder into your OpenClaw workspace/skills/ directory.

---
*README for the self-monitoring skill. The authoritative contract is SKILL.md.*
