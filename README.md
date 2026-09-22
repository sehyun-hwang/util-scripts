# util-scripts

> Personal development environment managed with Nix and Hjem.

The legacy Makefile and its duplicate installers have been removed. Inventory
capture remains available through the canonical [backup-workflow/backup.mk](backup-workflow/backup.mk).

## Usage

### VS Code

1. [Optional] Create [`.vscode/extensions.json`](.vscode/extensions.json) from machine A

    ```sh
    jq '[.[] | .identifier.id] | {"recommendations": . }' -r < ~/.vscode-server/extensions/extensions.json > .vscode/extensions.json
    ```

1. Open this workspace in machine B

    ```sh
    code tunnel
    # Optional Linux resource limits:
    systemd-run -p MemoryMax=2.5G -p MemorySwapMax=2G --user --scope code tunnel
    ```

1. Install recommended extensions

### VS Code CLI installation

`nix build 'git+file:'"$PWD"'#vscode-cli'` builds pinned VS Code 1.137.0 with matching
product metadata and source/Cargo hashes. Hjem installs it to `~/.local/bin/code`.

To update it, update the isolated `vscode-nixpkgs` input, confirm
`vscodePkgs.vscode.version` and `vscodePkgs.vscode.rev`, then update
`vscodeSource.hash` and `cargoHash`. The build verifies source/product version
and commit agreement plus the resulting `code --version`.

### Copilot subagent model policy (macOS)

Activate the Hjem configuration described below to install the policy files
from [copilot](copilot). Hjem backs up conflicting unmanaged files; it does not
change VS Code settings automatically. Runtime requires Bash,
`jq`, a VS Code build supporting Agent Plugins, and `chatgpt/gpt-5.6-sol`
registered in each channel you use. The hook finds `jq` on PATH or in standard
Homebrew/system locations. Installation includes the global instruction,
standalone hook, and an Agent Plugins 1.0 package at
`~/.copilot/local-plugins/byok-subagent-policy`. Its `PreToolUse` hook requires
this exact model for `task`, `Task`, `functions.task`, and VS Code's runtime
`Agent` alias:

`customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol`

The parent chat model is unrestricted. **Register the plugin manually** in both
Stable and Insiders user settings, merging this entry into any existing
`chat.pluginLocations` object (replace `/Users/YOUR_USER` with your home path):

```jsonc
"chat.pluginLocations": {
  "/Users/YOUR_USER/.copilot/local-plugins/byok-subagent-policy": true
}
```

Ensure `chat.plugins.enabled` is not disabled. Installation does not modify
Settings Sync, guidance settings, Agent Host configuration, or either channel's
settings. Non-executable policy files have mode 600 and executable scripts
have mode 700.

Both hook configurations invoke `/bin/bash` with a quoted `$HOME` path. One
canonical script is installed to both hook destinations. It accepts SDK
`toolName`/`toolArgs`, batched `toolCalls`, and command-hook
`tool_name`/`tool_input` payloads, emitting both SDK and VS Code decisions.
The standalone compatibility hook and plugin hook may both run. Remove any
existing standalone `.disabled` marker manually if that hook should be active.

Run the existing policy self-tests with:

```bash
bash copilot/test-policy.sh
```

Reload Stable and Insiders after installation, verify discovery in
**Chat: Open Customizations**, and verify enforcement in fresh sessions.
The plugin requests a five-second hook timeout. Error, timeout, and multiple-hook
handling depend on the active Agent Host runtime; local tests do not prove
provider reachability or live pre-provider enforcement. Do not treat this
plugin as a tamper-proof machine security boundary.

## Local backup workflow

The old ZIP/S3/SSH `backup.sh` has been removed. The canonical
[backup-workflow/backup-git-wip.sh](backup-workflow/backup-git-wip.sh)
remains unchanged; [backup-workflow.sh](backup-workflow/backup-workflow.sh)
orchestrates inventory capture and Git WIP snapshots without uploading anything.

```bash
make -f backup-workflow/backup.mk backup
bash backup-workflow/backup-workflow.sh --repo "$PWD" --destination "$HOME/Backups/git-wip" --home "$HOME"
```

