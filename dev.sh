docker run -it --rm --pod nginx-pod --name dev \
-w /mnt -v node_modules:/mnt/node_modules -v $PWD:/mnt \
-v ~/.cache/yarn/v6:/usr/local/share/.cache/yarn/v6 \
--security-opt label=disable node:alpine sh