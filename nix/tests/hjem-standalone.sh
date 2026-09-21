#!/usr/bin/env bash
set -euo pipefail

flake=${1:-path:./nix}
if [[ $flake == path:./* ]]; then
  flake="path:$PWD/${flake#path:./}"
fi
flake_dir=${flake#path:}
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

expected=20
if [[ $system == *-darwin ]]; then expected=23; fi
actual=$(find "$home" -type f | wc -l | tr -d ' ')
[[ $actual == "$expected" ]] || { echo "expected $expected managed files, got $actual" >&2; exit 1; }
[[ ! -e "$home/.ssh/id_ed25519" ]]
[[ ! -e "$home/.config/resilio-sync" ]]
grep -q '"type":"external-tool"\|"type": "external-tool"' "$home/.config/restish/restish.json"
! grep -Eiq 'credential|secret|password|cookie|["?]token["?][[:space:]]*:' "$home/.config/restish/restish.json"
[[ -x "$home/.local/bin/resilio-restish" ]]
[[ -x "$home/.local/libexec/resilio-restish-auth" ]]
"$home/.local/bin/code" --version
[[ $("$home/.local/bin/remoteit-ssh" --help 2>&1) == *"usage: remoteit-ssh"* ]]
[[ $("$home/.local/bin/remoteit-ssh" --help 2>&1) != *"opens an SSH connection"* ]]
! grep -Eq '(^|[[:space:]])eval([[:space:]]|$)' "$home/.local/bin/remoteit-ssh"
"$home/.local/bin/restish" --version
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
cmp -s "$home/.config/git/ignore" "$flake_dir/assets/shell/gitignore"

echo "Hjem standalone build, switch, idempotence, and unmanaged-conflict backup passed on $system"
