#!/bin/zsh

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin
state_dir="$HOME/Library/Caches/SwiftBar-TimeMachine"
state_file="$state_dir/state"
mkdir -p "$state_dir"

status_output="$(tmutil status 2>/dev/null || true)"
destination_output="$(tmutil destinationinfo 2>/dev/null || true)"

# Emit no menu-bar content while no Time Machine destination is mounted.
grep -q '^Mount Point[[:space:]]*:' <<<"$destination_output" || exit 0

latest="$(tmutil latestbackup 2>/dev/null || true)"

# latestbackup requires Full Disk Access and may fail when the destination is
# unmounted. Fall back to Time Machine's recorded snapshot dates.
if [[ -z "$latest" ]]; then
	latest="$(defaults read /Library/Preferences/com.apple.TimeMachine 2>/dev/null | awk '
    /SnapshotDates =/ { inside=1; next }
    inside && /^[[:space:]]*\);/ { inside=0 }
    inside && /[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
      gsub(/[",]/, ""); sub(/^[[:space:]]+/, ""); latest=$0
    }
    END { print latest }
  ')"
fi

latest_label="${latest:t}"
if [[ "$latest" == *" +"[0-9][0-9][0-9][0-9] ]]; then
	latest_label="$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$latest" '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || printf '%s' "$latest")"
fi

running=0
grep -Eq 'Running = (1|true);' <<<"$status_output" && running=1

previous_running=""
previous_latest=""
if [[ -r "$state_file" ]]; then
	IFS=$'\t' read -r previous_running previous_latest <"$state_file"
fi

notify() {
	osascript - "$1" "$2" <<'APPLESCRIPT' >/dev/null
on run argv
  display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

# Do not notify on the first SwiftBar refresh.
if [[ -n "$previous_running" ]]; then
	if [[ -n "$latest" && "$latest" != "$previous_latest" ]]; then
		notify "Time Machine" "Backup completed successfully."
	elif [[ "$previous_running" == 1 && "$running" == 0 && "$latest" == "$previous_latest" ]]; then
		notify "Time Machine" "Backup stopped without creating a new backup."
	fi
fi

printf '%s\t%s\n' "$running" "$latest" >"$state_file"

if ((running)); then
	percent="$(sed -nE 's/.*Percent = "?([0-9.]+)"?;.*/\1/p' <<<"$status_output" | head -1)"
	if [[ -n "$percent" ]]; then
		percent="$(awk -v p="$percent" 'BEGIN { printf "%d", p * 100 }')"
		echo "| color=#e5a50a sfimage=externaldrive.badge.timemachine"
	else
		echo "| color=#e5a50a sfimage=externaldrive.badge.timemachine"
	fi
else
	if [[ -n "$latest" ]]; then
		echo "| color=#2da44e sfimage=externaldrive.badge.checkmark"
	else
		echo "| color=#cf222e sfimage=externaldrive.badge.exclamationmark"
	fi
fi

echo "---"
if [[ -n "$latest" ]]; then
	echo "Last backup: $latest_label | trim=false"
else
	echo "Last backup: Never | color=#cf222e"
fi

if ((running)); then
	echo "Stop Backup | bash=/usr/bin/tmutil param1=stopbackup terminal=false refresh=true"
else
	echo "Run Backup Now | bash=/usr/bin/tmutil param1=startbackup terminal=false refresh=true"
fi

echo "Refresh | refresh=true"
echo "Open Time Machine Settings | bash=/usr/bin/open param1=x-apple.systempreferences:com.apple.Time-Machine-Settings.extension terminal=false"
