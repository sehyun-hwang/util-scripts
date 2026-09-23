#!/bin/bash
# The hook must return promptly and must not consume or log the prompt on stdin.
app="$HOME/Applications/Amphetamine Helper.app"
if [[ -x "$app/Contents/MacOS/AmphetamineHelper" ]]; then
  if [[ -n "${COPILOT_HOME:-}" ]]; then
    /usr/bin/open -g --env "COPILOT_HOME=$COPILOT_HOME" -a "$app" >/dev/null 2>&1 || true
  else
    /usr/bin/open -g -a "$app" >/dev/null 2>&1 || true
  fi
fi
exit 0
