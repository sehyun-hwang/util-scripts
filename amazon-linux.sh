sudo amazon-linux-extras install epel -y
sudo yum install fish

aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin 969305546698.dkr.ecr.ap-northeast-2.amazonaws.com
docker run -it --rm --name layout-parser --restart unless-stopped --gpus all 969305546698.dkr.ecr.ap-northeast-2.amazonaws.com/nextlab:layout-parser-cu111