Use the Nix-packaged commands below, or put Bash 4+ and GNU coreutils/findutils
on PATH (macOS `/bin/bash` and `realpath` are not sufficient). Runtime also needs
Git, rsync, GNU-compatible make, and Python 3.

`make -f backup-workflow/backup.mk backup` records available package-manager inventories
and SSH/VS Code configuration into [backup/](backup/). The workflow invokes the
canonical [backup-workflow/backup.mk](backup-workflow/backup.mk) directly; no root Makefile
or compatibility link is required.
Missing optional tools/configuration are skipped; failures from available tools
stop the workflow. Existing inventory files are retained, including those from
other platforms. Override `VSCODE_SETTINGS` for a non-default settings file.

The workflow refreshes this inventory first, copies it to
`DESTINATION/<encoded-host>/_system/backup/`, then invokes the original WIP script
with `DESTINATION` as its working directory. The inventory is copied explicitly,
so it is included even if the checkout is outside the WIP scan depth or its files
are clean/ignored. `--dry-run` does not refresh inventories or create directories;
a full Git preview requires an already-existing destination.

WIP snapshots contain current working-tree contents of staged/unstaged/untracked
non-ignored files, **not separate index versions, commits, or restoration patches**.
Deleted source paths retire existing copies with a single `.backup` suffix; clean
files retain their previous copies. Duplicate repository destinations are rejected.
Only repository roots within the script's documented scan depth are considered.
Symlinks are copied as symlinks. Resilio synchronization is not immutable backup
retention and can propagate deletion or corruption. Review inventories and
untracked files for private information before sharing a destination.

## Install with Hjem

The [root flake](flake.nix) packages the tools and configuration assets,
the backup commands, and all five SwiftBar plugin files. Hjem standalone handles
declarative file activation and command installation; no separate package profile is needed.
This does not modify existing Home Manager, nix-darwin, NixOS configuration, or
Python virtual environments. Do not assign the same destination files to both
Hjem and another configuration manager.
Keep a durable GC root for the Hjem configuration and its runtime dependencies:

```bash
FLAKE="git+file:$PWD"
GCROOT="${XDG_STATE_HOME:-$HOME/.local/state}/nix/gcroots/util-scripts-hjem-config"

mkdir -p "$(dirname "$GCROOT")"
nix build --out-link "$GCROOT" "$FLAKE#hjem-config"
nix run "$FLAKE#hjem" -- standalone switch --config "$GCROOT"

# Hjem installs selected commands in ~/.local/bin.
"$HOME/.local/bin/backup-workflow.sh" --repo "$PWD" --destination "$HOME/Backups/git-wip" --dry-run
"$HOME/.local/bin/resilio-restish" --help
"$HOME/.local/bin/restish" --version
"$HOME/.local/bin/thv-patched" version
```

The `git+file:$PWD` source includes only files tracked by Git and therefore excludes
untracked cache and machine-specific inventories. It also includes the repository's
tracked `backup/` inventories; review their path/content policy before publishing or
sharing the flake source. Newly added implementation files must be staged or
committed before Nix can see them; changes to already tracked files are visible.
Do not use `path:.`, which copies the whole working tree to the Nix store. Components have one canonical root tree; there
are no compatibility mirrors.

Available individual outputs include `#backup-workflow`, `#backup-git-wip`,
`#remoteit-ssh`, `#resilio`, `#restish`, `#thv-patched`, `#awscli2`,
`#vscode-cli`, `#committing-with-commitlint`, and
`#committing-with-commitlint-oci`. Restish 2.3.0 is built from tagged source commit
`6305246a75121a7373563577e50e9bf522baca6b`, not a release binary. ToolHive
0.46.0 is built from commit `c6c425a924fac51c86cbade15d0e720e29a600ab`
with [the explicit-OAuth patch](patches/toolhive-explicit-oauth.patch). The
`thv-patched` wrapper defaults `TOOLHIVE_SKIP_DESKTOP_CHECK=1`; an explicitly
set environment value overrides the default, and the existing `thv` command is
left untouched.

