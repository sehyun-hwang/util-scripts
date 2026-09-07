#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="$(command -v jq)"
assert_decision() {
    local expected="$1" input="$2" actual
    actual="$(printf '%s\n' "$input" | /bin/bash "$SCRIPT_DIR/local-plugins/byok-subagent-policy/scripts/byok-subagent-policy.sh" \
        | "$JQ" -r '.permissionDecision + ":" + .hookSpecificOutput.permissionDecision')"
    [[ "$actual" == "$expected:$expected" ]] || { printf 'Hook self-test expected %s, got %s\n' "$expected" "$actual" >&2; exit 1; }
}
assert_decision allow '{"toolName":"task","toolArgs":{"model":"customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol"}}'
assert_decision deny '{"toolName":"Task","toolArgs":{"model":"wrong-model"}}'
assert_decision allow '{"tool_name":"Agent","tool_input":{"model":"customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol"}}'
assert_decision deny '{"tool_name":"Agent","tool_input":{"model":"wrong-model"}}'
assert_decision deny '{"tool_name":"functions.task","tool_input":{}}'
assert_decision allow '{"tool_name":"grep","tool_input":{}}'
assert_decision allow '{"toolCalls":[{"name":"grep","args":{}},{"name":"task","args":{"model":"customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol"}}]}'
assert_decision deny '{"toolCalls":[{"name":"grep","args":{}},{"name":"task","args":{"model":"wrong-model"}}]}'
assert_decision deny '{"toolCalls":[]}'
assert_decision deny 'not-json'

printf 'All 10 hook tests passed.\n'
