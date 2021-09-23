set -e

AWS="aws"
NAME=Node
ZIP=nodejs.zip
cd /mnt/volatile/Lambda

zip -rFS $ZIP nodejs
VERSION=`$AWS lambda publish-layer-version --layer-name $NAME --zip-file fileb://$ZIP | jq .Version`
echo $VERSION

for x in `$AWS lambda list-functions --output json | jq -r '.Functions[] | select(has("Runtime")) | select( .Runtime | startswith("nodejs")) | .FunctionName'`; do
    echo $x
    $AWS lambda update-function-configuration --function-name $x \
    --layers arn:aws:lambda:$AWS_DEFAULT_REGION:$ACCOUNT:layer:$NAME:$VERSION \
    | jq .FunctionName
done