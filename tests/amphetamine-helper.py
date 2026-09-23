#!/usr/bin/env python3
"""Native helper event/liveness regression tests; pass path to built executable."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

BINARY = sys.argv.pop(1) if len(sys.argv) > 1 else "amphetamine-helper/.helper-check"


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=".")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.session = self.root / "active-session"
        self.session.mkdir()
        (self.session / "inuse.test.lock").write_text(str(os.getpid()))
        self.events = self.session / "events.jsonl"

    def append(self, *types):
        with self.events.open("a") as out:
            for kind, data in types:
                out.write(json.dumps({"type": kind, "data": data}) + "\n")

    def inspect(self):
        return json.loads(subprocess.check_output([BINARY, "--inspect", str(self.root)]))

    def test_final_turn_not_intermediate_message(self):
        self.append(("user.message", {}), ("assistant.message", {"toolRequests": []}))
        self.assertEqual(self.inspect()["working"], ["active-session"])
        self.append(("assistant.turn_end", {}))
        self.assertEqual(self.inspect()["working"], [])

    def test_waits_for_explicit_user_choice(self):
        self.append(("user.message", {}), ("permission.requested", {"requestId": "permission"}))
        self.assertEqual(self.inspect()["waiting"], ["active-session"])
        self.append(("assistant.message", {"toolRequests": []}))
        self.assertEqual(self.inspect()["waiting"], ["active-session"])
        self.append(("permission.completed", {"requestId": "permission"}))
        self.assertEqual(self.inspect()["working"], ["active-session"])
        self.append(("tool.execution_start", {"toolCallId": "choice", "toolName": "functions.ask_user"}))
        self.assertEqual(self.inspect()["waiting"], ["active-session"])
        self.append(("assistant.turn_end", {}))
        self.assertEqual(self.inspect()["waiting"], ["active-session"])
        self.append(("tool.execution_complete", {"toolCallId": "choice"}))
        self.assertEqual(self.inspect()["waiting"], [])
        self.assertEqual(self.inspect()["working"], [])

    def test_wait_survives_stale_event_file(self):
        self.append(("user.message", {}), ("permission.requested", {"requestId": "long-wait"}))
        os.utime(self.events, (time.time() - 3700, time.time() - 3700))
        self.assertEqual(self.inspect()["waiting"], ["active-session"])

    def test_dead_or_stale_session_is_ignored(self):
        self.append(("user.message", {}))
        self.assertEqual(self.inspect()["working"], ["active-session"])
        os.utime(self.events, (time.time() - 3700, time.time() - 3700))
        self.assertEqual(self.inspect()["working"], [])
        (self.session / "inuse.test.lock").write_text("99999999")
        self.assertEqual(self.inspect()["working"], [])

    def test_startup_grace_and_idle_exit(self):
        def exits(started, last_active):
            return int(subprocess.check_output([BINARY, "--lifecycle", str(started), str(last_active)]))

        self.assertEqual(exits(85, 85), 0)
        self.assertEqual(exits(80, 95), 0)
        self.assertEqual(exits(80, 87), 1)

    def test_incomplete_line_ignored(self):
        self.append(("user.message", {}))
        with self.events.open("a") as out:
            out.write('{"type":"assistant.turn_end"')
        self.assertEqual(self.inspect()["working"], ["active-session"])


if __name__ == "__main__":
    unittest.main()
