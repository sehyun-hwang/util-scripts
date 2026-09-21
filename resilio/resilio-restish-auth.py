#!/usr/bin/env python3
"""Restish external-tool auth helper for the local Resilio Sync WebUI."""

from __future__ import annotations

import argparse
import html.parser
import http.cookiejar
import ipaddress
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any

DEFAULT_STORAGE = pathlib.Path.home() / "Library/Application Support/Resilio Sync"
DEFAULT_CONFIG = DEFAULT_STORAGE / "sync.conf"
MAX_TOKEN_RESPONSE_BYTES = 1024 * 1024


class HelperError(RuntimeError):
    """An error safe to print without a credential-bearing request URI."""


@dataclass(frozen=True)
class Endpoint:
    host: str
    port: int

    @property
    def origin(self) -> str:
        host = f"[{self.host}]" if ":" in self.host else self.host
        return f"http://{host}:{self.port}"


class TokenParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.inside_token = False
        self.token: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if dict(attrs).get("id") == "token":
            self.inside_token = True

    def handle_endtag(self, tag: str) -> None:
        self.inside_token = False

    def handle_data(self, data: str) -> None:
        if self.inside_token and data.strip() and self.token is None:
            self.token = data.strip()


def fail(message: str) -> None:
    raise HelperError(message)


def is_loopback(host: str) -> bool:
    normalized = host.strip("[]").lower()
    if normalized == "localhost":
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def parse_listen(value: Any) -> Endpoint | None:
    if isinstance(value, bool):
        fail("webui.listen must be a string or integer")
    if isinstance(value, int):
        host, port = "127.0.0.1", value
    elif isinstance(value, str):
        text = value.strip()
        if not text:
            fail("webui.listen is empty")
        if text.isdigit():
            host, port = "127.0.0.1", int(text)
        else:
            try:
                parsed = urllib.parse.urlsplit(f"//{text}")
                host, port = parsed.hostname, parsed.port
            except ValueError:
                fail("webui.listen has an invalid host or port")
            if host is None or port is None:
                fail("webui.listen must include a host and port")
    else:
        fail("webui.listen must be a string or integer")
    if port == 0:
        return None
    if not 1 <= port <= 65535:
        fail("webui.listen port is outside 1-65535")
    if not is_loopback(host):
        fail("webui.listen must use a loopback host")
    return Endpoint(host.strip("[]"), port)


