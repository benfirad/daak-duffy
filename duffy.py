#!/usr/bin/env python3
"""
DAAK Duffy — a 24/7 background AI worker with a human approval gate.

Duffy keeps a SQLite task queue, runs each task through a CLI agent
(Antigravity `agy`, `claude -p`, `ollama run`, ...) with automatic model
fallback, and pauses any risky step until a human approves it from the web
dashboard, the CLI or a chat bridge.

Task life cycle:
    pending -> running -> done
                       -> awaiting_approval -> approved -> running -> done / failed
                                            -> rejected
                       -> failed  (retry puts it back to pending)

The agent asks for approval by ending its answer with
    [APPROVAL_REQUIRED: <what and why> | CMD: <shell command>]
Duffy never runs that command until someone approves the task.

Standard library only, Python 3.9+. Configuration: see config.example.json.
"""
from __future__ import annotations

import argparse
import html
import ipaddress
import json
import os
import re
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

__version__ = "0.2.0"

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

HOME = os.path.expanduser(os.environ.get("DUFFY_HOME", "~/.duffy"))

DEFAULTS: dict = {
    # Loopback only by default. Add a VPN / LAN address explicitly if you need it.
    "bind_hosts": ["127.0.0.1"],
    "port": 8899,
    # Empty list = allow every client that can reach a bound address.
    "allowed_clients": [],
    "db_path": os.path.join(HOME, "duffy.db"),
    "workspace_dir": os.path.join(HOME, "workspaces"),
    "poll_seconds": 12,
    # Agent command; {model}, {prompt} and {workspace} are substituted per run.
    "agent_command": ["agy", "--model", "{model}", "-p", "{prompt}"],
    "models": ["default"],
    "agent_timeout_seconds": 300,
    # Output fragments that mean "this model is out of quota, try the next one".
    "quota_markers": ["RESOURCE_EXHAUSTED", "quota", "rate limit", "usage limit"],
    "approved_command_timeout_seconds": 120,
    "notify": {
        # POSTs {"chatId": chat_id, "message": text} — fits WhatsApp/Telegram bridges.
        "webhook_url": "",
        "chat_id": "",
    },
    "system_prompt": (
        "You are Duffy, an autonomous background worker. Finish routine work on your own. "
        "If a step is risky or irreversible (sending messages or email, payments, deleting data, "
        "deploying), do not do it: end your answer with "
        "[APPROVAL_REQUIRED: <what and why> | CMD: <exact shell command>]."
    ),
    # Optional chat personas: {"id": {"name": "...", "prompt": "..."}}
    "agents": {
        "duffy": {"name": "Duffy", "prompt": "You are Duffy, a concise and practical operations assistant."},
    },
}


def load_config() -> dict:
    cfg = json.loads(json.dumps(DEFAULTS))
    path = os.environ.get("DUFFY_CONFIG", os.path.join(HOME, "config.json"))
    if os.path.exists(path):
        with open(path) as f:
            user = json.load(f)
        for key, value in user.items():
            if isinstance(value, dict) and isinstance(cfg.get(key), dict):
                cfg[key].update(value)
            else:
                cfg[key] = value
    for key in ("db_path", "workspace_dir"):
        cfg[key] = os.path.expanduser(cfg[key])
    if os.environ.get("DUFFY_PORT"):
        cfg["port"] = int(os.environ["DUFFY_PORT"])
    if os.environ.get("DUFFY_BIND"):
        cfg["bind_hosts"] = [h.strip() for h in os.environ["DUFFY_BIND"].split(",") if h.strip()]
    return cfg


CFG = load_config()
APPROVAL_RE = re.compile(
    r"\[(?:APPROVAL_REQUIRED|ONAY_GEREKL[İI])\s*:\s*(.+?)\s*\|\s*(?:CMD|KOMUT)\s*:\s*(.+?)\]",
    re.DOTALL,
)


def now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


# --------------------------------------------------------------------------
# Storage
# --------------------------------------------------------------------------

