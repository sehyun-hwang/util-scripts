#!/bin/env fish

#echo $argv >&2
#status dirname
set SECRETS (cat ~/.secret.csv)

for X in $SECRETS
    set LIST (string split ' ' $X)

    if contains $LIST[1] $argv
        set -x $LIST[1] $LIST[2]
        echo Setting $LIST[1] 1>&2
        echo $LIST[2] 1>&2
    end
end

for I in (seq (count $argv))
    set EXE $argv[$I]
    if which $EXE 1>&2
        $argv[$I..-1]
        exit
    end
end

echo 'Executable not found' 1>&2
exit 1
