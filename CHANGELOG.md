# Changelog

## 0.3.2 — 2026-11-01

- Fix: the macOS app showed the server as offline whenever it had to use a VPN address. `NSAllowsLocalNetworking` made macOS ignore `NSAllowsArbitraryLoads`, so plain HTTP to Tailscale-style `100.x` addresses was blocked; only the local-network setting is gone now.
- Fix: overlapping refreshes no longer flip the app back to an address that just failed. Every refresh tries all `hosts` in turn, stays on the one that answered and rechecks the first one once a minute.
- New: optional `devices` in `~/.duffy/app.json` show other machines as up/down chips on the Overview page (TCP check on a port you choose).
- New: optional `kasaPort` shows an expense web panel as an Expenses page inside the console.

## 0.3.1 — 2026-10-31

- macOS app speaks English, or Turkish when that is the system language (`"language"` in `~/.duffy/app.json` overrides).
- The app now reads `office.py` from this repository: Duffy status and health checks show up as cards and drive the agents' status dots (`"health:<name>"`).
- New project website (GitHub Pages, `docs/`), screenshots in the README, CI for tests and the app build, contributing and security guides, issue templates.
- `duffy.py --version` reports the release version.

## 0.3.0 — 2026-10-31

- New: native macOS menu bar app in `macos/` (agents, chat, console with overview, tasks, approvals, office panel, services and commands).
- Approving a command from the app asks for confirmation and shows the exact command.
- Characters, server addresses and commands come from `~/.duffy/app.json`; without it the app uses the personas the server reports.
- The app accepts both task field names (`result` / `result_summary`, `approval_summary` / `approval_Action`).
- `build.command` stops the LaunchAgent before swapping the bundle; replacing a running app made macOS kill it for an invalid signature.

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
