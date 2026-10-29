#!/bin/sh
set -eu

wrapper="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/atuin-wrapper.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export TMPDIR="$tmp" ATUIN_TEST_LOG="$tmp/calls"
mkdir "$tmp/bin"
cat > "$tmp/bin/atuin" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$ATUIN_TEST_LOG"
case "$*" in
  'history start '*) printf 'test-history-id\n' ;;
esac
EOF
chmod +x "$tmp/bin/atuin"
export ATUIN_BIN="$tmp/bin/atuin"

run_hook() {
  jq -nc --arg event "$1" --arg result "${2:-}" '{
    hook_event_name: $event, session_id: "atuin-hook-test", tool_name: "Bash",
    tool_input: {command: "printf test", description: "Test intent"},
    tool_result: {text_result_for_llm: $result}
  }' | sh "$wrapper"
}

run_hook PreToolUse
run_hook PostToolUse 'Process exited with exit code 7'
run_hook PostToolUseFailure
run_hook PreToolUse
run_hook PostToolUseFailure
cat > "$tmp/expected" <<'EOF'
history start --author copilot --intent Test intent -- printf test
history end --exit 7 test-history-id
history start --author copilot --intent Test intent -- printf test
history end --exit 1 test-history-id
history start --author copilot --intent Test intent -- printf test
history end --exit 1 test-history-id
EOF
diff -u "$tmp/expected" "$ATUIN_TEST_LOG"
[ -z "$(find "$tmp" -name 'atuin-copilot-*' -print)" ]

# Keep installed clients outside the test fixture from affecting discovery.
sed -e "s|/opt/homebrew/opt/atuin/bin/atuin|$tmp/missing-homebrew|g" \
  -e "s|/usr/local/opt/atuin/bin/atuin|$tmp/missing-local|g" \
  -e "s|\$HOME/.nix-profile/bin/atuin|$tmp/missing-profile|g" \
  -e "s|/nix/var/nix/profiles/default/bin/atuin|$tmp/missing-nix|g" \
  "$wrapper" > "$tmp/wrapper.sh"
wrapper="$tmp/wrapper.sh"
mkdir "$tmp/old" "$tmp/new client" "$tmp/tools"
for tool in sh jq awk grep shasum cut cat rm; do
  ln -s "$(command -v "$tool")" "$tmp/tools/$tool"
done
cat > "$tmp/client" <<'EOF'
#!/bin/sh
case "$*" in
  --version) printf 'atuin %s (test)\n' "$CLIENT_VERSION" ;;
  'daemon status')
    [ "$DAEMON_VERSION" != missing ] || exit 1
    printf 'Daemon running\n  Version: %s\n  Healthy: true\n' "$DAEMON_VERSION"
    ;;
  *)
    printf '%s: %s\n' "$CLIENT_VERSION" "$*" >> "$ATUIN_TEST_LOG"
    case "$*" in 'history start '*) printf 'test-history-id\n' ;; esac
    ;;
esac
EOF
for entry in old 'new client'; do
  version=1.0.0
  [ "$entry" = old ] || version=2.0.0
  printf '#!/bin/sh\nexport CLIENT_VERSION=%s\nexec /bin/sh "%s/client" "$@"\n' "$version" "$tmp" > "$tmp/$entry/atuin"
  chmod +x "$tmp/$entry/atuin"
done
unset ATUIN_BIN
export PATH="$tmp/old:$tmp/new client:$tmp/old:$tmp/tools"
export DAEMON_VERSION=2.0.0
run_hook PostToolUse 'Process exited with exit code 0'
tail_result=$(/usr/bin/tail -n 1 "$ATUIN_TEST_LOG")
[ "$tail_result" = '2.0.0: history end --exit 0 test-history-id' ]

export DAEMON_VERSION=1.0.0
run_hook PostToolUse 'Process exited with exit code 0'
tail_result=$(/usr/bin/tail -n 1 "$ATUIN_TEST_LOG")
[ "$tail_result" = '1.0.0: history end --exit 0 test-history-id' ]

for version in 3.0.0 missing; do
  export DAEMON_VERSION="$version"
  if run_hook PostToolUse 2> "$tmp/error"; then
    printf 'Expected discovery failure for daemon %s\n' "$version" >&2
    exit 1
  fi
  grep -q 'Atuin hook:' "$tmp/error"
  [ "$(/usr/bin/tr -cd '\007' < "$tmp/error" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" = 1 ]
done
export ATUIN_BIN="$tmp/failing-atuin"
printf '#!/bin/sh\nexit 17\n' > "$ATUIN_BIN"
/bin/chmod +x "$ATUIN_BIN"
result=0
run_hook PreToolUse 2> "$tmp/error" || result=$?
[ "$result" = 17 ]
[ "$(/usr/bin/tr -cd '\007' < "$tmp/error" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" = 1 ]
printf '{"tool_name":"other"}' | /bin/sh "$wrapper" 2> "$tmp/error"
[ ! -s "$tmp/error" ]
printf 'Atuin hook tests passed\n'
