#!/bin/bash
# <swiftbar.title>Copilot Awake</swiftbar.title>
# <swiftbar.desc>Keep awake while local Copilot sessions are working without ending user Amphetamine sessions.</swiftbar.desc>
# <swiftbar.dependencies>python3</swiftbar.dependencies>
export PATH="$HOME/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
exec python3 "$(dirname "$0")/copilot-awake/main.py"
