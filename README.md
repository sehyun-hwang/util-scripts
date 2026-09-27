# util-scripts

> Personal development environment managed with Nix and [Hjem](https://github.com/feel-co/hjem).

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
