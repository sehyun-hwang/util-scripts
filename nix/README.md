# Secret-free standalone Nix and Hjem

This directory is the only Nix flake source. Always use `path:./nix`; never use
the repository root or a Git flake reference. Components have one canonical tree
under `nix/byok`, `nix/resilio`, and `nix/swiftbar`; shared backup and shell files
remain under `nix/assets`. Root compatibility paths and duplicate mirrors are
removed. Verify the safe-root boundary, canonical layout, and preserved backup
script hash with:

```bash
python3 nix/verify-source.py
```

## Separate command profile

Commands remain independent from home-file activation. Keep `#hjem-config` in
the separate profile as a garbage-collection root for all copied files' runtime
closures (Nix may warn that this regular-file output has no binaries to expose):

```bash
PROFILE="$HOME/.local/state/nix/profiles/util-scripts"
mkdir -p "$(dirname "$PROFILE")"
nix profile install --profile "$PROFILE" "path:$PWD/nix#default" "path:$PWD/nix#hjem-config"
# Do not prepend the profile; Hjem exposes selected commands in ~/.local/bin.
```

Individual package outputs include `#backup-workflow`, `#backup-git-wip`,
`#remoteit-ssh`, `#resilio`, `#restish`, `#awscli2`, and `#vscode-cli`. The stale
ECR, Lambda, and secret helper sources have been removed.
`#resilio` packages a Bash lifecycle adapter, OpenAPI schema, checked Restish
launcher, external-tool auth helper, and response checker, using Restish 2.3.0.
The Python API client is removed; the auth/response helpers remain. Tokens and
cookies are acquired per request in memory. Use `resilio-restish status` or
`resilio-restish run-paused FOLDER -- COMMAND` for pause/run/restore. Helper
approval remains mandatory; no credentials are persisted. Hjem installs `code`,
`remoteit-ssh`, `restish`, `resilio-restish`, and both backup scripts in
`~/.local/bin` without adding older runtime tools to the user's PATH.

## Remote.it SSH

`#remoteit-ssh` packages upstream `conor-f/remoteit-ssh` version 0.3.1 at commit
`5a9e82b018cdc1957c71f3b88e2820bf718d597a`. It preserves the upstream Python
client and exact `requests-http-signature` 0.1.0 runtime dependency. Only the
upstream setuptools install hook is disabled because it appends an executing
shell wrapper to `~/.zshrc`; Nix exposes the entry point itself as
`remoteit-ssh`. Consequently the command keeps upstream behavior: it selects
the first matching device's first service and prints an SSH command without
executing it. Credentials are read at runtime from
`~/.config/remoteit_ssh/config.ini` or `--file`, never copied into the store.
Use `remoteit-ssh --help` for an offline installation check; do not pass a device
name during validation.

## VS Code CLI from packaged product metadata

`#vscode-cli` builds the standalone Rust CLI from the exact `pkgs.vscode.rev`
source commit and reads Microsoft's packaged `product.json` via
`VSCODE_CLI_PRODUCT_JSON`. No local desktop installation or copied product file
is required. Unfree permission is restricted to the `vscode` package. The default
command profile includes the CLI; Hjem also installs it as `~/.local/bin/code`.
Use `~/.local/bin/code tunnel`; there is no separate tunnel wrapper. Installing
over a newer local CLI is a downgrade to the pinned version below. Hjem is the
sole installer for this destination; the legacy Makefile installer was removed.

```bash
nix build path:./nix#vscode-cli
./result/bin/code --version
./result/bin/code tunnel --help
```

The dedicated `vscode-nixpkgs` input supplies **1.137.0**, commit
`645f29cc3176500b4b5762ba887cf2a7f0ffdf2c`. This updates the CLI without changing
the other command packages or Hjem's inputs. Source and Cargo dependency hashes
are pinned separately. To update, move `vscode-nixpkgs`, verify its VS Code
version/revision, reset both hashes to avoid reusing older fixed-output sources,
update the source and
Cargo hashes from Nix mismatch output, and rebuild `#vscode-cli`. Pre-build checks reject
mismatched product/source versions and commits. This is a locally compiled CLI,
not Microsoft's signed binary distribution; upstream service/license terms
still apply.

Validated an actual Apple Silicon macOS build, version/commit output and tunnel
help. ARM Linux derivation evaluation passed; Linux execution and authenticated
tunnel connections have not been tested. No tunnel is started by these checks.

## Hjem standalone files

The upstream `feel-co/hjem` CLI is pinned in `flake.lock`. The configuration uses
Hjem's common user module and `hjem-lib.fileToJson` manifest builder. The exposed
outputs are:

- `#hjem`: upstream standalone CLI.
- `#hjem-config`: evaluable standalone configuration for the current user.
- `#hjem-manifest`: validated schema-v3 JSON manifest.
- `hjemConfigurations.hwangsehyun.<system>`: declarative configuration value.
- `lib.mkHjemConfiguration SYSTEM { homeDirectory = "..."; }`: disposable-home builder.

Evaluate or build without changing `$HOME`:

```bash
nix eval --json "path:$PWD/nix#hjemConfigurations.hwangsehyun.$(nix eval --raw --impure --expr builtins.currentSystem).manifest" | jq
nix build "path:$PWD/nix#hjem-manifest"
HJEM="$(nix build --no-link --print-out-paths 'path:./nix#hjem')/bin/hjem"
CONFIG="$(nix build --no-link --print-out-paths 'path:./nix#hjem-config')"
"$HJEM" standalone build --config "$CONFIG"
```

Only after reviewing the manifest, activate it for the current configured home:

```bash
"$HJEM" standalone switch --config "$CONFIG"
```

Hjem preserves an unmanaged conflicting target using its upstream `.backup-`
prefix before writing the managed copy. It records generations below
`$XDG_STATE_HOME/hjem/standalone` (or `~/.local/state/hjem/standalone`). This
flake does not invoke `switch`, modify Home Manager/nix-darwin/NixOS, install SSH
private keys, store Remote.it credentials, or manage mutable Resilio state. Darwin additionally declares the
three SwiftBar plugin files under `~/SwiftBar`; select that directory in the
SwiftBar app manually. Linux omits them. Starship merges the two upstream presets
with the local TOML at build time, excludes `python.format`, and enables Kubernetes.
Atuin permissions are `0644`. Upstream currently publishes
standalone flake packages for `aarch64-darwin`, `aarch64-linux`, and
`x86_64-linux`, not `x86_64-darwin`. The pinned Hjem CLI requires Rust 1.95, so
its own pinned unstable Nixpkgs input is retained; command packages continue to
use this flake's separate `nixos-25.05` input.

## Tests

The integration test switches 20 files on Linux or 23 on Darwin only into
`./.hjem-test-work/home` and removes it. It verifies `remoteit-ssh --help` and
that the installed launcher contains no executing `eval` shell wrapper:

```bash
bash nix/tests/hjem-standalone.sh path:./nix
```
