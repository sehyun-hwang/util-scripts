from __future__ import annotations

import hashlib
import http.server
import json
import os
import pathlib
import shutil
import socketserver
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.parse

REPO = pathlib.Path(__file__).resolve().parents[2]
RESILIO = REPO / "resilio"
WRAPPER = RESILIO / "resilio-restish"
HELPER = RESILIO / "resilio-restish-auth.py"
SCHEMA = RESILIO / "openapi.yaml"
CONFIG_TEMPLATE = RESILIO / "restish.json"
RESTISH = os.environ.get("RESTISH_TEST_BIN") or shutil.which("restish")


class MockResilioHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    requests: list[dict[str, object]] = []
    token = "mock-token-sensitive"
    cookie = "mock-session-sensitive"
    token_failure = False
    preferences = {}
    fail_pause = False

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_POST(self) -> None:
        if self.path != "/gui/token.html" or self.token_failure:
            self.send_error(404)
            return
        body = f'<html><span id="token">{self.token}</span></html>'.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Set-Cookie", f"session={self.cookie}; Path=/; HttpOnly")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        self.__class__.requests.append(
            {"path": parsed.path, "query": query, "cookie": self.headers.get("Cookie")}
        )
        if (
            parsed.path != "/gui/"
            or query.get("token") != [self.token]
            or self.headers.get("Cookie") != f"session={self.cookie}"
        ):
            payload = {"status": 200, "value": {"error": "authentication failed"}}
        elif query.get("action") == ["getsyncfolders"]:
            payload = {
                "status": 200,
                "folders": [{"id": "folder-1", "path": "/mock/share"}],
                "schema_change": "preserved",
            }
        elif query.get("action") == ["folderpref"] and query.get("id") == ["folder-1"]:
            payload = {"status": 200, "value": self.preferences}
        elif query.get("action") == ["setfolderpref"]:
            for key, values in query.items():
                if key not in {"action", "token", "id"}:
                    try:
                        self.preferences[key] = json.loads(values[0])
                    except ValueError:
                        self.preferences[key] = values[0]
            payload = {"status": 200}
            if self.fail_pause and self.preferences["paused"]:
                payload["error"] = "pause acknowledgement lost"
        elif query.get("action") == ["getsysteminfo"]:
            payload = {"status": 200, "error": "mock application failure"}
        else:
            payload = {"status": 200, "value": {"error": "unexpected action"}}
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


