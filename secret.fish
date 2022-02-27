#!/bin/env fish

#echo $argv
#status dirname
set SECRETS (cat (status dirname)/.secret.csv)

for X in $SECRETS
    set LIST (string split ' ' $X)

    if contains $LIST[1] $argv
        set -x $LIST[1] $LIST[2]
        echo Setting $LIST[1] 1>&2
        echo $LIST[2]
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
