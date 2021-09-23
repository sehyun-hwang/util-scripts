set -e

[ -z "$NAME" ] && NAME=`basename $PWD`
BUILD="$NAME`[ -z "$TAG" ] || echo ':'`$TAG"
PUSH="nextlab:$NAME`[ -z "$TAG" ] || echo -`$TAG"
URL=$ACCOUNT.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
URI=$URL/$PUSH
which podman && FORMAT="--format v2s2"

echo Building $BUILD
docker build . -t $BUILD

echo Tagging $BUILD $URI
docker tag $BUILD $URI


echo Logging into account $ACCOUNT
TOKEN=`jq -r '.auths["'$URL'"].auth' $XDG_RUNTIME_DIR/containers/auth.json` curl --fail --header "Authorization: Basic $TOKEN" https://$URL/v2/ \
|| aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $URL

echo Pushing to $URI
docker push $FORMAT $URI
docker untag $URI


[ "$1" == "lambda" ] || exit
[ -z "$FUNCTION_NAME" ] && FUNCTION_NAME=$NAME
aws lambda update-function-code --function-name $FUNCTION_NAME --image-uri $URI | jq
aws lambda wait function-updated --function-name $FUNCTION_NAME
NAME=$FUNCTION_NAME bash lambda.sh invoke