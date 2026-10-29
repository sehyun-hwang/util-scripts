#!/bin/sh
set -eu

on_exit() {
  result=$?
  trap - 0
  if [ "$result" -ne 0 ]; then
    printf '\007' >&2
  fi
  exit "$result"
}
trap on_exit 0

payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty')
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')

case "$tool" in
  bash|Bash) ;;
  *) exit 0 ;;
esac

session_id=$(printf '%s' "$payload" | jq -r '.session_id // "copilot"')
command=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
[ -n "$command" ] || exit 0

if [ -z "${ATUIN_BIN:-}" ]; then
  candidates=$(
    {
      printf '%s' "$PATH" | awk -v RS=: 'length { print $0 "/atuin" }'
      printf '\n%s\n' /opt/homebrew/opt/atuin/bin/atuin /usr/local/opt/atuin/bin/atuin \
        "$HOME/.nix-profile/bin/atuin" /nix/var/nix/profiles/default/bin/atuin
    } | awk 'length && !seen[$0]++'
  )
  # Status comes from the live daemon, not the potentially upgraded binary on disk.
  daemon_version=$(
    printf '%s\n' "$candidates" | while IFS= read -r candidate; do
      [ -x "$candidate" ] || continue
      status=$("$candidate" daemon status 2>/dev/null) || continue
      printf '%s\n' "$status" | grep -Eq '^[[:space:]]*Healthy:[[:space:]]*true[[:space:]]*$' || continue
      version=$(printf '%s\n' "$status" | awk '$1 == "Version:" { print $2; exit }')
      [ -n "$version" ] || continue
      printf '%s\n' "$version"
      break
    done
  )
  if [ -z "$daemon_version" ]; then
    printf '%s\n' 'Atuin hook: cannot identify a healthy running daemon; set ATUIN_BIN to override.' >&2
    exit 1
  fi
  ATUIN_BIN=$(
    printf '%s\n' "$candidates" | while IFS= read -r candidate; do
      [ -x "$candidate" ] || continue
      version=$("$candidate" --version 2>/dev/null) || continue
      version=$(printf '%s\n' "$version" | awk '$1 == "atuin" { print $2; exit }')
      [ "$version" = "$daemon_version" ] || continue
      printf '%s\n' "$candidate"
      break
    done
  )
  if [ -z "$ATUIN_BIN" ]; then
    printf 'Atuin hook: no client matches running daemon version %s; set ATUIN_BIN to override.\n' "$daemon_version" >&2
    exit 1
  fi
fi

export ATUIN_SESSION="$session_id"
key=$(printf '%s' "$payload" | jq -r '[.session_id, .tool_name, .tool_input] | @json' | shasum -a 256 | cut -d ' ' -f 1)
state="${TMPDIR:-/tmp}/atuin-copilot-${key}"

case "$event" in
  PreToolUse)
    intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
    history_id=$("$ATUIN_BIN" history start --author copilot --intent "$intent" -- "$command")
    printf '%s\n' "$history_id" > "$state"
    ;;
  PostToolUse)
    if [ -r "$state" ]; then
      history_id=$(cat "$state")
    else
      intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
      history_id=$("$ATUIN_BIN" history start --author copilot --intent "$intent" -- "$command")
    fi
    exit_code=$(printf '%s' "$payload" | jq -r '
      .tool_result.text_result_for_llm // ""
      | try capture("exit code (?<code>[0-9]+)").code catch "0"
    ')
    "$ATUIN_BIN" history end --exit "$exit_code" "$history_id"
    rm -f "$state"
    ;;
  PostToolUseFailure)
    if [ -r "$state" ]; then
      history_id=$(cat "$state")
    else
      intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
      history_id=$("$ATUIN_BIN" history start --author copilot --intent "$intent" -- "$command")
    fi
    "$ATUIN_BIN" history end --exit 1 "$history_id"
    rm -f "$state"
    ;;
esac
