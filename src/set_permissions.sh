#!/bin/sh

needed_paths="/var/run/nginx.pid /usr/share/nginx /etc/nginx /var/log/nginx /usr/lib/nginx /var/cache/nginx /srv"

for file in ${needed_paths}; do
  echo "Setting permission for $file"
  chown -R root:nginx $file
  find $file -type f -exec chmod 660 '{}' ';'
  find $file -type d -exec chmod 770 '{}' ';'
done
