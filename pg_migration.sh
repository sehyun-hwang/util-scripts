$DIR=/home/linuxbrew/.linuxbrew/Cellar/libpq/12.3/bin
$DIR/pg_dump -h ec2-18-216-81-129.us-east-2.compute.amazonaws.com -U postgres -d pnid -F c --no-owner | \
$DIR/pg_restore -h aurora.vpc -U postgres -c -d pnid --no-owner