#!/bin/bash -e

export DNS_SERVER=${DNS_SERVER:-$(cat /etc/resolv.conf |grep -i '^nameserver'|head -n1|cut -d ' ' -f2)}

ENV_VARIABLES=$(awk 'BEGIN{for(v in ENVIRON) print "$"v}')

FILES=(
    /etc/modsecurity.d/modsecurity-override.conf
    /etc/nginx/nginx.conf
    /etc/nginx/sites/default.conf
)

for FILE in ${FILES[*]}; do
    if [ -f $FILE ]; then
        envsubst "$ENV_VARIABLES" <$FILE | sponge $FILE
    fi
done

exec "$@"
