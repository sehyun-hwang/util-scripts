#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: backup-git-wip.sh [OPTIONS]

Back up staged, unstaged, and untracked non-ignored files from Git repositories
whose roots are at most two levels below the scan root.

Options:
  --dry-run          Show the files that would be copied without changing anything.
  --home PATH        Scan PATH instead of the current user's home directory.
  --remote NAME      Use remote NAME for repository identity (default: origin).
  -h, --help         Show this help.

The destination is rooted at:
  $PWD/<short-hostname>/<remote-host>/<remote-path>/<encoded-branch>/
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

path_is_within() {
  local path=$1
  local parent=$2
  [[ $path == "$parent" || $path == "$parent/"* ]]
}

# Retire destination files whose corresponding worktree path no longer exists.
# A single .backup generation is kept. Files already ending in .backup are left
# alone, and a real source path using the proposed backup name wins a collision.
retire_missing_destination_files() {
  local repo=$1
  local destination=$2
  local destination_path relative_path source_path retired_path

  retired_count=0
  retire_failed=false
  [[ -d $destination ]] || return 0

  while IFS= read -r -d '' destination_path; do
    relative_path=${destination_path#"$destination"/}
    [[ $relative_path != *.backup ]] || continue

    source_path=$repo/$relative_path
    if [[ -e $source_path || -L $source_path ]]; then
      continue
    fi

    retired_path=$destination_path.backup
    if [[ -e $repo/$relative_path.backup || -L $repo/$relative_path.backup ]]; then
      warn "cannot retire $(printf '%q' "$relative_path"): the source has a real .backup file"
      retire_failed=true
      continue
    fi

    if [[ $dry_run == true ]]; then
      printf '  would rename %q -> %q\n' "$destination_path" "$retired_path"
    elif ! mv -f -- "$destination_path" "$retired_path"; then
      warn "could not retire destination file: $(printf '%q' "$destination_path")"
      retire_failed=true
      continue
    fi
    retired_count=$((retired_count + 1))
  done < <(find "$destination" \( -type f -o -type l \) -print0)
}

# Encode an arbitrary string as one safe, reversible filesystem path segment.
encode_segment() {
  local input=$1
  local output=''
  local char hex
  local i
  local LC_ALL=C

  for ((i = 0; i < ${#input}; i++)); do
    char=${input:i:1}
    case $char in
      [A-Za-z0-9._-]) output+=$char ;;
      *)
        printf -v hex '%02X' "'$char"
        output+="%$hex"
        ;;
    esac
  done

  case $output in
    '') output=_ ;;
    '.') output=%2E ;;
    '..') output=%2E%2E ;;
  esac

  printf '%s' "$output"
}

