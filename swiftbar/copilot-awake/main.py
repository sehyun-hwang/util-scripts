#!/usr/bin/env python3
"""SwiftBar controller for Amphetamine based on local Copilot session events."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path.home() / ".copilot/session-state"
CACHE = Path.home() / "Library/Caches/copilot-awake"
STATE_PATH = CACHE / "state.json"
OWNER_PATH = CACHE / "owned-lease.json"
STALE_SECONDS = 3600
LEASE_SECONDS = 60


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False


def session_alive(session: Path) -> bool:
    for lock in session.glob("inuse.*.lock"):
        try:
            if process_alive(int(lock.read_text().strip())):
                return True
        except (OSError, ValueError):
            pass
    return False


def apply_event(state: dict, event: dict) -> None:
    kind = event.get("type")
    data = event.get("data") or {}
    waiting = state.setdefault("waiting", [])
    if kind in ("user.message", "assistant.turn_start"):
        state["busy"] = True
    elif kind == "assistant.message":
        state["busy"] = bool(data.get("toolRequests"))
    elif kind in ("session.idle", "session.shutdown", "abort", "session.error"):
        state["busy"] = False
        waiting.clear()
    elif kind == "permission.requested":
        key = "permission:" + str(data.get("requestId"))
        if key not in waiting:
            waiting.append(key)
    elif kind == "permission.completed":
        key = "permission:" + str(data.get("requestId"))
        state["waiting"] = [item for item in waiting if item != key]
    elif kind in ("tool.execution_start", "external_tool.requested"):
        name = str(data.get("toolName", "")).split(".")[-1]
        if name in ("ask_user", "ask_user_question", "askUserQuestion"):
            key = "tool:" + str(data.get("toolCallId", data.get("requestId")))
            if key not in waiting:
                waiting.append(key)
    elif kind in ("tool.execution_complete", "external_tool.completed"):
        key = "tool:" + str(data.get("toolCallId", data.get("requestId")))
        state["waiting"] = [item for item in waiting if item != key]


def read_session(path: Path, previous: dict | None) -> tuple[dict, float]:
    stat = path.stat()
    state = previous
    if not state or state.get("inode") != stat.st_ino or state.get("offset", 0) > stat.st_size:
        state = {"inode": stat.st_ino, "offset": 0, "busy": False, "waiting": []}
    with path.open("rb") as stream:
        stream.seek(state["offset"])
        while True:
            line = stream.readline()
            if not line or not line.endswith(b"\n"):
                break
            try:
                apply_event(state, json.loads(line))
            except (json.JSONDecodeError, TypeError):
                pass
            state["offset"] = stream.tell()
    return state, stat.st_mtime


def detect(previous: dict) -> tuple[dict, list[str], int]:
    states: dict = {}
    active: list[str] = []
    stale = 0
    if not ROOT.is_dir():
        raise RuntimeError("Copilot session directory not found")
    for session in ROOT.iterdir():
        if not session.is_dir() or not session_alive(session):
            continue
        events = session / "events.jsonl"
        if not events.is_file():
            continue
        state, modified = read_session(events, previous.get(session.name))
        states[session.name] = state
        if state["busy"] and not state["waiting"]:
            if time.time() - modified <= STALE_SECONDS:
                active.append(session.name)
            else:
                stale += 1
    return states, sorted(active), stale


def run_applescript(source: str) -> str:
    result = subprocess.run(
        ["/usr/bin/osascript", "-e", source],
        text=True,
        capture_output=True,
        timeout=20,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Amphetamine AppleScript failed")
    return result.stdout.strip()


def amphetamine_active() -> bool:
    return run_applescript('tell application "Amphetamine" to get session is active').lower() == "true"


def read_owner() -> dict | None:
    try:
        owner = json.loads(OWNER_PATH.read_text())
        if isinstance(owner, dict) and isinstance(owner.get("expiresAt"), (int, float)):
            return owner
    except (OSError, ValueError):
        pass
    return None


def write_owner(expires_at: float) -> None:
    temporary = OWNER_PATH.with_suffix(".tmp")
    temporary.write_text(json.dumps({"expiresAt": expires_at}) + "\n")
    temporary.replace(OWNER_PATH)


def clear_owner() -> None:
    OWNER_PATH.unlink(missing_ok=True)


def control_amphetamine(active_sessions: list[str]) -> str:
    now = time.time()
    owner = read_owner()
    active = amphetamine_active()

    if active_sessions:
        if owner and owner["expiresAt"] > now:
            if active:
                return "Automation-owned one-minute lease is active"
            clear_owner()
            owner = None
        elif owner:
            clear_owner()
            owner = None
        if active:
            return "Existing user Amphetamine session left unchanged"
        run_applescript(
            'tell application "Amphetamine" to start new session with options '
            "{duration:1, interval:minutes, displaySleepAllowed:true}"
        )
        write_owner(now + LEASE_SECONDS)
        return "Started automation-owned one-minute lease; display may sleep"

    if owner:
        if owner["expiresAt"] <= now or not active:
            clear_owner()
            return "Automation-owned lease released"
        return "Idle; automation-owned lease will expire naturally"
    return "Idle; no automation-owned Amphetamine lease"


def clean(text: object) -> str:
    return " ".join(str(text).replace("|", "/").split())[:250]


def main() -> None:
    CACHE.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (CACHE / "run.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("☕ …\n---\nActivity check already running")
            return
        try:
            try:
                previous = json.loads(STATE_PATH.read_text())
            except (OSError, ValueError):
                previous = {}
            states, active, stale = detect(previous)
            temporary = STATE_PATH.with_suffix(".tmp")
            temporary.write_text(json.dumps(states))
            temporary.replace(STATE_PATH)
            status = control_amphetamine(active)
            print(f"☕ {len(active)}" if active else "☕ idle")
            print("---")
            print(f"Working Copilot sessions: {len(active)}")
            print(clean(status))
            print("Checks every 10 seconds; automation leases last one minute")
            print("Existing user Amphetamine sessions are never ended or replaced")
            if stale:
                print(f"Ignored {stale} session(s) with no events for one hour")
            for session in active:
                print(f"Session {session[:8]}")
        except Exception as error:
            print("☕ !\n---")
            print(clean(error))
            print("No Amphetamine session was ended")
        print("Refresh now | refresh=true")


if __name__ == "__main__":
    main()