def load_config(path: pathlib.Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8-sig") as handle:
            config = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise HelperError("could not read a valid Resilio config") from exc
    if not isinstance(config, dict):
        fail("Resilio config root must be an object")
    return config


def read_live_pid(storage: pathlib.Path) -> int:
    try:
        text = (storage / "sync.pid").read_text(encoding="ascii").strip()
        pid = int(text)
    except (OSError, UnicodeError, ValueError) as exc:
        raise HelperError("Resilio Sync is not running (invalid or missing storage sync.pid)") from exc
    if pid <= 1:
        fail("storage sync.pid is invalid")
    try:
        os.kill(pid, 0)
    except ProcessLookupError as exc:
        raise HelperError("Resilio Sync is not running (stale storage sync.pid)") from exc
    except PermissionError:
        pass
    return pid


def loopback_listeners(pid: int, timeout: float) -> list[Endpoint]:
    try:
        result = subprocess.run(
            ["lsof", "-nP", "-a", "-p", str(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"],
            check=False,
            capture_output=True,
            text=True,
            timeout=max(0.1, timeout),
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise HelperError("could not inspect Resilio loopback listeners") from exc
    if result.returncode not in (0, 1):
        fail("could not inspect Resilio loopback listeners")
    endpoints: set[Endpoint] = set()
    for line in result.stdout.splitlines():
        if not line.startswith("n"):
            continue
        address = line[1:].split("->", 1)[0]
        if address.startswith("[") and "]:" in address:
            host, port_text = address[1:].rsplit("]:", 1)
        elif ":" in address:
            host, port_text = address.rsplit(":", 1)
        else:
            continue
        try:
            port = int(port_text)
        except ValueError:
            continue
        if is_loopback(host) and 1 <= port <= 65535:
            endpoints.add(Endpoint(host.strip("[]"), port))
    return sorted(endpoints, key=lambda endpoint: (endpoint.port, endpoint.host))


def candidate_endpoints(configured: Endpoint | None, discovered: list[Endpoint]) -> list[Endpoint]:
    if configured is None:
        candidates = discovered
    else:
        candidates = [endpoint for endpoint in discovered if endpoint.port == configured.port]
    if not candidates:
        fail("no eligible loopback listener was found for the Resilio storage PID")
    return candidates


def parse_request() -> tuple[str, urllib.parse.SplitResult, dict[str, Any]]:
    try:
        request = json.load(sys.stdin)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise HelperError("invalid Restish external-tool request") from exc
    if not isinstance(request, dict):
        fail("invalid Restish external-tool request")
    method = request.get("method")
    uri = request.get("uri")
    headers = request.get("headers")
    body = request.get("body")
    if method != "GET" or not isinstance(uri, str) or not isinstance(headers, dict):
        fail("only Restish GET requests with a headers object are eligible")
    if body not in (None, ""):
        fail("request body must be omitted")
    try:
        parsed = urllib.parse.urlsplit(uri)
    except ValueError as exc:
        raise HelperError("request URI is invalid") from exc
    if parsed.scheme != "http" or not parsed.hostname or not is_loopback(parsed.hostname):
        fail("request URI must use loopback HTTP")
    if parsed.username is not None or parsed.password is not None or parsed.fragment:
        fail("request URI contains unsupported components")
    try:
        port = parsed.port
    except ValueError as exc:
        raise HelperError("request URI has an invalid port") from exc
    if port is None or not 1 <= port <= 65535 or parsed.path != "/gui/":
        fail("request URI is outside the eligible Resilio action endpoint")
    try:
        query = urllib.parse.parse_qs(parsed.query, keep_blank_values=True, strict_parsing=True)
    except ValueError as exc:
        raise HelperError("request query is invalid") from exc
    if any(len(values) != 1 for values in query.values()) or "token" in query:
        fail("request query contains duplicate parameters or an explicit token")
    if len(query.get("action", [])) != 1:
        fail("request must contain exactly one action")
    action = query["action"][0]
    allowed = {"getappinfo", "getsysteminfo", "licenseagreed", "getsyncfolders", "folderpref", "setfolderpref"}
    if action not in allowed:
        fail("request action is not allowed")
    if action != "setfolderpref" and set(query) - {"action", "id"}:
        fail("request query contains unsupported parameters")
    if action in {"folderpref", "setfolderpref"}:
        if len(query.get("id", [])) != 1 or not query["id"][0]:
            fail("folderpref requires one non-empty id")
    elif "id" in query:
        fail("id is only allowed for folderpref")
    return action, parsed, query


def acquire_auth(endpoints: list[Endpoint], timeout: float) -> tuple[Endpoint, str, str]:
    for endpoint in endpoints:
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        request = urllib.request.Request(endpoint.origin + "/gui/token.html", method="POST")
        try:
            with opener.open(request, timeout=timeout) as response:
                content_type = response.headers.get_content_type()
                body = response.read(MAX_TOKEN_RESPONSE_BYTES + 1)
        except (OSError, urllib.error.URLError, TimeoutError, ValueError):
            continue
        if content_type != "text/html" or len(body) > MAX_TOKEN_RESPONSE_BYTES:
            continue
        parser = TokenParser()
        try:
            parser.feed(body.decode("utf-8"))
        except (UnicodeError, html.parser.HTMLParseError):
            continue
        token = parser.token
        if (
            token is None
            or len(token) > 4096
            or any(ord(char) < 0x20 or char == "\x7f" for char in token)
        ):
            continue
        cookies = []
        for cookie in jar:
            if cookie.name and not any(char in cookie.name for char in "\r\n;="):
                value = cookie.value or ""
                if not any(char in value for char in "\r\n;"):
                    cookies.append(f"{cookie.name}={value}")
        if cookies:
            return endpoint, token, "; ".join(cookies)
    fail("no eligible Resilio listener returned a WebUI token and cookie")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    config_default = pathlib.Path(os.environ.get("RESILIO_RESTISH_CONFIG_PATH") or DEFAULT_CONFIG)
    storage_default = pathlib.Path(os.environ.get("RESILIO_RESTISH_STORAGE_PATH") or DEFAULT_STORAGE)
    try:
        timeout_default = float(os.environ.get("RESILIO_RESTISH_TIMEOUT") or "3")
    except ValueError:
        timeout_default = 3.0
    parser.add_argument("--config", type=pathlib.Path, default=config_default)
    parser.add_argument("--storage", type=pathlib.Path, default=storage_default)
    parser.add_argument("--timeout", type=float, default=timeout_default)
    args = parser.parse_args()
    if not 0 < args.timeout <= 60:
        parser.error("--timeout must be greater than zero and at most 60 seconds")

    _action, request_uri, query = parse_request()
    config = load_config(args.config)
    webui = config.get("webui", {})
    if not isinstance(webui, dict):
        fail("Resilio config webui value must be an object")
    configured = parse_listen(webui.get("listen", "127.0.0.1:8889"))
    pid = read_live_pid(args.storage)
    endpoints = candidate_endpoints(configured, loopback_listeners(pid, args.timeout))
    endpoint, token, cookie = acquire_auth(endpoints, args.timeout)

    clean_query: list[tuple[str, str]] = []
    for key, values in query.items():
        clean_query.extend((key, value) for value in values)
    clean_query.append(("token", token))
    rewritten = urllib.parse.urlunsplit(
        ("http", urllib.parse.urlsplit(endpoint.origin).netloc, request_uri.path, urllib.parse.urlencode(clean_query), "")
    )
    json.dump({"uri": rewritten, "headers": {"Cookie": [cookie]}}, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HelperError as exc:
        print(f"resilio-restish-auth: {exc}", file=sys.stderr)
        raise SystemExit(1)
