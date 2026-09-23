#!/usr/bin/env python3
"""Unified system status with child submenu items."""

import json
import os
import re
import subprocess
import time
from datetime import date
from pathlib import Path

CACHE_DIR = Path.home() / "Library/Caches/SwiftBar-Status"
AWS_BIN = os.environ.get("AWS_BIN", "aws")
RESILIO_CLIENT = os.environ.get("RESILIO_CLIENT", str(Path.home() / ".local/bin/resilio-restish"))


def cached(name, max_age):
    def decorator(fn):
        def wrapper():
            path = CACHE_DIR / f"{name}.json"
            try:
                d = json.loads(path.read_text())
                if time.time() - d["t"] < max_age:
                    return d["v"]
            except (OSError, ValueError, KeyError):
                pass
            v = fn()
            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"t": time.time(), "v": v}))
            return v
        return wrapper
    return decorator


def run(cmd, timeout=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except Exception:
        return None


@cached("aws", 3600)
def aws_section():
    today = date.today()
    start = today.replace(day=1).isoformat()
    end = (today.replace(month=today.month % 12 + 1, day=1) if today.month < 12
           else today.replace(year=today.year + 1, month=1, day=1)).isoformat()
    r = run([AWS_BIN, "ce", "get-cost-and-usage", "--output", "json",
             "--time-period", f"Start={start},End={end}",
             "--granularity", "MONTHLY", "--metrics", "BlendedCost"], timeout=15)
    if not r or r.returncode:
        return None
    try:
        cost = json.loads(r.stdout)["ResultsByTime"][0]["Total"]["BlendedCost"]
        return {"amount": float(cost["Amount"]), "unit": cost["Unit"]}
    except (json.JSONDecodeError, KeyError, IndexError):
        return None


def tm_section():
    status = run(["/usr/bin/tmutil", "status"], timeout=5)
    dest = run(["/usr/bin/tmutil", "destinationinfo"], timeout=5)
    if not dest or "Mount Point" not in dest.stdout:
        return None
    running = status and ("Running = 1" in status.stdout or "Running = true" in status.stdout)
    latest = ""
    r = run(["/usr/bin/tmutil", "latestbackup"], timeout=5)
    if r and r.returncode == 0 and r.stdout.strip():
        latest = r.stdout.strip().split("/")[-1]
    if not latest:
        r = run(["/usr/bin/defaults", "read", "/Library/Preferences/com.apple.TimeMachine"], timeout=5)
        if r and r.stdout:
            dates = re.findall(r'"(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})"', r.stdout)
            if dates:
                latest = sorted(dates)[-1]
    percent = ""
    if running and status:
        m = re.search(r'Percent = "?([0-9.]+)', status.stdout)
        if m:
            percent = f"{float(m.group(1)) * 100:.0f}%"
    return {"running": running, "latest": latest, "percent": percent}


@cached("resilio", 600)
def resilio_section():
    r = run([RESILIO_CLIENT, "status"], timeout=8)
    if not r or r.returncode:
        return None
    try:
        folders = json.loads(r.stdout).get("folders", [])
        return [{"path": f["path"], "paused": f.get("paused", False)} for f in folders]
    except (json.JSONDecodeError, KeyError):
        return None


def main():
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    aws = aws_section()
    tm = tm_section()
    resilio = resilio_section()

    if aws:
        print(f"${aws['amount']:.0f}")
    else:
        print("⚙")
    print("---")

    label = f"AWS ${aws['amount']:.2f} {aws['unit']}" if aws else "AWS unavailable | color=red"
    print(f"{label} | sfimage=dollarsign.circle")
    if aws:
        print(f"--Month to date: ${aws['amount']:.2f}")

    if tm is not None:
        if tm["running"]:
            pct = f" {tm['percent']}" if tm["percent"] else ""
            print(f"Time Machine{pct} | sfimage=externaldrive.badge.timemachine color=#e5a50a")
        elif tm["latest"]:
            print("Time Machine | sfimage=externaldrive.badge.checkmark color=#2da44e")
        else:
            print("Time Machine | sfimage=externaldrive.badge.exclamationmark color=#cf222e")
        if tm["latest"]:
            print(f"--Last: {tm['latest']}")
        else:
            print("--No backups found | color=#cf222e")
        if tm["running"]:
            print("--Stop Backup | bash=/usr/bin/tmutil param1=stopbackup terminal=false refresh=true")
        else:
            print("--Backup Now | bash=/usr/bin/tmutil param1=startbackup terminal=false refresh=true")
        print("--Settings | bash=/usr/bin/open param1=x-apple.systempreferences:com.apple.Time-Machine-Settings.extension terminal=false")

    if resilio is not None:
        paused = sum(1 for f in resilio if f["paused"])
        rlabel = f"Resilio {len(resilio)}"
        if paused:
            rlabel += f" ({paused} paused)"
        print(f"{rlabel} | sfimage=arrow.triangle.2.circlepath")
        for f in resilio[:20]:
            s = "paused" if f["paused"] else "active"
            print(f"--{f['path'].replace('|', chr(0xa6))}: {s}")
        print("--Open Resilio Sync | bash=/usr/bin/open param1=-a param2='Resilio Sync' terminal=false")
    else:
        print("Resilio unavailable | sfimage=arrow.triangle.2.circlepath color=red")

    print("---")
    print("Refresh | refresh=true")


if __name__ == "__main__":
    main()
