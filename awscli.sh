set -e
cd /volatile/src/awscli

#pip install -t . -U https://github.com/boto/botocore/archive/v2.zip https://github.com/aws/aws-cli/archive/v2.zip

[[ `python -m awscli --version` =~ aws-cli/([0-9.]+) ]] && VERSION=${BASH_REMATCH[1]}
echo $VERSION

docker create --name aws amazon/aws-cli:$VERSION
docker cp aws:/usr/local/aws-cli/v2/$VERSION/dist/awscli/data/ac.index awscli/data/