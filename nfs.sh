#https://vitux.com/install-nfs-server-and-client-on-ubuntu/

echo "/ 192.168.0.77(ro,subtree_check)" | sudo tee /etc/exports
sudo exportfs -a

sudo apt install nfs-kernel-server
sudo systemctl restart nfs-kernel-server
sudo systemctl status nfs-kernel-server

sudo ufw allow from 192.168.0.77 to any port nfs
sudo ufw status

docker run -d --name server2 -v /volume1/Mount/kbdlab-server2:/src -v /volume2/Backup/server2-2020:/dsc alpine cp -rvu /src /dsc

#docker run \
#  -v /Volumes/dev:/mnt  \
#  -e NFS_EXPORT_0='/mnt *(ro,subtree_check)' \
#  --privileged --cap-add SYS_ADMIN  \
#  -p 2049:2049 -p 2049:2049/udp \
#  erichough/nfs-server 