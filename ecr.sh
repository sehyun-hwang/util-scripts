set -e

REPOSITORY=nextlab
[ -z "$NAME" ] && NAME=`basename $PWD`
BUILD="$NAME`[ -z "$TAG" ] || echo ':'`$TAG"
REGION=`aws configure get region`
URL=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com
URI="$URL/$REPOSITORY:`echo $BUILD | sed 's/:/-/g'`"
which podman && FORMAT="--format v2s2"

echo Building $BUILD
docker build . -t $BUILD
echo Tagging $BUILD $URI
docker tag $BUILD $URI


echo Logging into account $ACCOUNT
TOKEN=`jq -r '.auths["'$URL'"].auth' $XDG_RUNTIME_DIR/containers/auth.json` \
&& curl --fail -H "Authorization: Basic $TOKEN" https://$URL/v2/$REPOSITORY/tags/list -o /dev/null \
|| aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $URL


echo Pushing to $URI
export TMPDIR=/volatile/cache/tmp
docker push $FORMAT $URI
docker untag $URI


[ "$1" == "lambda" ] || exit
[ -z "$FUNCTION_NAME" ] && FUNCTION_NAME=$NAME
aws lambda update-function-code --function-name $FUNCTION_NAME --image-uri $URI | jq
aws lambda wait function-updated --function-name $FUNCTION_NAME
NAME=$FUNCTION_NAME bash lambda.sh invoke