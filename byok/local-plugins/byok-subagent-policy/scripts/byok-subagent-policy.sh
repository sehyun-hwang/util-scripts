#!/bin/bash
set -u -o pipefail
readonly REQUIRED_MODEL='customendpoint/cliproxyapi customendpoint/chatgpt/gpt-5.6-sol'
JQ="$(command -v jq)"
if [[ -z "$JQ" ]]; then
    for candidate in /opt/homebrew/bin/jq /usr/local/bin/jq /usr/bin/jq; do
        if [[ -x "$candidate" ]]; then
            JQ="$candidate"
            break
        fi
    done
fi
readonly JQ
log_debug() {
    :
}
input_file="$(mktemp "${TMPDIR:-/tmp}/byok-subagent-policy.XXXXXX")" || exit 1
output_file="$(mktemp "${TMPDIR:-/tmp}/byok-subagent-policy.XXXXXX")" || {
    rm -f "$input_file"
    exit 1
}
cleanup() {
    rm -f "$input_file" "$output_file"
}
trap cleanup EXIT
cat >"$input_file"

classification="$($JQ -csr --arg model "$REQUIRED_MODEL" '
    def call:
        (.name | if type == "string" then . else "invalid" end) as $name
        | (.args | if type == "string" then (try fromjson catch null) else . end) as $args
        | {name:$name,
           model:(if ($name == "task" or $name == "Task" or $name == "functions.task" or $name == "Agent") then
                      (if ($args | type) == "object" and $args.model == $model then "match" else "mismatch" end)
                  else "not-task" end),
           allowed:(if (.name | type) != "string" then false
                    elif ($name == "task" or $name == "Task" or $name == "functions.task" or $name == "Agent") then
                        (($args | type) == "object" and $args.model == $model)
                    else true end)};
    (if length == 1 then .[0] else null end)
    | if type != "object" then ["invalid", "invalid", "invalid", "deny"]
      elif has("toolCalls") and (.toolCalls | type) == "array" then
          (.toolCalls | map(call)) as $calls
          | if ($calls | length) == 0 then ["toolCalls", "empty", "invalid", "deny"]
            else ["toolCalls", ($calls | map(.name) | join(",")), ($calls | map(.model) | join(",")),
                  (if all($calls[]; .allowed) then "allow" else "deny" end)] end
      elif has("toolName") then ({name:.toolName,args:.toolArgs} | call) as $call
          | ["toolName", $call.name, $call.model, (if $call.allowed then "allow" else "deny" end)]
      elif has("tool_name") then ({name:.tool_name,args:.tool_input} | call) as $call
          | ["tool_name", $call.name, $call.model, (if $call.allowed then "allow" else "deny" end)]
      else ["unknown", "invalid", "invalid", "deny"] end
    | @tsv
' <"$input_file" 2>/dev/null)"
classification_status=$?
if [[ $classification_status -eq 0 ]]; then
    IFS=$'\t' read -r input_shape tool_names model_match expected_decision <<<"$classification"
else
    input_shape='invalid'
    tool_names='invalid'
    model_match='invalid'
    expected_decision='deny'
fi

if "$JQ" -cs --arg model "$REQUIRED_MODEL" '
    def call_allowed:
        if (.name | type) != "string" then false
        elif (.name == "task" or .name == "Task" or .name == "functions.task" or .name == "Agent") then
            (.args | if type == "string" then (try fromjson catch null) else . end)
            | if type == "object" then .model == $model else false end
        else true end;
    def result($decision; $reason):
        {permissionDecision:$decision,
         hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$decision}}
        | if $reason == null then .
          else .permissionDecisionReason = $reason
             | .hookSpecificOutput.permissionDecisionReason = $reason end;
    (if length == 1 then .[0] else null end)
    | (if type != "object" then false
       elif has("toolCalls") then
           if (.toolCalls | type) == "array" and (.toolCalls | length) > 0 then
               all(.toolCalls[]; call_allowed)
           else false end
       elif has("toolName") then {name:.toolName,args:.toolArgs} | call_allowed
       elif has("tool_name") then {name:.tool_name,args:.tool_input} | call_allowed
       else false end) as $allowed
    | if $allowed then result("allow"; null)
      else result("deny"; "Subagent requires explicit model " + $model) end
' <"$input_file" >"$output_file" 2>/dev/null; then
    jq_status=0
else
    jq_status=$?
    printf '%s\n' '{"permissionDecision":"deny","permissionDecisionReason":"Invalid hook input; BYOK policy cannot be enforced.","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Invalid hook input; BYOK policy cannot be enforced."}}' >"$output_file"
fi
actual_decision="$($JQ -r '.permissionDecision // "invalid"' "$output_file" 2>/dev/null || printf invalid)"
log_debug "phase=result shape=$(printf %q "$input_shape") tools=$(printf %q "$tool_names") model=$(printf %q "$model_match") expected=$expected_decision actual=$actual_decision classify_status=$classification_status jq_status=$jq_status exit_status=0"
cat "$output_file"
