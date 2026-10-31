#!/usr/bin/env python3
"""
Duffy Office — one screen for a small fleet of background agents.

Shows the Duffy queue and approvals, any HTTP health checks you list,
launchd services matching your prefixes (macOS) and the tail of
allow-listed log files. Actions (queue, approve, reject, retry, chat)
are forwarded to Duffy's own API; the office never writes anything itself.

Configuration lives under the "office" key of ~/.duffy/config.json.
Standard library only, Python 3.9+.
"""
from __future__ import annotations

import ipaddress
import json
import os
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOME = os.path.expanduser(os.environ.get("DUFFY_HOME", "~/.duffy"))
DEFAULTS = {
    "port": 8900,
    "bind_hosts": ["127.0.0.1"],
    "allowed_clients": [],
    "duffy_url": "http://127.0.0.1:8899",
    "health_checks": {},
    "service_prefixes": [],
    "logs": {},
    "health_cache_seconds": 60,
}


def load_config() -> dict:
    cfg = dict(DEFAULTS)
    path = os.environ.get("DUFFY_CONFIG", os.path.join(HOME, "config.json"))
    if os.path.exists(path):
        with open(path) as f:
            cfg.update(json.load(f).get("office", {}))
    cfg["logs"] = {k: os.path.expanduser(v) for k, v in cfg["logs"].items()}
    return cfg


CFG = load_config()
_health_cache: dict = {"at": 0.0, "data": []}


def tail(path: str, max_bytes: int = 8000) -> str:
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            f.seek(max(0, size - max_bytes))
            text = f.read().decode("utf-8", "replace")
        return text.split("\n", 1)[-1] if size > max_bytes else text
    except Exception as e:
        return f"(cannot read: {e})"


def health() -> list:
    # Cached so a dashboard left open does not flood the checked services' logs
    if time.time() - _health_cache["at"] < CFG["health_cache_seconds"]:
        return _health_cache["data"]
    out = []
    for name, url in CFG["health_checks"].items():
        t = time.time()
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                ok = 200 <= r.status < 300
        except Exception:
            ok = False
        out.append({"name": name, "ok": ok, "ms": int((time.time() - t) * 1000)})
    _health_cache.update(at=time.time(), data=out)
    return out


def services() -> list:
    if not CFG["service_prefixes"] or sys.platform != "darwin":
        return []
    listing = subprocess.run(["launchctl", "list"], capture_output=True, text=True, timeout=10).stdout
    rows = []
    for line in listing.splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) == 3 and any(parts[2].startswith(p) for p in CFG["service_prefixes"]):
            rows.append({"label": parts[2], "pid": None if parts[0] == "-" else int(parts[0]), "last_exit": parts[1]})
    return sorted(rows, key=lambda r: r["label"])


def duffy_status() -> dict:
    try:
        with urllib.request.urlopen(CFG["duffy_url"] + "/api/status", timeout=5) as r:
            return json.loads(r.read())
    except Exception as e:
        return {"error": str(e), "tasks": [], "chats": [], "agents": {}}


def snapshot() -> dict:
    d = duffy_status()
    tasks = d.get("tasks", [])
    return {
        "duffy_online": "error" not in d,
        "approvals": [t for t in tasks if t["status"] == "awaiting_approval"],
        "tasks": tasks[:20],
        "chats": d.get("chats", [])[-120:],
        "agents": d.get("agents", {}),
        "health": health(),
        "services": services(),
        "logs": list(CFG["logs"]),
    }