def db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(CFG["db_path"]), exist_ok=True)
    conn = sqlite3.connect(CFG["db_path"], timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            category TEXT DEFAULT 'general',
            status TEXT DEFAULT 'pending',
            model_used TEXT,
            result TEXT,
            approval_summary TEXT,
            approval_cmd TEXT,
            created_at TEXT,
            updated_at TEXT,
            completed_at TEXT
        );
        CREATE TABLE IF NOT EXISTS logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_id INTEGER NOT NULL,
            level TEXT DEFAULT 'INFO',
            message TEXT NOT NULL,
            created_at TEXT
        );
        CREATE TABLE IF NOT EXISTS chats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            agent_id TEXT NOT NULL,
            sender TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TEXT
        );
        """
    )
    return conn


def log(task_id: int, message: str, level: str = "INFO") -> None:
    with db() as conn:
        conn.execute(
            "INSERT INTO logs (task_id, level, message, created_at) VALUES (?, ?, ?, ?)",
            (task_id, level, message, now_str()),
        )


def add_task(title: str, category: str = "general") -> int:
    ts = now_str()
    with db() as conn:
        tid = conn.execute(
            "INSERT INTO tasks (title, category, status, created_at, updated_at) VALUES (?, ?, 'pending', ?, ?)",
            (title, category, ts, ts),
        ).lastrowid
    log(tid, f"Queued (category={category}).")
    return tid


def set_status(tid: int, status: str, note: str, allowed_from: tuple = ()) -> bool:
    with db() as conn:
        row = conn.execute("SELECT status FROM tasks WHERE id = ?", (tid,)).fetchone()
        if not row or (allowed_from and row["status"] not in allowed_from):
            return False
        done = now_str() if status in ("done", "failed", "rejected") else None
        conn.execute(
            "UPDATE tasks SET status = ?, updated_at = ?, completed_at = COALESCE(?, completed_at) WHERE id = ?",
            (status, now_str(), done, tid),
        )
    log(tid, note)
    return True


def approve(tid: int) -> bool:
    return set_status(tid, "approved", "Approved by a human.", ("awaiting_approval",))


def reject(tid: int) -> bool:
    return set_status(tid, "rejected", "Rejected by a human.", ("awaiting_approval", "pending"))


def retry(tid: int) -> bool:
    return set_status(tid, "pending", "Re-queued.", ("failed", "rejected", "done"))


# --------------------------------------------------------------------------
# Notifications
# --------------------------------------------------------------------------

def notify(text: str) -> bool:
    url, chat = CFG["notify"].get("webhook_url"), CFG["notify"].get("chat_id")
    if not url:
        return False
    body = json.dumps({"chatId": chat, "message": text}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status in (200, 201, 204):
                return True
            sys.stderr.write(f"[duffy] notify HTTP {resp.status}\n")
    except Exception as e:
        sys.stderr.write(f"[duffy] notify failed: {e}\n")
    return False


# --------------------------------------------------------------------------
# Agent execution
# --------------------------------------------------------------------------

def build_command(model: str, prompt: str, workspace: str) -> list:
    return [
        part.replace("{model}", model).replace("{prompt}", prompt).replace("{workspace}", workspace)
        for part in CFG["agent_command"]
    ]


def run_agent(prompt: str, task_id: int) -> tuple:
    """Returns (output, model). Walks the model list until one answers."""
    workspace = os.path.join(CFG["workspace_dir"], f"task_{task_id}")
    os.makedirs(workspace, exist_ok=True)
    markers = [m.lower() for m in CFG["quota_markers"]]
    last_error = ""
    for model in CFG["models"]:
        log(task_id, f"Running model {model}...")
        try:
            res = subprocess.run(
                build_command(model, prompt, workspace),
                cwd=workspace, capture_output=True, text=True,
                timeout=CFG["agent_timeout_seconds"],
            )
        except Exception as e:
            last_error = str(e)
            log(task_id, f"Model {model} failed: {last_error[:160]}", "WARN")
            continue
        out = (res.stdout or "").strip()
        if res.returncode == 0 and out and not (len(out) < 400 and any(m in out.lower() for m in markers)):
            return out, model
        last_error = (res.stderr or out or f"exit {res.returncode}").strip()
        log(task_id, f"Model {model} unavailable ({last_error[:160]}), trying next.", "WARN")
    raise RuntimeError(f"All models failed: {last_error[:300]}")


def task_prompt(row: sqlite3.Row) -> str:
    workspace = os.path.join(CFG["workspace_dir"], f"task_{row['id']}")
    return (
        f"{CFG['system_prompt']}\n\n"
        f"Task #{row['id']} (category: {row['category']}):\n{row['title']}\n\n"
        f"Working directory for files you create: {workspace}\n"
        f"Reply with a short report of what you did and found."
    )


def run_approved(row: sqlite3.Row) -> None:
    tid, cmd = row["id"], (row["approval_cmd"] or "").strip()
    set_status(tid, "running", f"Running approved command: {cmd}")
    workspace = os.path.join(CFG["workspace_dir"], f"task_{tid}")
    os.makedirs(workspace, exist_ok=True)
    try:
        res = subprocess.run(
            cmd, shell=True, cwd=workspace, capture_output=True, text=True,
            timeout=CFG["approved_command_timeout_seconds"],
        )
        status = "done" if res.returncode == 0 else "failed"
        output = ((res.stdout or "") + ("\n" + res.stderr if res.stderr else "")).strip()
        if not output:
            output = "Completed (no output)." if status == "done" else f"Failed without output (exit {res.returncode})."
    except Exception as e:
        status, output = "failed", f"Error: {e}"
    with db() as conn:
        conn.execute(
            "UPDATE tasks SET result = COALESCE(result, '') || ? WHERE id = ?",
            (f"\n\n[APPROVED COMMAND RESULT]\n{output}", tid),
        )
    set_status(tid, status, f"Approved command finished ({status}): {output[:300]}")
    notify(f"Duffy #{tid} {'done' if status == 'done' else 'FAILED'}: {row['title']}\n\n{output[:1500]}")


def process_one() -> bool:
    with db() as conn:
        row = conn.execute("SELECT * FROM tasks WHERE status = 'approved' ORDER BY id LIMIT 1").fetchone()
    if row:
        run_approved(row)
        return True

    with db() as conn:
        row = conn.execute("SELECT * FROM tasks WHERE status = 'pending' ORDER BY id LIMIT 1").fetchone()
    if not row:
        return False
    tid = row["id"]
    set_status(tid, "running", f"Started: {row['title']}")
    try:
        output, model = run_agent(task_prompt(row), tid)
    except Exception as e:
        with db() as conn:
            conn.execute("UPDATE tasks SET result = ? WHERE id = ?", (f"Error: {e}", tid))
        set_status(tid, "failed", f"Task failed: {e}", ())
        return True

    match = APPROVAL_RE.search(output)
    report = output[: match.start()].strip() if match else output
    with db() as conn:
        conn.execute(
            "UPDATE tasks SET model_used = ?, result = ?, approval_summary = ?, approval_cmd = ? WHERE id = ?",
            (model, report, match.group(1).strip() if match else None,
             match.group(2).strip() if match else None, tid),
        )
    if match:
        set_status(tid, "awaiting_approval", f"Waiting for approval: {match.group(1).strip()}")
        notify(
            f"Duffy #{tid} needs your approval\n{row['title']}\n\n{report[:1500]}\n\n"
            f"Action: {match.group(1).strip()}\nCommand: {match.group(2).strip()}\n\n"
            f"Approve: duffy approve {tid}   Reject: duffy reject {tid}"
        )
    else:
        set_status(tid, "done", "Completed.")
        notify(f"Duffy #{tid} done ({model}): {row['title']}\n\n{report[:2500]}")
    return True


def chat_reply(agent_id: str, message: str) -> None:
    agent = CFG["agents"].get(agent_id) or {"name": agent_id, "prompt": ""}
    with db() as conn:
        history = conn.execute(
            "SELECT sender, message FROM chats WHERE agent_id = ? ORDER BY id DESC LIMIT 8", (agent_id,)
        ).fetchall()
    transcript = "\n".join(f"{h['sender']}: {h['message']}" for h in reversed(history))
    prompt = f"{agent['prompt']}\n\nConversation so far:\n{transcript}\n\nReply to the last user message."
    try:
        reply, _ = run_agent(prompt, 0)
    except Exception as e:
        reply = f"(no model available: {e})"
    with db() as conn:
        conn.execute(
            "INSERT INTO chats (agent_id, sender, message, created_at) VALUES (?, 'agent', ?, ?)",
            (agent_id, reply, now_str()),
        )


# --------------------------------------------------------------------------
# Web dashboard + JSON API
# --------------------------------------------------------------------------

def client_allowed(ip: str) -> bool:
    allowed = CFG["allowed_clients"]
    if not allowed or ip in ("127.0.0.1", "::1"):
        return True
    addr = ipaddress.ip_address(ip)
    return any(addr in ipaddress.ip_network(a, strict=False) for a in allowed)


def status_payload() -> dict:
    with db() as conn:
        tasks = [dict(r) for r in conn.execute("SELECT * FROM tasks ORDER BY id DESC LIMIT 50")]
        chats = [dict(r) for r in conn.execute("SELECT * FROM chats ORDER BY id DESC LIMIT 300")][::-1]
    agents = {k: v.get("name", k) for k, v in CFG["agents"].items()}
    return {"status": "ok", "version": __version__, "tasks": tasks, "chats": chats, "agents": agents}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send(self, code: int, ctype: str, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _guard(self) -> bool:
        if client_allowed(self.client_address[0]):
            return True
        self._send(403, "text/plain", b"forbidden")
        return False

    def do_GET(self):
        if not self._guard():
            return
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/status":
            self._send(200, "application/json", json.dumps(status_payload(), ensure_ascii=False).encode())
        elif path == "/api/logs":
            tid = int(urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("id", ["0"])[0])
            with db() as conn:
                rows = [dict(r) for r in conn.execute("SELECT * FROM logs WHERE task_id = ? ORDER BY id", (tid,))]
            self._send(200, "application/json", json.dumps(rows, ensure_ascii=False).encode())
        elif path in ("/", "/index.html"):
            self._send(200, "text/html; charset=utf-8", PAGE.encode())
        else:
            self._send(404, "text/plain", b"not found")

    def do_POST(self):
        if not self._guard():
            return
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0") or 0)).decode()
        if "json" in (self.headers.get("Content-Type") or ""):
            params = json.loads(raw or "{}")
        else:
            params = {k: v[0] for k, v in urllib.parse.parse_qs(raw).items()}
        path = urllib.parse.urlparse(self.path).path.replace("/api/", "/")
        ok = False
        if path == "/add" and str(params.get("title", "")).strip():
            ok = bool(add_task(str(params["title"]).strip(), str(params.get("category", "general"))))
        elif path in ("/approve", "/reject", "/retry"):
            ok = {"/approve": approve, "/reject": reject, "/retry": retry}[path](int(params.get("id", 0)))
        elif path == "/chat" and str(params.get("message", "")).strip():
            agent_id = str(params.get("agent_id", "duffy"))
            with db() as conn:
                conn.execute(
                    "INSERT INTO chats (agent_id, sender, message, created_at) VALUES (?, 'user', ?, ?)",
                    (agent_id, str(params["message"]).strip(), now_str()),
                )
            threading.Thread(target=chat_reply, args=(agent_id, str(params["message"])), daemon=True).start()
            ok = True
        if "json" in (self.headers.get("Accept") or "") or "json" in (self.headers.get("Content-Type") or ""):
            self._send(200 if ok else 400, "application/json", json.dumps({"ok": ok}).encode())
        else:
            self.send_response(303)
            self.send_header("Location", "/")
            self.end_headers()


PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Duffy</title>
<style>
:root{--bg:#0e1013;--card:#161a20;--line:#262c35;--text:#e7eaee;--mute:#8b94a3;--ok:#3fb27f;--warn:#e0a83b;--bad:#e2555a;--acc:#f59e0b}
@media(prefers-color-scheme:light){:root{--bg:#f6f7f9;--card:#fff;--line:#e3e6ea;--text:#16191d;--mute:#5f6773}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 -apple-system,system-ui,sans-serif}
header{display:flex;gap:12px;align-items:center;padding:14px 20px;border-bottom:1px solid var(--line)}
h1{font-size:17px;margin:0}.mute{color:var(--mute);font-size:12px}main{max-width:1000px;margin:auto;padding:16px 20px}
form.new{display:flex;gap:8px;margin-bottom:16px}input,select{background:var(--card);color:var(--text);border:1px solid var(--line);border-radius:7px;padding:8px}
input{flex:1}button{border:0;border-radius:7px;padding:7px 12px;cursor:pointer;background:var(--line);color:var(--text)}
.go{background:var(--ok);color:#fff}.no{background:var(--bad);color:#fff}.add{background:var(--acc);color:#111}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;margin-bottom:10px}
.row{display:flex;gap:8px;align-items:center;justify-content:space-between;flex-wrap:wrap}
.pill{font-size:11px;padding:2px 8px;border-radius:9px;background:var(--line)}
.awaiting_approval{background:#5c4615;color:#ffd27a}.done{color:var(--ok)}.failed,.rejected{color:var(--bad)}.running{color:#6aa7ff}
pre{white-space:pre-wrap;background:rgba(0,0,0,.25);padding:10px;border-radius:8px;font-size:12px;max-height:280px;overflow:auto}
.gate{border:1px solid #5c4615;background:rgba(224,168,59,.08);border-radius:8px;padding:10px;margin-top:8px}
</style></head><body>
<header><h1>🦆 Duffy</h1><span class="mute" id="meta"></span></header>
<main>
<form class="new" onsubmit="add(event)"><select id="cat"><option>general</option><option>research</option><option>code</option><option>ops</option></select>
<input id="title" placeholder="What should Duffy do while you're away?"><button class="add">Queue</button></form>
<div id="tasks"></div></main>
<script>
const esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function post(p,b){await fetch('/api'+p,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(b)});load()}
function add(e){e.preventDefault();const t=document.getElementById('title');if(!t.value.trim())return;post('/add',{title:t.value,category:document.getElementById('cat').value});t.value=''}
async function load(){const d=await (await fetch('/api/status')).json();
document.getElementById('meta').textContent=`v${d.version} · ${d.tasks.filter(t=>t.status==='awaiting_approval').length} awaiting approval`;
document.getElementById('tasks').innerHTML=d.tasks.map(t=>`<div class="card"><div class="row"><b>#${t.id} ${esc(t.title)}</b>
<span class="pill ${t.status}">${t.status}</span></div><div class="mute">${esc(t.category)} · ${esc(t.created_at)} · ${esc(t.model_used||'—')}</div>
${t.status==='awaiting_approval'?`<div class="gate"><b>Approval needed:</b> ${esc(t.approval_summary)}<pre>${esc(t.approval_cmd)}</pre>
<button class="go" onclick="confirm('Run this command?')&&post('/approve',{id:${t.id}})">Approve & run</button> <button class="no" onclick="post('/reject',{id:${t.id}})">Reject</button></div>`:''}
${t.result?`<pre>${esc(t.result)}</pre>`:''}${['failed','rejected','done'].includes(t.status)?`<button onclick="post('/retry',{id:${t.id}})">Retry</button>`:''}</div>`).join('')||'<p class="mute">Queue is empty.</p>'}
load();setInterval(load,5000);
</script></body></html>"""


