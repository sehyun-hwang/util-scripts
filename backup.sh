DEPTH=2
ROOT=.backup
cd /mnt
COMMAND=echo
COMMAND="zip -FS"

echo =========================

find . -maxdepth $DEPTH | while read x; do
    [[ -f $x ]] && continue
    [[ $x == *node_modules ]] && continue

    x=${x:2}
    [[ $x == volatile* ]] && continue
    [[ $x == .backup* ]] && continue

    echo ============================

    if (( `echo $x | grep -o / | wc -l` < $DEPTH-1 )); then
        echo Files: $x
        ZIP=$ROOT/`echo $x | tr / -`.zip
        echo $ZIP
        $COMMAND $ZIP `find $x -type f -maxdepth 1`

    else
        echo A directory: $x
        ZIP=$ROOT/`echo $x | tr / -`.zip
        echo $ZIP
        $COMMAND $ZIP -r $x
    fi

    [[ $COMMAND == echo ]] && sleep 1
done

aws s3 sync --no-sign-request --endpoint-url https://nextlab.hwangsehyun.com:41443/s3 .backup s3://hwangsehyun/backup
ssh nextlab /opt/homebrew/bin/aws s3 sync --no-sign-request --endpoint-url http://localhost/s3 s3://hwangsehyun/backup backup2