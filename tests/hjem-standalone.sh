#!/usr/bin/env bash
set -euo pipefail

flake=${1:-git+file:$PWD}
case $flake in
  path:./*) flake="path:$PWD/${flake#path:./}" ;;
  git+file:./*) flake="git+file:$PWD/${flake#git+file:./}" ;;
esac
flake_dir=$PWD
if [[ $flake == path:* ]]; then
  flake_dir=${flake#path:}
elif [[ $flake == git+file:* ]]; then
  flake_dir=${flake#git+file:}
fi
system=$(nix eval --raw --impure --expr builtins.currentSystem)
case $system in
  *-darwin|*-linux) ;;
  *) echo "unsupported test system: $system" >&2; exit 1 ;;
esac

work=$PWD/.hjem-test-work
home=$work/home
state=$work/state
conf=$work/hjem.nix
rm -rf "$work"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
mkdir -p "$home" "$state"

cat > "$conf" <<EOF_CONFIG
(builtins.getFlake "${flake}").lib.mkHjemConfiguration "${system}" {
  homeDirectory = "${home}";
}
EOF_CONFIG

# Standalone evaluation alone does not realize referenced file derivations.
nix build --no-link "${flake}#hjem-manifest"
hjem=$(nix build --no-link --print-out-paths "${flake}#hjem")/bin/hjem
"$hjem" standalone build --config "$conf" --state-dir "$state"
"$hjem" standalone switch --config "$conf" --state-dir "$state"

expected=21
if [[ $system == *-darwin ]]; then expected=26; fi
actual=$(find "$home" -type f | wc -l | tr -d ' ')
[[ $actual == "$expected" ]] || { echo "expected $expected managed files, got $actual" >&2; exit 1; }
[[ ! -e "$home/.ssh/id_ed25519" ]]
[[ ! -e "$home/.config/resilio-sync" ]]
grep -q '"type":"external-tool"\|"type": "external-tool"' "$home/.config/restish/restish.json"
! grep -Eiq 'credential|secret|password|cookie|["?]token["?][[:space:]]*:' "$home/.config/restish/restish.json"
[[ -x "$home/.local/bin/resilio-restish" ]]
[[ $(stat -f '%Lp' "$home/.config/restish/restish.json" 2>/dev/null || stat -c '%a' "$home/.config/restish/restish.json") == 600 ]]
[[ -x "$home/.local/libexec/resilio-restish-auth" ]]
! grep -ER '@[A-Za-z_][A-Za-z0-9_]*@' "$home/.local/bin" "$home/.local/libexec" "$home/.config/restish" "$home/SwiftBar" 2>/dev/null
if [[ $system == *-darwin ]]; then
  [[ -x "$home/SwiftBar/awsmonthcost.1h.sh" ]]
  [[ -x "$home/SwiftBar/timemachine.1m.sh" ]]
fi
"$home/.local/bin/code" --version
[[ $("$home/.local/bin/remoteit-ssh" --help 2>&1) == *"usage: remoteit-ssh"* ]]
[[ $("$home/.local/bin/remoteit-ssh" --help 2>&1) != *"opens an SSH connection"* ]]
! grep -Eq '(^|[[:space:]])eval([[:space:]]|$)' "$home/.local/bin/remoteit-ssh"
[[ $("$home/.local/bin/restish" --version) == "restish version 2.3.0" ]]
"$home/.local/bin/restish" --help >/dev/null
[[ $("$home/.local/bin/thv-patched" version 2>&1) == *"ToolHive v0.46.0-patched"* ]]
"$home/.local/bin/thv-patched" --help >/dev/null
[[ $(TOOLHIVE_SKIP_DESKTOP_CHECK=0 "$home/.local/bin/thv-patched" version 2>&1) == *"CLI conflict detected"* ]]
"$home/.local/bin/resilio-restish" --help
[[ ! -e "$home/.local/bin/code-tunnel" ]]
[[ ! -e "$home/.local/bin/resilio-client" ]]
python3 - "$home/.config/starship.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as stream:
    config = tomllib.load(stream)
assert config['kubernetes']['disabled'] is False
assert 'format' not in config.get('python', {})
assert 'nodejs' in config
PY

first_hash=$(find "$home" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)
"$hjem" standalone switch --config "$conf" --state-dir "$state"
second_hash=$(find "$home" -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256)
[[ $first_hash == "$second_hash" ]]

echo unmanaged > "$home/.config/git/ignore"
"$hjem" standalone switch --config "$conf" --state-dir "$state"
grep -qx unmanaged "$home/.config/git/.backup-ignore"
cmp -s "$home/.config/git/ignore" "$flake_dir/shell/gitignore"

echo "Hjem standalone build, switch, idempotence, and unmanaged-conflict backup passed on $system"
