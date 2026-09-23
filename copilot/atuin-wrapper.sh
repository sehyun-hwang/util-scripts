#!/bin/sh
set -eu

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

export ATUIN_SESSION="$session_id"
key=$(printf '%s' "$payload" | jq -r '[.session_id, .tool_name, .tool_input] | @json' | shasum -a 256 | cut -d ' ' -f 1)
state="${TMPDIR:-/tmp}/atuin-copilot-${key}"

case "$event" in
  PreToolUse)
    intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
    history_id=$(atuin history start --author copilot --intent "$intent" -- "$command")
    printf '%s\n' "$history_id" > "$state"
    ;;
  PostToolUse)
    if [ -r "$state" ]; then
      history_id=$(cat "$state")
    else
      intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
      history_id=$(atuin history start --author copilot --intent "$intent" -- "$command")
    fi
    exit_code=$(printf '%s' "$payload" | jq -r '
      .tool_result.text_result_for_llm // ""
      | try capture("exit code (?<code>[0-9]+)").code catch "0"
    ')
    atuin history end --exit "$exit_code" "$history_id"
    rm -f "$state"
    ;;
  PostToolUseFailure)
    if [ -r "$state" ]; then
      history_id=$(cat "$state")
    else
      intent=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
      history_id=$(atuin history start --author copilot --intent "$intent" -- "$command")
    fi
    atuin history end --exit 1 "$history_id"
    rm -f "$state"
    ;;
esac