@unittest.skipUnless(RESTISH, "set RESTISH_TEST_BIN to official Restish 2.3.0+ or install restish")
class RestishWrapperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        version = subprocess.run([str(RESTISH), "--version"], capture_output=True, text=True, check=True)
        cls.assertRegex(cls, version.stdout, r"restish version (?:[3-9]|2\.(?:[3-9]|[1-9][0-9]))")
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), MockResilioHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)

    def setUp(self) -> None:
        MockResilioHandler.requests.clear()
        MockResilioHandler.token_failure = False
        MockResilioHandler.fail_pause = False
        MockResilioHandler.preferences = dict.fromkeys(
            ['canencrypt', 'deletetotrash', 'iswritable', 'paused', 'readonlysecret',
             'relay', 'searchlan', 'secrettype', 'selectivesync', 'stopped',
             'transferpriority', 'usehosts', 'usetracker'], False)
        MockResilioHandler.preferences['new_server_field'] = {'nested': True}
        self.temporary = tempfile.TemporaryDirectory(dir=REPO)
        self.work = pathlib.Path(self.temporary.name)
        self.storage = self.work / "storage"
        self.storage.mkdir()
        (self.storage / "sync.pid").write_text(f"{os.getpid()}\n", encoding="ascii")
        self.config = self.storage / "sync.conf"
        self.config.write_text(
            json.dumps({"webui": {"listen": "127.0.0.1:0"}, "untouched": True}),
            encoding="utf-8",
        )
        self.restish_config = self.work / "restish.json"
        static_config = json.loads(CONFIG_TEMPLATE.read_text(encoding="utf-8"))
        api = static_config["apis"]["resilio"]
        api["spec_files"] = [str(SCHEMA)]
        api["profiles"]["default"]["auth"]["params"]["commandline"] = str(HELPER)
        self.restish_config.write_text(json.dumps(static_config), encoding="utf-8")
        self.restish_config.chmod(0o600)
        helper_hash = "sha256:" + hashlib.sha256(str(HELPER).encode()).hexdigest()
        self.approval_path = self.work / "external-tool-approvals.json"
        self.approval_path.write_text(json.dumps({"approved": [helper_hash]}) + "\n", encoding="utf-8")
        self.approval_path.chmod(0o600)
        fake_lsof = self.work / "lsof"
        fake_lsof.write_text("#!/bin/sh\nprintf 'p%s\\nn127.0.0.1:%s\\n' \"$PPID\" \"$MOCK_PORT\"\n", encoding="utf-8")
        fake_lsof.chmod(0o700)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def environment(self) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.work}{os.pathsep}{env['PATH']}",
                "MOCK_PORT": str(self.server.server_address[1]),
                "RESTISH_BIN": str(RESTISH),
                "RESILIO_RESTISH_CONFIG": str(self.restish_config),
                "RESILIO_RESTISH_AUTH_HELPER": str(HELPER),
                "RESILIO_RESTISH_RESPONSE_CHECKER": str(RESILIO / "resilio-restish-response.py"),
                "RESILIO_RESTISH_CONFIG_PATH": str(self.config),
                "RESILIO_RESTISH_STORAGE_PATH": str(self.storage),
                "RESILIO_RESTISH_TIMEOUT": "3",
            }
        )
        return env

    def arguments(self, *arguments: str) -> list[str]:
        return [str(WRAPPER), "resilio", "web-ui-action", *arguments]

    def run_wrapper(
        self, *arguments: str, approve: bool = True, cwd: pathlib.Path = REPO
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            self.arguments(*arguments),
            cwd=cwd,
            env=self.environment(),
            input="y\n" if approve else "n\n",
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )

    def test_wrapper_uses_xdg_config_by_default(self) -> None:
        fake_restish = self.work / "restish-print-config"
        fake_restish.write_text(
            '#!/bin/sh\nprintf \'{"config":"%s"}\\n\' "$RSH_CONFIG"\n',
            encoding="utf-8",
        )
        fake_restish.chmod(0o700)
        checker = self.work / "response-checker"
        checker.write_text("#!/bin/sh\n/bin/cat\n", encoding="utf-8")
        checker.chmod(0o700)
        xdg = self.work / "xdg"
        config = xdg / "restish/restish.json"
        config.parent.mkdir(parents=True)
        config.write_text("{}\n", encoding="utf-8")
        installed_bin = self.work / "bin"
        installed_bin.mkdir()
        installed_wrapper = installed_bin / "resilio-restish"
        shutil.copy2(WRAPPER, installed_wrapper)
        env = self.environment()
        env.update({
            "RESTISH_BIN": str(fake_restish),
            "XDG_CONFIG_HOME": str(xdg),
            "RESILIO_RESTISH_RESPONSE_CHECKER": str(checker),
        })
        env.pop("RESILIO_RESTISH_CONFIG")
        result = subprocess.run(
            [str(installed_wrapper), "get", "resilio/gui/"], env=env,
            capture_output=True, text=True, timeout=20, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"config": str(config)})

    def test_wrapper_resolves_raw_checkout_config_outside_repo_cwd(self) -> None:
        fake_restish = self.work / "restish-check-cwd"
        fake_restish.write_text(
            "#!/bin/sh\ntest -f resilio/openapi.yaml || exit 9\nprintf '{\"status\":200}\\n'\n",
            encoding="utf-8",
        )
        fake_restish.chmod(0o700)
        env = self.environment()
        env["RESTISH_BIN"] = str(fake_restish)
        env.pop("RESILIO_RESTISH_CONFIG")
        env.pop("RESILIO_RESTISH_AUTH_HELPER")
        result = subprocess.run(
            self.arguments("getsyncfolders"),
            cwd=self.work,
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"status": 200})

    def run_lifecycle(self, *args):
        return subprocess.run([str(WRAPPER.resolve()), *args], env=self.environment(),
                              capture_output=True, text=True, timeout=30)

    def test_lifecycle_restores_after_command_failure(self):
        before = MockResilioHandler.preferences.copy()
        result = self.run_lifecycle('run-paused', 'folder-1', '--', '/bin/sh', '-c', 'exit 7')
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertEqual(MockResilioHandler.preferences, before)

    def test_lifecycle_restores_after_uncertain_pause_failure(self):
        MockResilioHandler.fail_pause = True
        result = self.run_lifecycle('run-paused', 'folder-1', '--', '/usr/bin/true')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(MockResilioHandler.preferences['paused'])
        self.assertEqual(len([r for r in MockResilioHandler.requests if r['query']['action'] == ['setfolderpref']]), 2)

    def test_lifecycle_preserves_initially_paused_folder(self):
        MockResilioHandler.preferences['paused'] = True
        result = self.run_lifecycle('run-paused', '/mock/share', '--', '/usr/bin/true')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(MockResilioHandler.preferences['paused'])
        self.assertFalse(any(r['query']['action'] == ['setfolderpref'] for r in MockResilioHandler.requests))

    def test_lifecycle_restores_on_termination(self):
        process = subprocess.Popen([str(WRAPPER.resolve()), 'run-paused', 'folder-1',
                                    '--', '/bin/sleep', '30'], env=self.environment(),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 10
            while not MockResilioHandler.preferences['paused'] and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(MockResilioHandler.preferences['paused'])
            time.sleep(0.3)
            process.terminate()
            _, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 143, error)
            self.assertFalse(MockResilioHandler.preferences['paused'])
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_external_tool_hook_rewrites_random_port_query_and_cookie(self) -> None:
        result = self.run_wrapper("getsyncfolders")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["folders"][0]["id"], "folder-1")
        self.assertEqual(payload["schema_change"], "preserved")
        request = MockResilioHandler.requests[-1]
        self.assertEqual(request["path"], "/gui/")
        self.assertEqual(request["query"]["action"], ["getsyncfolders"])
        self.assertEqual(request["query"]["token"], [MockResilioHandler.token])
        self.assertEqual(request["cookie"], f"session={MockResilioHandler.cookie}")
        self.assertNotIn(MockResilioHandler.token, result.stderr)
        self.assertNotIn(MockResilioHandler.cookie, result.stderr)

    def test_approval_is_restish_managed_and_contains_no_credentials(self) -> None:
        self.approval_path.unlink()
        denied = self.run_wrapper("getsyncfolders", approve=False)
        self.assertNotEqual(denied.returncode, 0)
        self.assertIn("Approve external auth tool", denied.stderr)
        self.assertIn("external-tool auth command was not approved", denied.stderr)
        self.assertFalse(self.approval_path.exists())

        expected = "sha256:" + hashlib.sha256(str(HELPER).encode()).hexdigest()
        self.approval_path.write_text(json.dumps({"approved": [expected]}) + "\n", encoding="utf-8")
        self.approval_path.chmod(0o600)
        approved = self.run_wrapper("getsyncfolders")
        self.assertEqual(approved.returncode, 0, approved.stderr)
        approval = json.loads(self.approval_path.read_text(encoding="utf-8"))
        self.assertEqual(approval, {"approved": [expected]})
        self.assertEqual(self.approval_path.stat().st_mode & 0o777, 0o600)
        persisted = "\n".join(path.read_text(errors="ignore") for path in self.work.rglob("*") if path.is_file())
        self.assertNotIn(MockResilioHandler.token, persisted)
        self.assertNotIn(MockResilioHandler.cookie, persisted)

    def test_folderpref_uses_canonical_schema_generated_option(self) -> None:
        result = self.run_wrapper("folderpref", "--id", "folder-1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)["value"]["new_server_field"]["nested"])
        self.assertEqual(MockResilioHandler.requests[-1]["query"]["id"], ["folder-1"])

    def test_application_error_fails_without_leaking_response_or_auth(self) -> None:
        result = self.run_wrapper("getsysteminfo")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("mock application failure", result.stderr)
        self.assertNotIn(MockResilioHandler.token, result.stderr)
        self.assertNotIn(MockResilioHandler.cookie, result.stderr)

    def test_token_failure_is_safe_and_has_no_persistent_auth(self) -> None:
        MockResilioHandler.token_failure = True
        result = self.run_wrapper("getsyncfolders")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(MockResilioHandler.token, result.stderr)
        self.assertNotIn(MockResilioHandler.cookie, result.stderr)
        for path in self.work.rglob("*"):
            if path.is_file():
                contents = path.read_text(errors="ignore")
                self.assertNotIn(MockResilioHandler.token, contents)
                self.assertNotIn(MockResilioHandler.cookie, contents)

    def test_helper_rejects_wrong_method_path_and_action(self) -> None:
        env = self.environment()
        env.update(
            {
                "RESILIO_RESTISH_CONFIG_PATH": str(self.config),
                "RESILIO_RESTISH_STORAGE_PATH": str(self.storage),
            }
        )
        cases = [
            {"method": "POST", "uri": "http://127.0.0.1:8889/gui/?action=getsyncfolders", "headers": {}, "body": ""},
            {"method": "GET", "uri": "http://127.0.0.1:8889/other?action=getsyncfolders", "headers": {}, "body": ""},
            {"method": "GET", "uri": "http://127.0.0.1:8889/gui/?action=setfolderpref", "headers": {}, "body": ""},
        ]
        for request in cases:
            with self.subTest(request=request):
                result = subprocess.run(
                    [str(HELPER)], input=json.dumps(request), env=env,
                    capture_output=True, text=True, timeout=10, check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertNotIn(MockResilioHandler.token, result.stderr)
                self.assertNotIn(MockResilioHandler.cookie, result.stderr)


if __name__ == "__main__":
    unittest.main()
