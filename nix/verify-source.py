#!/usr/bin/env python3
"""Verify that the standalone Nix source is safe and internally canonical."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path

NIX_DIR = Path(__file__).resolve().parent
REPO = NIX_DIR.parent
BACKUP_GIT_WIP = NIX_DIR / "assets/scripts/backup-git-wip.sh"
BACKUP_GIT_WIP_SHA256 = "13aeccfbb8aa49eb6d177f0a0d1213446b156928ee2ec5466a5167585450234e"

REQUIRED = (
    "assets/backup.mk",
    "assets/scripts/backup-git-wip.sh",
    "assets/scripts/backup-workflow.sh",
    "byok/byok-subagent-policy.json",
    "byok/byok-subagents.instructions.md",
    "byok/test-policy.sh",
    "resilio/openapi.yaml",
    "resilio/resilio-restish",
    "resilio/tests/test_resilio_restish.py",
    "swiftbar/copilot-awake.10s.sh",
    "swiftbar/copilot-awake/main.py",
)
REMOVED_ROOT_PATHS = (
    "atuin.toml",
    "backup-git-wip.sh",
    "backup-workflow.sh",
    "backup.mk",
    "bash_profile.sh",
    "byok",
    "config.fish",
    "ecr.sh",
    "gitconfig",
    "gitignore",
    "lambda.sh",
    "resilio",
    "secret.fish",
    "starship.toml",
    "swiftbar",
    "tests",
)
FORBIDDEN_NAMES = {"id_ed25519", "sync.conf", ".secret.csv"}
FORBIDDEN_SUFFIXES = {".pem", ".key", ".p12", ".pfx"}


def problems() -> list[str]:
    result: list[str] = []
    for relative in REQUIRED:
        if not (NIX_DIR / relative).is_file():
            result.append(f"missing canonical source: nix/{relative}")

    for relative in REMOVED_ROOT_PATHS:
        path = REPO / relative
        if path.exists() or path.is_symlink():
            result.append(f"root compatibility path still exists: {relative}")

    for path in NIX_DIR.rglob("*"):
        relative = path.relative_to(REPO)
        if path.is_symlink():
            result.append(f"Nix source must not contain symlinks: {relative}")
        if path.is_file() and (path.name in FORBIDDEN_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES):
            result.append(f"forbidden secret-like file in Nix source: {relative}")

    if BACKUP_GIT_WIP.is_file():
        actual = hashlib.sha256(BACKUP_GIT_WIP.read_bytes()).hexdigest()
        if actual != BACKUP_GIT_WIP_SHA256:
            result.append(f"backup-git-wip.sh hash changed: {actual}")
    return result


def main() -> int:
    found = problems()
    if found:
        print("\n".join(found), file=sys.stderr)
        return 1
    print(f"verified canonical path: {NIX_DIR}")
    print(f"verified backup-git-wip.sh sha256: {BACKUP_GIT_WIP_SHA256}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