def serve() -> None:
    pending = list(CFG["bind_hosts"])
    while pending:
        for host in list(pending):
            try:
                server = ThreadingHTTPServer((host, CFG["port"]), Handler)
            except OSError as e:
                sys.stderr.write(f"[duffy] cannot bind {host}:{CFG['port']}: {e}\n")
                continue
            threading.Thread(target=server.serve_forever, daemon=True).start()
            pending.remove(host)
            print(f"🦆 Duffy dashboard on http://{host}:{CFG['port']}", flush=True)
        if pending:
            time.sleep(60)  # VPN interfaces may come up after boot


def daemon() -> None:
    threading.Thread(target=serve, daemon=True).start()
    while True:
        try:
            worked = process_one()
        except Exception as e:
            sys.stderr.write(f"[duffy] loop error: {e}\n")
            worked = False
        time.sleep(3 if worked else CFG["poll_seconds"])


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def main(argv: list | None = None) -> None:
    p = argparse.ArgumentParser(prog="duffy", description="Duffy — background AI worker with approval gate")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd")
    a = sub.add_parser("add", help="queue a task")
    a.add_argument("title", nargs="?")
    a.add_argument("-p", "--prompt", dest="prompt_opt", help=argparse.SUPPRESS)  # v0.1 compatibility
    a.add_argument("-c", "--category", default="general")
    sub.add_parser("list", help="show recent tasks")
    s = sub.add_parser("show", help="show one task with its log")
    s.add_argument("id", type=int)
    for name in ("approve", "reject", "retry"):
        x = sub.add_parser(name)
        x.add_argument("id", type=int, nargs="?")
        x.add_argument("--id", dest="id_opt", type=int, help=argparse.SUPPRESS)  # v0.1 compatibility
    sub.add_parser("step", help="process one task and exit")
    sub.add_parser("daemon", help="run worker + dashboard")
    args = p.parse_args(argv)

    if args.cmd == "add":
        title = args.title or args.prompt_opt
        if not title:
            p.error("add needs a task description")
        print(f"🦆 queued #{add_task(title, args.category)}")
    elif args.cmd == "list":
        with db() as conn:
            for r in conn.execute("SELECT * FROM tasks ORDER BY id DESC LIMIT 20"):
                print(f"#{r['id']:<4} {r['status']:<18} [{r['category']}] {r['title'][:90]}")
    elif args.cmd == "show":
        with db() as conn:
            r = conn.execute("SELECT * FROM tasks WHERE id = ?", (args.id,)).fetchone()
            logs = conn.execute("SELECT * FROM logs WHERE task_id = ? ORDER BY id", (args.id,)).fetchall()
        if not r:
            sys.exit(f"task #{args.id} not found")
        print(f"#{r['id']} {r['title']}\nstatus: {r['status']}  model: {r['model_used'] or '-'}")
        if r["approval_cmd"]:
            print(f"approval: {r['approval_summary']}\ncommand:  {r['approval_cmd']}")
        if r["result"]:
            print(f"\n{r['result']}")
        for l in logs:
            print(f"[{l['created_at']}] {l['level']}: {l['message']}")
    elif args.cmd in ("approve", "reject", "retry"):
        tid = args.id if args.id is not None else args.id_opt
        if tid is None:
            p.error(f"{args.cmd} needs a task id")
        ok = {"approve": approve, "reject": reject, "retry": retry}[args.cmd](tid)
        done = {"approve": "approved", "reject": "rejected", "retry": "re-queued"}[args.cmd]
        print(f"🦆 #{tid} {done}" if ok else f"#{tid}: not found or not in a state that allows {args.cmd}")
    elif args.cmd == "step":
        print("worked" if process_one() else "queue empty")
    elif args.cmd == "daemon" or args.cmd is None:
        daemon()


if __name__ == "__main__":
    main()
