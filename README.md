# util-scripts

> Personal development environment managed with Nix and [Hjem](https://github.com/feel-co/hjem).

Nixpkgs tracks `nixos-26.05`. Restish 2.3.0, ToolHive 0.51.4 (with the
explicit-OAuth patch), and remoteit-ssh 0.3.1 use non-flake source inputs pinned
in `flake.lock`. Restish and remoteit-ssh were already at their latest upstream
release/revision when checked. VS Code retains its separate source pin.

The SwiftBar Time Machine section queries `tmutil status` and `tmutil latestbackup`
live, without cached state or preference-file lookups. Resilio status is also
queried on every refresh without caching. Only AWS cost data retains its cache.

## Usage

### Hjem file activation

Build

```bash
hjem standalone build \
  --config (nix build --print-out-paths "git+file:$PWD#hjem-config")

# Alternatively, use the repository's pinned Hjem:
nix run "git+file:$PWD#hjem" -- standalone build \
  --config (nix build --print-out-paths "git+file:$PWD#hjem-config")
```

Switch

```bash
hjem standalone switch \
  --config (nix build --print-out-paths "git+file:$PWD#hjem-config")

# Alternatively, use the repository's pinned Hjem:
nix run "git+file:$PWD#hjem" -- standalone switch \
  --config (nix build --print-out-paths "git+file:$PWD#hjem-config")
```

### Backups

```sh
backup-workflow.sh --destination /path/to/backups --git "$HOME"
```

The Nix package includes the inventory Makefile; no checkout or `--repo` is
needed. Inventories are generated directly in
`<destination>/<host>/_system/backup/`, without staging or copying from the checkout.
A failed inventory run can leave partial inventory updates; Git snapshots run
only after inventory generation succeeds.

`--git` replaces `--home` and selects the Git scan root (default: `$HOME`) for
both `backup-workflow.sh` and `backup-git-wip.sh`. Repository roots must be at
most two directory levels below that root. Use `--dry-run` to preview without
writing inventories or snapshots. For Git-only backups, run `backup-git-wip.sh`
from the destination directory.

Repositories without a usable remote are backed up under
`<destination>/<host>/_local/<folder-name>/<branch>/`, outside remote-host
folders such as `github.com`. Folder and branch names are encoded for safe paths.
A sole non-origin remote is still used when available. Repositories mapping to
the same destination are rejected rather than overwriting each other.

## Testing

```bash
python3 -m unittest discover -s resilio/tests -v
python3 -m unittest discover -s backup-workflow/tests -v
```

## Post Install

### Amphetamine

Set Trigger

1. Amphetamine icon on menu bar → Preferences → Triggers
1. Add Amphetamine Helper.app

### Resilio Sync

Configure Sync

### ToolHive

Install skills

```bash
skopeo --insecure-policy copy \
  "oci:$(nix build .#committing-with-commitlint-oci --print-out-paths):committing-with-commitlint" \
  "oci:$HOME/Library/Application Support/ToolHive/skills:committing-with-commitlint"
thv-patched skill install committing-with-commitlint
```
