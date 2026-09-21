#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: backup-workflow.sh --destination PATH [--repo PATH] [--home PATH] [--remote NAME] [--dry-run]

Refresh the util-scripts `make -f nix/assets/backup.mk backup` inventory, copy that
inventory to DESTINATION/<encoded-host>/_system/backup/, then run unchanged
backup-git-wip.sh from DESTINATION. No upload or remote commands are performed.
--repo selects the util-scripts repository checkout and defaults to the checkout
containing this source script; installed copies require --repo.
--dry-run does not refresh inventories or create destination directories.
EOF
}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo=$(cd -- "$script_dir/../../.." && pwd -P)
destination=''
dry_run=false
args=()
while (($#)); do
  case $1 in
    --destination|--repo|--home|--remote)
      (($# >= 2)) || { usage >&2; exit 2; }
      case $1 in
        --destination) destination=$2 ;;
        --repo) repo=$2 ;;
        *) args+=("$1" "$2") ;;
      esac
      shift 2 ;;
    --dry-run) dry_run=true; args+=(--dry-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n $destination ]] || { usage >&2; exit 2; }
for cmd in realpath hostname rsync make python3; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 2; }
done
repo=$(realpath -e -- "$repo")
destination=$(realpath -m -- "$destination")
inventory_makefile=$repo/nix/assets/backup.mk
[[ -f $inventory_makefile ]] || { echo 'Use --repo to select the util-scripts checkout.' >&2; exit 2; }
wip=$script_dir/backup-git-wip.sh
[[ -f $wip ]] || { echo 'backup-git-wip.sh must be installed alongside this script.' >&2; exit 2; }
case $destination/ in "$repo/backup/"*) echo 'Destination cannot be inside the inventory directory.' >&2; exit 2 ;; esac
if [[ -L $repo/backup ]]; then
  echo 'Inventory directory must not be a symlink.' >&2
  exit 2
fi
host=$(hostname -s)
host=$(python3 -c 'import sys, urllib.parse; s=urllib.parse.quote(sys.argv[1], safe="-._"); print({"":"_", ".":"%2E", "..":"%2E%2E"}.get(s,s))' "$host")
inventory=$destination/$host/_system/backup
if [[ $dry_run == true ]]; then
  printf 'Would run make -C %q -f nix/assets/backup.mk backup\n' "$repo"
  printf 'Would copy %q to %q\n' "$repo/backup/" "$inventory/"
  [[ -d $destination ]] || { echo 'Destination does not exist; Git preview requires an existing destination.'; exit 0; }
else
  make -C "$repo" -f nix/assets/backup.mk backup "BACKUP_DIR=$repo/backup"
  mkdir -p -- "$inventory"
  rsync -a --checksum -- "$repo/backup/" "$inventory/"
fi
cd -- "$destination"
exec bash "$wip" "${args[@]}"
