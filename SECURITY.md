# Security policy

Duffy runs commands on your machine, so security reports matter.

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private
[security advisory form](https://github.com/benfirad/daak-duffy/security/advisories/new)
instead. Include steps to reproduce and the version you tested. You will get an answer
within a week.

## In scope

- A way to run a command that asked for approval without it being approved.
- Reaching the dashboard or API from an address that `bind_hosts` / `allowed_clients` should block.
- Prompt or task content that escapes the task workspace or the approval gate.

## Out of scope

- Whatever the agent CLI you configure is allowed to do on its own.
- Exposing the dashboard to the internet; the README asks you not to.
