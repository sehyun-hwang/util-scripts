set -e
cd /volatile/src/awscli

docker create --name aws amazon/aws-cli
pip3 install -t awscli -U https://github.com/boto/botocore/archive/v2.zip https://github.com/aws/aws-cli/archive/v2.zip
docker cp aws:/usr/local/aws-cli/v2/2.2.41/dist/awscli/data/ac.index awscli/data/