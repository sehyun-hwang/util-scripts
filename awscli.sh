set -e
cd /volatile/src/awscli

pip install -t awscli -U https://github.com/boto/botocore/archive/v2.zip https://github.com/aws/aws-cli/archive/v2.zip

docker create --name aws amazon/aws-cli
docker cp aws:/usr/local/aws-cli/v2/2.4.0/dist/awscli/data/ac.index awscli/data/