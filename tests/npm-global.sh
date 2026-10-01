#!/usr/bin/env bash
set -euo pipefail

flake=${1:-git+file:$PWD}
package=$(nix build --no-link --print-out-paths "$flake#npm-global")
system=$(nix eval --raw --impure --expr builtins.currentSystem)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

nix eval --json "$flake#hjemConfigurations.hwangsehyun.$system.manifest" > "$work/manifest.json"
python3 - "$package" "$work" <<'PY'
import json
import pathlib
import shutil
import sys

package, work = map(pathlib.Path, sys.argv[1:])
manifest = json.loads((work / 'manifest.json').read_text())
commands = ['artillery', 'diffchecker', 'nx', 'nx-cloud', 'projen', 'serve',
            'showdown', 'v8r', 'vite', 'wscat']
for name in commands:
    source = package / 'bin' / name
    assert source.is_file(), name
    assert any(str(source) in json.dumps(entry) and f'.local/bin/{name}' in json.dumps(entry)
               for entry in manifest['files']), name
    shutil.copy2(source, work / name)
PY

# Copied Hjem wrappers must work without a host Node.js on PATH.
for command in diffchecker projen serve showdown v8r vite wscat; do
  PATH=/usr/bin:/bin "$work/$command" --version
done
PATH=/usr/bin:/bin NX_DAEMON=false "$work/nx" --version
PATH=/usr/bin:/bin ARTILLERY_DISABLE_TELEMETRY=true "$work/artillery" --version
