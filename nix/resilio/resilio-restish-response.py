#!/usr/bin/env python3
"""Reject Resilio application errors returned inside successful HTTP responses."""

from __future__ import annotations

import json
import sys
from typing import Any


def safe_error(value: Any) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    return text[:300] or "unknown application error"


def main() -> int:
    raw = sys.stdin.read()
    if not raw:
        return 0
    try:
        payload = json.loads(raw)
    except (json.JSONDecodeError, UnicodeError):
        print("resilio-restish: Restish returned a non-JSON API response", file=sys.stderr)
        return 1
    if not isinstance(payload, dict):
        print("resilio-restish: Restish returned an unexpected API response", file=sys.stderr)
        return 1

    error = payload.get("error")
    value = payload.get("value")
    if error not in (None, "", False):
        print(f"resilio-restish: Resilio application error: {safe_error(error)}", file=sys.stderr)
        return 1
    if isinstance(value, dict) and value.get("error") not in (None, "", False):
        print(
            f"resilio-restish: Resilio application error: {safe_error(value['error'])}",
            file=sys.stderr,
        )
        return 1
    status = payload.get("status")
    if status not in (None, 200, "200"):
        print(f"resilio-restish: Resilio application status {status!r}", file=sys.stderr)
        return 1

    sys.stdout.write(raw)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