# Convert common HTTPS, SSH, git, file, and scp-like Git URLs to a stable,
# credential-free host/path identity. SSH and HTTPS forms normalize identically.
normalize_remote_url() {
  local url=$1
  local rest authority host path segment encoded
  local -a segments=()
  local -a encoded_segments=()

  url=${url%%\#*}
  url=${url%%\?*}
  while [[ $url == */ ]]; do
    url=${url%/}
  done

  if [[ $url == *://* ]]; then
    rest=${url#*://}
    if [[ $rest == */* ]]; then
      authority=${rest%%/*}
      path=${rest#*/}
    else
      return 1
    fi

    authority=${authority##*@}
    if [[ $authority == \[*\]* ]]; then
      host=${authority#\[}
      host=${host%%\]*}
    else
      host=${authority%%:*}
    fi
    [[ -n $host ]] || host=_local
  elif [[ $url == *:* && ${url%%:*} != */* ]]; then
    authority=${url%%:*}
    path=${url#*:}
    host=${authority##*@}
    [[ -n $host ]] || return 1
  else
    host=_local
    path=$url
  fi

  while [[ $path == /* ]]; do
    path=${path#/}
  done
  while [[ $path == */ ]]; do
    path=${path%/}
  done
  [[ -n $path ]] || return 1

  path=${path%.git}
  [[ -n $path ]] || return 1
  host=${host,,}

  IFS='/' read -r -a segments <<< "$path"
  for segment in "${segments[@]}"; do
    [[ -n $segment ]] || continue
    encoded=$(encode_segment "$segment")
    encoded_segments+=("$encoded")
  done
  ((${#encoded_segments[@]} > 0)) || return 1

  printf '%s' "$(encode_segment "$host")"
  printf '/%s' "${encoded_segments[@]}"
}

dry_run=false
scan_home=${HOME:?HOME is not set}
remote_name=origin

while (($# > 0)); do
  case $1 in
    --dry-run)
      dry_run=true
      shift
      ;;
    --home)
      (($# >= 2)) || die '--home requires a path'
      scan_home=$2
      shift 2
      ;;
    --remote)
      (($# >= 2)) || die '--remote requires a name'
      remote_name=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

for command_name in git find hostname realpath sort mktemp mv; do
  command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done
if [[ $dry_run == false ]]; then
  command -v rsync >/dev/null 2>&1 || die 'required command not found: rsync'
fi

[[ -d $scan_home ]] || die "scan root is not a directory: $scan_home"
scan_home=$(realpath -m -- "$scan_home")
output_base=$(pwd -P)
machine_name=$(hostname -s) || die 'could not determine the short hostname'
machine_name=$(encode_segment "$machine_name")
output_root=$(realpath -m -- "$output_base/$machine_name")

task_tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-wip-backup.XXXXXX") || die 'could not create a temporary directory'
candidate_file=$task_tmp_dir/candidates
raw_file=$task_tmp_dir/raw
sorted_file=$task_tmp_dir/sorted
filtered_file=$task_tmp_dir/filtered

cleanup() {
  rm -f -- "$candidate_file" "$raw_file" "$sorted_file" "$filtered_file"
  rmdir -- "$task_tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

: > "$candidate_file"
if ! find "$scan_home" -mindepth 1 -maxdepth 3 \
  \( -path "$output_root" -o -path "$output_root/*" \) -prune -o \
  -name .git \( -type d -o -type f \) -print0 > "$candidate_file"; then
  warn "repository discovery reported an error under $scan_home"
fi

declare -a repo_roots=()
declare -a repo_destinations=()
declare -a repo_labels=()
declare -A seen_roots=()
declare -A destination_owner=()
declare -A conflicted_destinations=()

while IFS= read -r -d '' git_marker; do
  git_marker=$(realpath -m -s -- "$git_marker")
  # Secondary discovery guard in case the destination contains pattern-like
  # characters that make find(1)'s -path pruning less exact.
  path_is_within "$git_marker" "$output_root" && continue
  candidate=${git_marker%/.git}
  root=$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null) || continue
  root=$(realpath -m -- "$root")
  [[ $(git -C "$root" rev-parse --is-bare-repository 2>/dev/null) == false ]] || continue
  [[ -z ${seen_roots["$root"]+x} ]] || continue
  seen_roots["$root"]=1

  selected_remote=$remote_name
  if ! remote_url=$(git -C "$root" remote get-url -- "$selected_remote" 2>/dev/null); then
    mapfile -t configured_remotes < <(git -C "$root" remote)
    if ((${#configured_remotes[@]} == 1)); then
      selected_remote=${configured_remotes[0]}
      remote_url=$(git -C "$root" remote get-url -- "$selected_remote" 2>/dev/null) || {
        warn "skipping $(printf '%q' "$root"): cannot read its only remote"
        continue
      }
    else
      warn "skipping $(printf '%q' "$root"): remote '$remote_name' is unavailable or ambiguous"
      continue
    fi
  fi

  if ! remote_identity=$(normalize_remote_url "$remote_url"); then
    warn "skipping $(printf '%q' "$root"): remote '$selected_remote' has an unsupported URL"
    continue
  fi

  if branch_name=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null); then
    branch_label=$(encode_segment "$branch_name")
    branch_display=$branch_name
  elif commit_name=$(git -C "$root" rev-parse --short=12 HEAD 2>/dev/null); then
    branch_label="detached-$commit_name"
    branch_display=$branch_label
  else
    warn "skipping $(printf '%q' "$root"): cannot determine its branch or HEAD"
    continue
  fi

  destination=$output_root/$remote_identity/$branch_label
  if [[ -n ${destination_owner["$destination"]+x} && ${destination_owner["$destination"]} != "$root" ]]; then
    conflicted_destinations["$destination"]=1
  else
    destination_owner["$destination"]=$root
  fi

  repo_roots+=("$root")
  repo_destinations+=("$destination")
  repo_labels+=("$remote_identity [$branch_display]")
done < "$candidate_file"

if ((${#repo_roots[@]} == 0)); then
  log "No eligible Git repositories found under $scan_home."
  exit 0
fi

result=0
for index in "${!repo_roots[@]}"; do
  repo=${repo_roots[index]}
  destination=${repo_destinations[index]}
  label=${repo_labels[index]}

  if [[ -n ${conflicted_destinations["$destination"]+x} ]]; then
    warn "skipping $(printf '%q' "$repo"): another local repository maps to $destination"
    result=1
    continue
  fi

  : > "$raw_file"
  selection_ok=true
  git -C "$repo" diff --name-only -z --diff-filter=ACMRTUXB -- >> "$raw_file" || selection_ok=false
  git -C "$repo" diff --cached --name-only -z --diff-filter=ACMRTUXB -- >> "$raw_file" || selection_ok=false
  git -C "$repo" ls-files --others --exclude-standard -z -- >> "$raw_file" || selection_ok=false
  if [[ $selection_ok == false ]]; then
    warn "skipping $(printf '%q' "$repo"): Git could not enumerate changed files"
    result=1
    continue
  fi

  if ! sort -zu -- "$raw_file" > "$sorted_file"; then
    warn "skipping $(printf '%q' "$repo"): could not deduplicate its file list"
    result=1
    continue
  fi

  : > "$filtered_file"
  file_count=0
  while IFS= read -r -d '' relative_path; do
    case $relative_path in
      ''|/*|..|../*|*/../*|*/..)
        warn "rejecting unsafe Git path in $(printf '%q' "$repo")"
        result=1
        continue
        ;;
    esac

    source_path=$(realpath -m -s -- "$repo/$relative_path")
    if ! path_is_within "$source_path" "$repo"; then
      warn "rejecting path outside repository $(printf '%q' "$relative_path")"
      result=1
      continue
    fi

    # Primary recursion safeguard: output files can never enter rsync's list,
    # even when the output directory is inside this Git worktree.
    if path_is_within "$source_path" "$output_root"; then
      continue
    fi

    # Avoid copying a separately discovered nested repository through its parent.
    nested_repository=false
    for other_root in "${repo_roots[@]}"; do
      if [[ $other_root != "$repo" ]] \
        && path_is_within "$other_root" "$repo" \
        && path_is_within "$source_path" "$other_root"; then
        nested_repository=true
        break
      fi
    done
    [[ $nested_repository == false ]] || continue

    # A Git submodule is represented as a directory. Never give rsync a
    # directory entry, because that could expand into a full recursive copy.
    if [[ ! -f $source_path && ! -L $source_path ]]; then
      continue
    fi

    printf '%s\0' "$relative_path" >> "$filtered_file"
    file_count=$((file_count + 1))
  done < "$sorted_file"

  if [[ $dry_run == true ]]; then
    if ((file_count == 0)); then
      log "$label: no files would be copied"
    else
      log "$label: $file_count file(s) would be copied"
      while IFS= read -r -d '' relative_path; do
        printf '  %q -> %q\n' "$repo/$relative_path" "$destination/$relative_path"
      done < "$filtered_file"
    fi
    retire_missing_destination_files "$repo" "$destination"
    [[ $retire_failed == false ]] || result=1
    continue
  fi

  copy_ok=true
  if ((file_count == 0)); then
    log "$label: no files to copy"
  else
    if ! mkdir -p -- "$destination"; then
      warn "cannot create destination: $destination"
      result=1
      continue
    fi

    log "$label: copying $file_count file(s)"
    if ! rsync -a -r --checksum --from0 --files-from="$filtered_file" -- "$repo/" "$destination/"; then
      warn "rsync failed for $(printf '%q' "$repo")"
      result=1
      copy_ok=false
    fi
  fi

  if [[ $copy_ok == true ]]; then
    retire_missing_destination_files "$repo" "$destination"
    if ((retired_count > 0)); then
      log "$label: renamed $retired_count missing file(s) with .backup"
    fi
    [[ $retire_failed == false ]] || result=1
  fi
done

exit "$result"
