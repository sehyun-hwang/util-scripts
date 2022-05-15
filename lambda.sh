set -e

S3=nextlab

ARG=$1
echo $ARG
[ ! -f package.json ] || AWSARG=$(jq -r '.CLI // ""' package.json)

[ -z "$NAME" ] && NAME=$(basename $PWD)

echo Lambda Function: $NAME

invoke () {
    echo $1
    aws $AWSARG lambda invoke --function-name $NAME $1 \
        `[[ -f Payload.json ]] && echo --payload fileb://Payload.json` \
        --log-type Tail \
        /dev/stdout | (jq -r .LogResult | base64 -d)
    echo invoked
    exit
}

[ "$ARG" = invoke ] && invoke "$2"
ls $(< Lambda.txt) || ls

DIR=${PWD##*/}
cd ..
zip -rFS $DIR/$NAME.zip $(sed "s/^/$DIR\//" $DIR/Lambda.txt || echo $DIR) -x '*/.git/*' -x '*/__pycache__/*' -x '*/.mypy_cache/*'
cd $DIR

if (( `stat --printf="%s" $NAME.zip` < 60000000 )); then
    aws $AWSARG lambda update-function-code --function-name $NAME --zip-file fileb://$NAME.zip | jq
else
    aws $AWSARG s3 cp $NAME.zip s3://$S3/$NAME.zip
    aws $AWSARG lambda update-function-code --function-name $NAME --s3-bucket $S3 --s3-key $NAME.zip | jq
    #aws s3 rm s3://hwangsehyun/$NAME
fi

invoke "$2"