### ToolHive skill installation

The `committing-with-commitlint` skill is packaged as an OCI artifact built
with `dockerTools.buildImage` and `skopeo`. Hjem installs the SKILL.md to
`~/.claude/skills/` for direct use. To install it into the ToolHive skill
store:

```bash
nix build .#committing-with-commitlint-oci

# Copy blobs into the thv store
STORE=~/Library/Application\ Support/ToolHive/skills
cp result/blobs/sha256/* "$STORE/blobs/sha256/"

# Merge the OCI index entry (adds the local-build annotation)
python3 -c "
import json, sys
store_path, new_path = '$STORE/index.json', 'result/index.json'
with open(store_path) as f: store = json.load(f)
with open(new_path) as f: new = json.load(f)
refs = {m.get('annotations',{}).get('org.opencontainers.image.ref.name') for m in store.get('manifests',[])}
for m in new['manifests']:
    ref = m.get('annotations',{}).get('org.opencontainers.image.ref.name')
    if ref not in refs:
        m.setdefault('annotations',{})['dev.stacklok.toolhive.local-build'] = 'true'
        store['manifests'].append(m)
with open(store_path,'w') as f: json.dump(store, f, separators=(',',':'))
"

# Install and register with Claude Code
thv-patched skill install committing-with-commitlint --clients claude-code
```

Resilio itself remains an external application. The stale ECR, Lambda, and
secret helper sources have been removed. Hjem installs `code`, `remoteit-ssh`,
`restish`, `thv-patched`, `resilio-restish`, and both backup commands into
`~/.local/bin`; use `code tunnel`.
The updated Nix CLI is pinned to 1.137.0. Existing PATH precedence is unchanged;
use `~/.local/bin/code` to select this binary explicitly.

### Hjem file activation

