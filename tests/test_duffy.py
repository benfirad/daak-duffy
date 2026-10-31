from __future__ import annotations

import importlib
import json
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)


def fresh_duffy(extra: dict | None = None):
    """Import duffy against a throw-away home directory and a fake agent."""
    home = tempfile.mkdtemp()
    agent = os.path.join(home, "fake_agent.py")
    with open(agent, "w") as f:
        f.write(
            "import sys\n"
            "model, prompt = sys.argv[1], sys.argv[2]\n"
            "if model == 'busy': print('RESOURCE_EXHAUSTED'); sys.exit(0)\n"
            "if 'NEEDS_GATE' in prompt: print('Drafted it.\\n[APPROVAL_REQUIRED: send the email | CMD: echo sent]')\n"
            "else: print('report from ' + model)\n"
        )
    cfg = {"agent_command": [sys.executable, agent, "{model}", "{prompt}"], "models": ["busy", "good"]}
    cfg.update(extra or {})
    with open(os.path.join(home, "config.json"), "w") as f:
        json.dump(cfg, f)
    os.environ["DUFFY_HOME"] = home
    os.environ.pop("DUFFY_CONFIG", None)
    import duffy
    return importlib.reload(duffy)


class DuffyTests(unittest.TestCase):
    def test_model_fallback_and_done(self):
        d = fresh_duffy()
        tid = d.add_task("summarise the logs")
        self.assertTrue(d.process_one())
        with d.db() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (tid,)).fetchone()
        self.assertEqual(row["status"], "done")
        self.assertEqual(row["model_used"], "good")

    def test_approval_gate_blocks_until_approved(self):
        d = fresh_duffy()
        tid = d.add_task("NEEDS_GATE step")
        d.process_one()
        with d.db() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (tid,)).fetchone()
        self.assertEqual(row["status"], "awaiting_approval")
        self.assertEqual(row["approval_cmd"], "echo sent")
        self.assertNotIn("APPROVAL_REQUIRED", row["result"])
        self.assertFalse(d.process_one())  # nothing runs without a human
        self.assertTrue(d.approve(tid))
        d.process_one()
        with d.db() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (tid,)).fetchone()
        self.assertEqual(row["status"], "done")
        self.assertIn("sent", row["result"])

    def test_cannot_approve_task_that_did_not_ask(self):
        d = fresh_duffy()
        tid = d.add_task("plain task")
        self.assertFalse(d.approve(tid))

    def test_failed_command_reports_exit_code(self):
        d = fresh_duffy()
        tid = d.add_task("x")
        with d.db() as conn:
            conn.execute(
                "UPDATE tasks SET status='approved', approval_cmd='exit 3' WHERE id = ?", (tid,)
            )
        d.process_one()
        with d.db() as conn:
            row = conn.execute("SELECT * FROM tasks WHERE id = ?", (tid,)).fetchone()
        self.assertEqual(row["status"], "failed")
        self.assertIn("exit 3", row["result"])

    def test_turkish_marker_is_understood(self):
        d = fresh_duffy()
        m = d.APPROVAL_RE.search("rapor\n[ONAY_GEREKLİ: mail at | KOMUT: echo ok]")
        self.assertEqual(m.group(2), "echo ok")

    def test_client_allowlist(self):
        d = fresh_duffy({"allowed_clients": ["100.64.0.0/10"]})
        self.assertTrue(d.client_allowed("127.0.0.1"))
        self.assertTrue(d.client_allowed("100.101.1.2"))
        self.assertFalse(d.client_allowed("192.168.1.20"))

    def test_default_binds_loopback_only(self):
        d = fresh_duffy()
        self.assertEqual(d.CFG["bind_hosts"], ["127.0.0.1"])


if __name__ == "__main__":
    unittest.main()
