#!/usr/bin/with-contenv bash
. "/usr/local/bin/logger"
program_name="nginx-config"

echo "Configuring nginx settings..." | info "[${program_name}] "
sed -i "s/FASTCGI_BUFFERS_CONFIGURATION_STRING/${FASTCGI_BUFFERS_CONFIGURATION_STRING}/g" /etc/nginx/nginx.conf
