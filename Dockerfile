FROM nginx:stable-alpine AS builder

# nginx:alpine contains NGINX_VERSION environment variable, like so:
# ENV NGINX_VERSION 1.15.0
ARG vMODSEC=3

# For latest build deps, see https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile
RUN apk add --no-cache --virtual .build-deps \
    gcc \
    libc-dev \
    make \
    openssl-dev \
    pcre-dev \
    zlib-dev \
    linux-headers \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    perl-dev \
    libedit-dev \
    bash \
    alpine-sdk \
    findutils \
    openssl-dev \
    # for modsecurity
    pcre-dev \
    libxml2-dev \
    luajit-dev \
    git \
    libtool \
    automake \
    autoconf \
    g++ \
    flex-dev \
    bison \
    lmdb-dev \
    wget \
    yajl-dev \
    curl-dev \
    swig


#Build ssdeep
WORKDIR /opt/ssdeep
RUN git clone https://github.com/ssdeep-project/ssdeep.git \
    && cd ssdeep \
    && ./bootstrap && ./configure && make && make install

# Build libmodsecurity
WORKDIR /opt/ModSecurity
RUN echo "Building ModSecurity lib" && \
    git clone --depth 1 -b v${vMODSEC}/master --single-branch https://github.com/SpiderLabs/ModSecurity . && \
    git submodule update --init && \
    ./build.sh && \
    #--with-lmdb --with-lua
    ./configure --with-yajl  --with-lmdb \
    && make && make install && make clean

#WORKDIR /opt/ngx_http_geoip2_module
#RUN echo "Installing geoip2" && git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git .

WORKDIR /opt/brotli
RUN echo "Installing brotli" && \
    git clone --depth 1 https://github.com/google/ngx_brotli.git . && \
    git submodule update --init

WORKDIR /opt/ngx_cache_purge
RUN echo "Installing ngx_cache_purge" && \
    git clone --depth 1 https://github.com/torden/ngx_cache_purge.git .

WORKDIR /opt/
RUN echo "Installing ModSec - Nginx Connector" && \
    git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git && \
    wget "http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" && \
    tar -zxvf nginx-${NGINX_VERSION}.tar.gz

WORKDIR /opt/nginx-${NGINX_VERSION}
RUN echo "Building dynamic modules" && ./configure --with-compat \
    #--add-dynamic-module=../ngx_http_geoip2_module \
    --add-dynamic-module=../ModSecurity-nginx \
    --add-dynamic-module=../brotli \
    --add-dynamic-module=../ngx_cache_purge \
    && make modules \
    && install -s -m750 objs/*.so /usr/lib/nginx/modules/ \
    && make clean

RUN apk del .build-deps

FROM nginx:stable-alpine

ENV ACCESSLOG=/var/log/nginx/access.log \
    BACKEND=http://localhost:80 \
    DNS_SERVER='1.1.1.1 1.0.0.1' \
    ERRORLOG=/var/log/nginx/error.log \
    LOGLEVEL=warn \
    METRICS_ALLOW_FROM='127.0.0.0/24' \
    METRICS_DENY_FROM='all' \
    METRICSLOG=/dev/null \
    MODSEC_AUDIT_LOG_FORMAT=JSON \
    MODSEC_AUDIT_LOG_TYPE=Serial \
    MODSEC_AUDIT_LOG=/dev/stdout \
    MODSEC_AUDIT_STORAGE=/var/log/modsecurity/audit/ \
    MODSEC_DATA_DIR=/tmp/modsecurity/data \
    MODSEC_DEBUG_LOG=/dev/null \
    MODSEC_DEBUG_LOGLEVEL=0 \
    MODSEC_PCRE_MATCH_LIMIT_RECURSION=100000 \
    MODSEC_PCRE_MATCH_LIMIT=100000 \
    MODSEC_REQ_BODY_ACCESS=on \
    MODSEC_REQ_BODY_LIMIT=13107200 \
    MODSEC_REQ_BODY_NOFILES_LIMIT=131072 \
    MODSEC_RESP_BODY_ACCESS=on \
    MODSEC_RESP_BODY_LIMIT=1048576 \
    MODSEC_RULE_ENGINE=on \
    MODSEC_TAG=modsecurity \
    MODSEC_TMP_DIR=/tmp/modsecurity/tmp \
    MODSEC_UPLOAD_DIR=/tmp/modsecurity/upload \
    PORT=80 \
    PROXY_TIMEOUT=60s \
    SERVER_NAME=localhost \
    SSL_PORT=443 \
    TIMEOUT=60s \
    WORKER_CONNECTIONS=1024 \
    LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib \
    SSL_VERIFY=on
#SSL_CERT_KEY=/etc/nginx/ssl/server.key \
#SSL_CERT=/etc/nginx/ssl/server.crt \

# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
RUN apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    && runDeps="$( \
    scanelf --needed --nobanner /tmp/envsubst \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | sort -u \
    | xargs -r apk info --installed \
    | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/

# Add runtime dependencies that should not be removed
RUN apk add --update --no-cache yajl libstdc++ sed tzdata curl lmdb \
    && apk update && apk upgrade --available --no-cache

RUN mkdir /etc/modsecurity.d
COPY --from=builder /usr/lib/nginx/modules/ /usr/lib/nginx/modules/
COPY --from=builder /usr/local/lib/ /usr/local/lib/
COPY --from=builder /usr/local/modsecurity/ /usr/local/modsecurity/
COPY --from=builder /opt/ModSecurity/modsecurity.conf-recommended /etc/modsecurity.d/modsecurity.conf
COPY --from=builder /opt/ModSecurity/unicode.mapping /etc/modsecurity.d/unicode.mapping
COPY src/etc/modsecurity.d/*.conf /etc/modsecurity.d/
COPY src/set_permissions.sh /
COPY nginx/conf.d/*.conf /etc/nginx/conf.d/
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/docker-entrypoint.sh /docker-entrypoint.d/40-modsec-entrypoint.sh

RUN chmod 700 /docker-entrypoint.d/40-modsec-entrypoint.sh /set_permissions.sh

RUN touch /var/run/nginx.pid
RUN /set_permissions.sh && rm /set_permissions.sh

RUN ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
