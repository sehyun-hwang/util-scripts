cd /volatile
sudo dd if=/dev/zero of=swap bs=64M count=32
sudo chmod 600 swap
sudo mkswap swap
sudo swapon -s