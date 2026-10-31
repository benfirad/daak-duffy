# Contributing

Thanks for helping. Duffy stays small on purpose, so a few ground rules:

- **No new dependencies** in `duffy.py` or `office.py`: Python 3.9+ standard library only.
- **Safety first.** Changes must keep the approval gate intact: nothing that asked for approval may run without it, and the dashboard stays on loopback by default.
- **Tests.** Run `python3 -m unittest discover -s tests` before opening a pull request, and add a test for new behaviour.
- **macOS app.** `cd macos && ./build.command --no-install` must build without warnings. Put every user-facing string through `L("Türkçe", "English")`.
- **No personal data** in code, examples or screenshots. Use `example.com` addresses and made-up names.

## Reporting a bug

Open an issue with what you ran, what you expected, what happened, and your OS and Python
version. For anything security-related, see [SECURITY.md](SECURITY.md) instead.

## Pull requests

Keep them focused on one change, describe why, and add a line to `CHANGELOG.md`.
