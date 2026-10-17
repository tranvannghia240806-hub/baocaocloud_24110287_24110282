#!/bin/bash
# User data của Launch Template HA-Web-LT (Amazon Linux 2023, t3.micro)
# Cai Apache, hien thi Instance ID va AZ (lay tu IMDSv2) de quan sat can bang tai.
dnf install -y httpd
systemctl enable --now httpd
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
echo "<h1>HA Web</h1><p>Instance: $IID</p><p>AZ: $AZ</p>" \
  > /var/www/html/index.html

# Endpoint tao tai CPU de thu scale-out (moi request ~1 giay CPU)
mkdir -p /var/www/cgi-bin
printf '#!/bin/bash\necho "Content-Type: text/plain"\necho ""\n' \
  > /var/www/cgi-bin/load.sh
printf 'end=$((SECONDS+1))\nwhile [ $SECONDS -lt $end ]; do :; done\necho ok\n' \
  >> /var/www/cgi-bin/load.sh
chmod +x /var/www/cgi-bin/load.sh
