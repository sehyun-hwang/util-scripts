#!/bin/sh
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NO='\033[0m'
TITLE="$BLUE[$0]$NO"

lite-server &

FORMAT=$(echo "$TITLE $YELLOW%w%f$NO is written")
while inotifywait -qre close_write --format "$FORMAT" bs-config.js
do
    echo "$TITLE PID: $YELLOW$!$NO"
    kill -9 $!
    lite-server &
done