Pinned upstream [Hjem](https://github.com/feel-co/hjem) replaces the custom asset
installer. Building packages does not activate configuration files.
Build and validate the configuration first. This does not activate files:

```bash
FLAKE="git+file:$PWD"
CONFIG=$(nix build --no-link --print-out-paths "$FLAKE#hjem-config")
nix build "$FLAKE#hjem-manifest"
nix run "$FLAKE#hjem" -- standalone build --config "$CONFIG"
```

The default configuration targets **hwangsehyun**, with `/Users/hwangsehyun` on
Darwin and `/home/hwangsehyun` on Linux; it does not infer a different home from
the caller. Review the manifest and destination paths before explicitly running the
`standalone switch --config` command above. The flake exposes `#hjem-manifest`
for inspection and `lib.mkHjemConfiguration` for custom-home configuration;
[the integration test](tests/hjem-standalone.sh) activates only a disposable home.
Hjem handles file conflicts and generations using upstream behavior, including
backing up unmanaged conflicting targets with its `.backup-` prefix. Do not
activate files already owned by Home Manager.

On macOS, the manifest includes plugins under
`~/SwiftBar`; select that folder in SwiftBar (preferences are not changed automatically).
Starship is built by recursively merging `no-nerd-font`, `no-runtime-versions`,
and local TOML in that order; local values win, `python.format` is removed, and
Kubernetes is enabled. Atuin configuration is installed with mode `0644`.
Python paths are pinned by Nix. Builds alone do not change
that directory. Private keys and mutable Resilio state are not managed.

The Hjem integration test expects 26 managed files on macOS and 21 on Linux,
including the new `thv-patched` command. Build/switch, repeated activation and
unmanaged-conflict handling were tested in a disposable home on Apple Silicon
macOS. Linux evaluation passed;
the OrbStack VM became unresponsive during the upstream Rust build, so Linux
Hjem runtime testing remains unverified. Supported package systems are currently
`aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. Backup and Resilio tests
pass; actual GUI operation still requires the external macOS applications.

## Resilio WebUI and SwiftBar

[resilio/resilio-restish](resilio/resilio-restish) uses Restish to access the
existing licensed Resilio installation through its unofficial loopback WebUI.
The former Python API/lifecycle client is removed. The small Python auth hook
and response checker remain; tokens/cookies live only in request memory.

```bash
resilio-restish status
resilio-restish pause FOLDER_ID
resilio-restish resume FOLDER_ID
```

Enable the local WebUI in Resilio configuration separately. This integration
does not configure, restart, or register shares automatically. Port discovery
uses the storage PID and loopback listeners. Never commit credentials/state.

Register the destination folder in your existing licensed Resilio installation
before using pause/resume. The wrapper identifies the share by path or ID:

```bash
resilio-restish run-paused "$HOME/Backups/git-wip" -- \
  bash "$PWD/backup-workflow/backup-workflow.sh" --repo "$PWD" \
  --destination "$HOME/Backups/git-wip" --home "$HOME"
```

This waits for pause acknowledgement, runs inventory/WIP capture, and restores
the original preference state even if the command fails. A share that was
already paused stays paused. `pause`, `resume`, and `wait-paused` are also
available. A bounded pause-state wait is **not** a guarantee that all remote
peers have finished receiving files; destination testing remains necessary.

The [SwiftBar/BitBar plugin](resilio/resilio.10m.py) periodically displays
read-only folder status and offers Open Resilio Sync and Refresh actions.
It uses the packaged Restish launcher. It never starts or restarts Resilio automatically during
refresh. Enable discovery/synchronization and connect the destination through
Resilio itself; this implementation does not silently register production shares.

### Unofficial API specification

[resilio/openapi.yaml](resilio/openapi.yaml) describes the observed Resilio Sync
3.1.2 WebUI protocol, not a vendor-supported stable API. The single `/gui/`
endpoint dispatches on its `action` query parameter. Authentication uses
`POST /gui/token.html` plus session cookies; never log token-bearing query URLs.
Application errors can be returned inside HTTP 200 responses. Folder preference
updates require the full current preferences, including transfer priority.

### Direct Restish usage

The static config, schema, lifecycle wrapper, external-auth request hook, and
tests all live in the single canonical [resilio](resilio) component tree.
`resilio-restish` is a narrow checked launcher: it selects that config and
helper, runs Restish directly, and validates the resulting JSON for Resilio
application errors that may otherwise be hidden inside HTTP 200 responses.

```bash
resilio-restish resilio web-ui-action getsyncfolders
resilio-restish resilio web-ui-action folderpref --id FOLDER_ID
resilio-restish resilio web-ui-action getsysteminfo
```

The external hook validates and authenticates only the documented read-only
requests, discovers the local Resilio listener, and keeps token/cookie values in
memory. Restish performs transport/status checks; the small response checker preserves
the same top-level `error`, nested `value.error`, and application `status`
checks as the removed Python client. Use the lifecycle subcommands for verified
pause/restore behavior. Restish's first-run helper hash approval remains in force. The API is
unofficial and version-sensitive.

### Remote.it SSH command

Nix packages upstream `conor-f/remoteit-ssh` 0.3.1 unchanged at commit
`5a9e82b018cdc1957c71f3b88e2820bf718d597a`, with its exact
`requests-http-signature` 0.1.0 dependency. The upstream install hook that edits
`~/.zshrc` is disabled; the packaged `remoteit-ssh` command directly invokes the
upstream Python entry point. No local wrapper or patch changes its behavior: it
selects the first matching device and first service, then **prints** an SSH
command. It does not execute SSH.

Credentials stay outside the Nix store in the upstream default file
`~/.config/remoteit_ssh/config.ini` or another path passed with `--file`.
Validation uses only `remoteit-ssh --help`; it performs no Remote.it request.
The former `ssh-mac.py`, EC2 helper, shared interactive shell, and their virtual
environment recipes were removed.

### Focused tests

```bash
python3 -m unittest discover -s resilio/tests -v
python3 -m unittest discover -s backup-workflow/tests -v
```

Backup tests require the same modern Bash/GNU runtime as the scripts. They use
disposable repositories, never a real backup destination. Resilio unit tests
mock transport and lifecycle operations and do not change live shares.
