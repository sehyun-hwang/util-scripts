#!/usr/bin/env python3
# <bitbar.title>Resilio Sync local status</bitbar.title>
# <bitbar.version>1.0</bitbar.version>
# <bitbar.author>Local</bitbar.author>
# <bitbar.desc>Read-only local Resilio status with explicit lifecycle actions.</bitbar.desc>

from __future__ import annotations

import json
import pathlib
import shlex
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
CLIENT = pathlib.Path.home() / ".local/bin/resilio-restish"
PYTHON = pathlib.Path(sys.executable)


def menu_command(*arguments: str, terminal: bool = False) -> str:
    values = " ".join(shlex.quote(value) for value in (str(CLIENT), *arguments))
    return f"bash={shlex.quote('/bin/sh')} param1=-c param2={shlex.quote(values)} terminal={'true' if terminal else 'false'} refresh=true"


def output() -> None:
    try:
        result = subprocess.run(
            [str(CLIENT), "status"],
            capture_output=True,
            text=True,
            timeout=8,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        result = None

    try:
        folders = json.loads(result.stdout)["folders"] if result and result.returncode == 0 else None
        lines = ["Local folders", *[f"- {folder['path']}: {'paused' if folder['paused'] else 'active'}" for folder in folders]] if folders is not None else []
    except (ValueError, KeyError, TypeError):
        lines = []
    if lines:
        folder_lines = [line for line in lines[1:] if line.startswith("-")]
        paused = sum(line.endswith(": paused") for line in folder_lines)
        title = f"Resilio {len(folder_lines)}"
        if paused:
            title += f" ({paused} paused)"
        print(title)
        print("---")
        for line in lines[:21]:
            print(line.replace("|", "¦"))
    else:
        print("Resilio unavailable")
        print("---")
        print("WebUI status unavailable")

    print("---")
    print("Open Resilio Sync | bash=/usr/bin/open param1=-a param2='Resilio Sync' terminal=false")
    print("Refresh | refresh=true")


if __name__ == "__main__":
    output()
