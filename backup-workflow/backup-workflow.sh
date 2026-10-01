#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: backup-workflow.sh --destination PATH [--git PATH] [--remote NAME] [--dry-run]

Generate inventories directly in DESTINATION/<encoded-host>/_system/backup/,
then run backup-git-wip.sh from DESTINATION. No checkout or staging is required.
--git selects the Git repository scan root (default: HOME).
No upload or remote commands are performed.
--dry-run does not refresh inventories or create destination directories.
EOF
}
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
inventory_makefile=$script_dir/backup.mk
destination=''
dry_run=false
args=()
while (($#)); do
  case $1 in
    --destination|--git|--remote)
      (($# >= 2)) || { usage >&2; exit 2; }
      case $1 in
        --destination) destination=$2 ;;
        *) args+=("$1" "$2") ;;
      esac
      shift 2 ;;
    --dry-run) dry_run=true; args+=(--dry-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n $destination ]] || { usage >&2; exit 2; }
for cmd in realpath hostname make python3; do
  command -v "$cmd" >/dev/null || { printf 'Missing command: %s\n' "$cmd" >&2; exit 2; }
done
destination=$(realpath -m -- "$destination")
[[ -f $inventory_makefile ]] || { echo 'Inventory Makefile is missing.' >&2; exit 2; }
wip=$script_dir/backup-git-wip.sh
[[ -f $wip ]] || { echo 'backup-git-wip.sh must be installed alongside this script.' >&2; exit 2; }
host=$(hostname -s)
host=$(python3 -c 'import sys, urllib.parse; s=urllib.parse.quote(sys.argv[1], safe="-._"); print({"":"_", ".":"%2E", "..":"%2E%2E"}.get(s,s))' "$host")
inventory=$destination/$host/_system/backup
if [[ $dry_run == true ]]; then
  printf 'Would run make -f %q backup %q\n' "$inventory_makefile" "BACKUP_DIR=$inventory"
  [[ -d $destination ]] || { echo 'Destination does not exist; Git preview requires an existing destination.'; exit 0; }
else
  make -f "$inventory_makefile" backup "BACKUP_DIR=$inventory"
fi
cd -- "$destination"
exec bash "$wip" "${args[@]}"
