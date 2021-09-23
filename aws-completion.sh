docker create --name aws amazon/aws-cli
docker cp aws:/usr/local/aws-cli/v2/2.2.7/dist/awscli/data/ac.index /volatile/src/awscli/awscli/data/ac.index
docker rm aws