def forward(path: str, payload: dict) -> bool:
    req = urllib.request.Request(
        CFG["duffy_url"] + "/api" + path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("ok", False)
    except Exception:
        return False


def allowed(ip: str) -> bool:
    if not CFG["allowed_clients"] or ip in ("127.0.0.1", "::1"):
        return True
    addr = ipaddress.ip_address(ip)
    return any(addr in ipaddress.ip_network(a, strict=False) for a in CFG["allowed_clients"])


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

    def _json(self, obj, code: int = 200):
        self._send(code, "application/json; charset=utf-8", json.dumps(obj, ensure_ascii=False).encode())

    def do_GET(self):
        if not allowed(self.client_address[0]):
            return self._send(403, "text/plain", b"forbidden")
        url = urllib.parse.urlparse(self.path)
        if url.path == "/api/office":
            self._json(snapshot())
        elif url.path == "/api/log":
            name = urllib.parse.parse_qs(url.query).get("name", [""])[0]
            if name not in CFG["logs"]:
                return self._json({"error": "unknown log"}, 404)
            self._json({"name": name, "text": tail(CFG["logs"][name])})
        elif url.path in ("/", "/index.html"):
            self._send(200, "text/html; charset=utf-8", PAGE.encode())
        else:
            self._send(404, "text/plain", b"not found")

    def do_POST(self):
        if not allowed(self.client_address[0]):
            return self._send(403, "text/plain", b"forbidden")
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0") or 0)) or b"{}")
        path = urllib.parse.urlparse(self.path).path.replace("/api", "")
        if path not in ("/add", "/approve", "/reject", "/retry", "/chat"):
            return self._json({"ok": False}, 404)
        self._json({"ok": forward(path, body)})


PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Duffy Office</title>
<style>
:root{--bg:#0d0f12;--panel:#151920;--line:#252b35;--text:#e6e9ee;--mute:#8a93a3;--ok:#3fb27f;--warn:#e0a83b;--bad:#e2555a}
@media(prefers-color-scheme:light){:root{--bg:#f5f6f8;--panel:#fff;--line:#e2e5e9;--text:#15181c;--mute:#5d6571}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 -apple-system,system-ui,sans-serif}
header{display:flex;gap:14px;align-items:center;padding:14px 20px;border-bottom:1px solid var(--line)}h1{font-size:17px;margin:0}
.mute{color:var(--mute);font-size:12px}main{display:grid;grid-template-columns:minmax(0,1fr) 360px;gap:16px;padding:16px 20px}
@media(max-width:960px){main{grid-template-columns:1fr}}h2{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--mute);margin:16px 0 8px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:8px}
.card,.box{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}
.card{border-left:3px solid var(--mute)}.ok{border-left-color:var(--ok)}.bad{border-left-color:var(--bad)}
.gate{border:1px solid #5c4615;background:rgba(224,168,59,.08);border-radius:10px;padding:12px;margin-bottom:8px}
pre{white-space:pre-wrap;background:rgba(0,0,0,.25);border-radius:8px;padding:10px;font-size:12px;max-height:380px;overflow:auto}
button{border:0;border-radius:6px;padding:6px 10px;background:var(--line);color:var(--text);cursor:pointer}.go{background:var(--ok);color:#fff}.no{background:var(--bad);color:#fff}
input,select,textarea{width:100%;background:transparent;color:var(--text);border:1px solid var(--line);border-radius:6px;padding:7px;font:inherit}
.chat{height:280px;overflow:auto;display:flex;flex-direction:column;gap:6px;margin:8px 0}.msg{padding:6px 9px;border-radius:8px;white-space:pre-wrap;max-width:92%}
.user{align-self:flex-end;background:#1d3557;color:#fff}.agent{background:var(--line)}
</style></head><body><header><h1>Duffy Office</h1><span class="mute" id="sum"></span></header><main><section>
<h2>Approvals</h2><div id="approvals"></div><h2>Health</h2><div class="grid" id="health"></div>
<h2>Services</h2><div class="grid" id="services"></div><h2>Logs</h2><select id="logsel" onchange="loadLog()"></select><pre id="log"></pre></section>
<aside><div class="box"><h2>Queue a task</h2><textarea id="t" rows="3"></textarea><p><button class="go" onclick="add()">Queue</button></p></div>
<div class="box" style="margin-top:12px"><h2>Chat</h2><select id="agent" onchange="render()"></select><div class="chat" id="chat"></div>
<input id="m" placeholder="Message…" onkeydown="if(event.key==='Enter')send()"></div>
<div class="box" style="margin-top:12px"><h2>Recent tasks</h2><div id="tasks"></div></div></aside></main>
<script>
let S;const $=i=>document.getElementById(i),esc=s=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
async function post(p,b){await fetch('/api'+p,{method:'POST',body:JSON.stringify(b)});load()}
async function load(){S=await (await fetch('/api/office')).json();render()}
function render(){if(!S)return;$('sum').textContent=`Duffy ${S.duffy_online?'online':'OFFLINE'} · ${S.approvals.length} awaiting approval`;
$('approvals').innerHTML=S.approvals.map(t=>`<div class="gate"><b>#${t.id}</b> ${esc(t.title)}<div>${esc(t.approval_summary)}</div><pre>${esc(t.approval_cmd)}</pre>
<button class="go" onclick="confirm('Run it?')&&post('/approve',{id:${t.id}})">Approve</button> <button class="no" onclick="post('/reject',{id:${t.id}})">Reject</button></div>`).join('')||'<p class="mute">Nothing waiting.</p>';
$('health').innerHTML=S.health.map(h=>`<div class="card ${h.ok?'ok':'bad'}"><b>${esc(h.name)}</b><div class="mute">${h.ok?'up':'down'} · ${h.ms} ms</div></div>`).join('')||'<p class="mute">No checks configured.</p>';
$('services').innerHTML=S.services.map(s=>`<div class="card ${s.pid?'ok':(s.last_exit==='0'?'':'bad')}"><b>${esc(s.label)}</b><div class="mute">pid ${s.pid??'—'} · last exit ${esc(s.last_exit)}</div></div>`).join('')||'<p class="mute">No services configured.</p>';
if(!$('logsel').options.length){$('logsel').innerHTML=S.logs.map(l=>`<option>${esc(l)}</option>`).join('');if(S.logs.length)loadLog()}
if(!$('agent').options.length)$('agent').innerHTML=Object.entries(S.agents).map(([k,v])=>`<option value="${esc(k)}">${esc(v)}</option>`).join('');
$('chat').innerHTML=S.chats.filter(c=>c.agent_id===$('agent').value).map(c=>`<div class="msg ${c.sender==='user'?'user':'agent'}">${esc(c.message)}</div>`).join('');
$('tasks').innerHTML=S.tasks.map(t=>`<div class="mute">#${t.id} · ${esc(t.status)} · ${esc(t.title)}</div>`).join('')}
async function loadLog(){const r=await (await fetch('/api/log?name='+encodeURIComponent($('logsel').value))).json();$('log').textContent=r.text||r.error}
function add(){const v=$('t').value.trim();if(v){post('/add',{title:v});$('t').value=''}}
function send(){const v=$('m').value.trim();if(v){post('/chat',{agent_id:$('agent').value,message:v});$('m').value=''}}
load();setInterval(load,10000);
</script></body></html>"""


def main() -> None:
    pending = list(CFG["bind_hosts"])
    while True:
        for host in list(pending):
            try:
                srv = ThreadingHTTPServer((host, CFG["port"]), Handler)
            except OSError as e:
                sys.stderr.write(f"[office] cannot bind {host}:{CFG['port']}: {e}\n")
                continue
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            pending.remove(host)
            print(f"Duffy Office on http://{host}:{CFG['port']}", flush=True)
        time.sleep(60 if pending else 3600)


if __name__ == "__main__":
    main()
