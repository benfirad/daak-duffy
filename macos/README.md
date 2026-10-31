# DAAK Duffy for macOS

A native menu bar app for Duffy. Talk to your agents, queue background tasks, and approve
risky steps without opening a browser. The interface is in Turkish.

Requires macOS 13 or newer and the Xcode Command Line Tools. No Xcode project, no dependencies.

## Build and install

```bash
cd macos
./build.command               # builds, installs to /Applications and starts it
./build.command --no-install  # only builds into macos/build/
```

If a LaunchAgent named `app.daakduffy.system-ui` exists, the script stops it before
swapping the bundle and starts it again afterwards. Override the label with
`DUFFY_APP_LABEL` and the install path with `DUFFY_APP_DEST`.

## Screens

| Screen | What it does |
|---|---|
| **Agents** (main window and menu bar popover) | Every agent with its last message or task, a live status dot from the office panel, and one line with connection, queue and warnings. A banner appears when something waits for approval. |
| **Chat** | Day separators, Markdown replies (headings, lists, bold, links), suggested first questions, typing indicator. *Background task* turns what you typed into a queued task instead of a chat message. Right-click a message to copy it or turn it into a task. |
| **Console → Overview** | Connection, running tasks, pending approvals and service warnings, plus what needs your attention and the latest tasks. |
| **Console → Tasks** | Add tasks for any agent, filter by status or agent, search titles, reports and `#numbers`, expand long reports, retry. |
| **Console → Approvals** | The exact command the agent wants to run. Approving asks once more before it runs. |
| **Console → Agent Office / Services** | Cards from `office.py` with problems first; launchd services split into running, failing and idle. |
| **Console → Commands** | Copyable CLI commands. |

The menu bar icon shows the number of pending approvals. Left click opens the agents,
right click opens the console.

## Configuration

Without a config file the app connects to Duffy on `127.0.0.1:8899` and lists the chat
personas the server reports. To set server addresses and your own characters, copy
[`app.example.json`](app.example.json) to `~/.duffy/app.json` (or point `DUFFY_APP_CONFIG`
at another file).

| Key | Meaning |
|---|---|
| `hosts` | Addresses tried in order; the app moves to the next one when a request fails (for example a cable link first, then a VPN). |
| `duffyPort`, `officePort` | Ports of `duffy.py` (8899) and `office.py` (8900). |
| `hostLabel`, `linkLabels` | Names shown in the status line, such as "Home server · VPN". |
| `chief`, `agents` | Characters. `id` must match the persona and task category on the server. `color` is a hex colour, `shape` is 0–2, `suggestions` are the first-question buttons. |
| `agents[].office` | Office panel entries that drive the agent's status dot: an entry id such as `"health"`, or `"name:email"` to match by name. |
| `commands` | Entries on the Commands page. |

Keep personal names, addresses and greetings in `~/.duffy/app.json`; the file is never
part of the repository.
