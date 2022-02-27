sudo growpart /dev/nvme1n1 1
sudo xfs_growfs -d /dev/nvme1n1
sudo /sbin/resize2fs /dev/nvme1n1
df