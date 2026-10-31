# Changelog

## 0.2.0 — 2026-10-31

Rewritten from the version that has been running 24/7 on a home server.

- Agent command is now configurable (`agy`, `claude -p`, `ollama run`, …) with per-model fallback and quota detection.
- Approval gate driven by the agent's own `[APPROVAL_REQUIRED: … | CMD: …]` line; the exact command is shown before it can run, and `approve` refuses tasks that never asked.
- A failed approved command now reports its exit code instead of "completed (no output)".
- Dashboard listens on `127.0.0.1` by default; extra addresses via `bind_hosts`, client filter via `allowed_clients`. Addresses that are not up yet at boot (VPNs) are retried every minute.
- Webhook notification failures are logged instead of silently ignored.
- Chat personas, JSON API, `show` and `step` commands, light/dark dashboard.
- New: `office.py` panel and `bin/ai` (Claude → Antigravity fallback).
- Tests (`python3 -m unittest discover -s tests`).
- The v0.1 forms `add -p "…"` and `approve --id N` still work.

## 0.1.0

Initial release.
