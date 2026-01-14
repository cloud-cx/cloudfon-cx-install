#!/usr/bin/env bash
set -e

if [ -z $1 ];
then
    echo -e "\t => need parameters <="
    exit -1
fi

export_configure_all() {
    echo ""
    echo -e "\t => export configure file 'docker-compose.yml' <="
	if [ $2 = 'root' ];then
	echo "mariadb user: root"
	cat << FEOF > docker-compose.yml
services:
  # callcenter api
  cx-api:
    image: $1
    container_name: cx-api
    privileged: true
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "9002:8000"
      - "8008:8008"
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
      timeout: 20s
      retries: 10
    depends_on:
      cx-upgrade:
        condition: service_completed_successfully
    networks:
      - cx-network
  cx-upgrade:
    image: $1
    container_name: cx-upgrade
    privileged: true
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      cx-mariadb:
        condition: service_healthy
      cx-elasticsearch:
        condition: service_healthy
      cx-redis:
        condition: service_healthy
      cx-nfs:
        condition: service_healthy
    networks:
      - cx-network
    working_dir: /data
    command: >
      /usr/local/sbin/upgrade
  # kong gateway
  cx-kong:
    image: kong:3.3.0-ubuntu
    privileged: true
    user: kong
    container_name: cx-kong
    environment: 
      KONG_DATABASE: "off"
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_PROXY_LISTEN: "0.0.0.0:80, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
      KONG_ADMIN_LISTEN: "0.0.0.0:8001 reuseport backlog=16384, 0.0.0.0:8444 http2 ssl reuseport backlog=16384"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cx_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cx_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cx_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "80:80"
      - "443:443"
      - "9001:9001"
      - "9006:9006"
      - "8001:8001"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    restart: always
    read_only: true
    volumes:
      - kong_prefix_vol:/var/run/kong
      - kong_tmp_vol:/tmp
      - ./:/opt/kong
      - ./kong-nginx.conf:/var/run/kong/nginx.conf
    security_opt:
      - no-new-privileges
  # mysql database
  cx-mariadb:
    image: mariadb:10.6.7
    container_name: cx-mariadb
    volumes:
      - ./mariadb_data/data:/var/lib/mysql
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./my.cnf:/etc/mysql/my.cnf:ro
    environment:
      MYSQL_DATABASE: \${MARIADB_DATABASE}
      MYSQL_ROOT_PASSWORD: \${MARIADB_PASSWORD}
    healthcheck:
      test: [ "CMD", "mysqladmin" ,"ping", "-h", "localhost","-p\${MARIADB_PASSWORD}"]
      timeout: 20s
      retries: 30
    # if want expose to external,please uncomment this
    ports:
      - "63306:3306"
    restart: always
    networks:
      - cx-network
  cx-redis:
    image: redis
    container_name: cx-redis
    ports:
      - "56379:6379"
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./redis.conf:/etc/redis/redis.conf
    command:
      redis-server /etc/redis/redis.conf
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "redis-cli","ping"]
      interval: 10s
      timeout: 3s
      retries: 5
  # elasticsearch
  cx-elasticsearch:
    image: elasticsearch:8.14.3
    container_name: cx-elasticsearch
    ports:
      - "59200:9200"
      - "59300:9300"
    environment:
      ELASTIC_PASSWORD: \${ES_PASSWORD}
      xpack.security.enabled: true
      discovery.type: single-node
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    volumes:
      - ./es/data:/usr/share/elasticsearch/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "curl", "-f", "-u", "elastic:\${ES_PASSWORD}", "http://localhost:9200"]
      interval: 10s
      timeout: 10s
      retries: 10
  # nfs
  cx-nfs:
    image: gists/nfs-server:2.6.4
    container_name: cx-nfs
    privileged: true
    ports:
      - "52049:2049"
    environment:
      NFS_DIR: "/nfs_share"
      NFS_DOMAIN: "*"
      NFS_OPTION: "fsid=0,rw,sync,no_root_squash,all_squash,anonuid=0,anongid=0,no_subtree_check,insecure"
    volumes:
      - ./nfs:/nfs_share
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "pgrep", "nfsd"]
      interval: 10s
      timeout: 10s
      retries: 10
  # loki
  cx-loki:
    image: grafana/loki:2.9.13
    container_name: cx-loki
    ports:
      - "53100:3100"
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml
      - ./loki_data:/tmp/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: always
    networks:
      - cx-network
    healthcheck:
        test: ["CMD", "wget", "-qO-", "http://localhost:3100/ready"]
        interval: 10s
        timeout: 10s
        retries: 10

networks:
  cx-network:
    name: cx-network
volumes:
  kong_data: {}
  kong_prefix_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
  kong_tmp_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
FEOF
	else
	cat << FEOF > docker-compose.yml
services:
  # callcenter api
  cx-api:
    image: $1
    container_name: cx-api
    privileged: true
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "9002:8000"
      - "8008:8008"
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
      timeout: 20s
      retries: 10
    depends_on:
      cx-upgrade:
        condition: service_completed_successfully
    networks:
      - cx-network
  cx-upgrade:
    image: $1
    container_name: cx-upgrade
    privileged: true
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      cx-mariadb:
        condition: service_healthy
      cx-elasticsearch:
        condition: service_healthy
      cx-redis:
        condition: service_healthy
      cx-nfs:
        condition: service_healthy
    networks:
      - cx-network
    working_dir: /data
    command: >
      /usr/local/sbin/upgrade
  # kong gateway
  cx-kong:
    image: kong:3.3.0-ubuntu
    privileged: true
    user: kong
    container_name: cx-kong
    environment:
      KONG_DATABASE: "off"
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_PROXY_LISTEN: "0.0.0.0:80, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
      KONG_ADMIN_LISTEN: "0.0.0.0:8001 reuseport backlog=16384, 0.0.0.0:8444 http2 ssl reuseport backlog=16384"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cx_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cx_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cx_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "80:80"
      - "443:443"
      - "9001:9001"
      - "9006:9006"
      - "8001:8001"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    restart: always
    read_only: true
    volumes:
      - kong_prefix_vol:/var/run/kong
      - kong_tmp_vol:/tmp
      - ./:/opt/kong
      - ./kong-nginx.conf:/var/run/kong/nginx.conf
    security_opt:
      - no-new-privileges
  # mysql database
  cx-mariadb:
    image: mariadb:10.6.7
    container_name: cx-mariadb
    volumes:
      - ./mariadb_data/data:/var/lib/mysql
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./my.cnf:/etc/mysql/my.cnf:ro
    environment:
      MYSQL_DATABASE: \${MARIADB_DATABASE}
      MARIADB_USER: \${MARIADB_USER}
      MARIADB_PASSWORD: \${MARIADB_PASSWORD}
      MYSQL_ROOT_PASSWORD: \${MARIADB_PASSWORD}
    healthcheck:
      test: [ "CMD", "mysqladmin" ,"ping", "-h", "localhost","-p\${MARIADB_PASSWORD}"]
      timeout: 20s
      retries: 30
    # if want expose to external,please uncomment this
    ports:
      - "63306:3306"
    restart: always
    networks:
      - cx-network
  cx-redis:
    image: redis
    container_name: cx-redis
    ports:
      - "56379:6379"
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./redis.conf:/etc/redis/redis.conf
    command:
      redis-server /etc/redis/redis.conf
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "redis-cli","ping"]
      interval: 1s
      timeout: 3s
      retries: 5
  # elasticsearch
  cx-elasticsearch:
    image: elasticsearch:8.14.3
    container_name: cx-elasticsearch
    ports:
      - "59200:9200"
      - "59300:9300"
    environment:
      ELASTIC_PASSWORD: \${ES_PASSWORD}
      xpack.security.enabled: true
      discovery.type: single-node
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    volumes:
      - ./es/data:/usr/share/elasticsearch/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "curl", "-f", "-u", "elastic:\${ES_PASSWORD}", "http://localhost:9200"]
      interval: 5s
      timeout: 10s
      retries: 10
  # nfs
  cx-nfs:
    image: gists/nfs-server:2.6.4
    container_name: cx-nfs
    privileged: true
    ports:
      - "52049:2049"
    environment:
      NFS_DIR: "/nfs_share"
      NFS_DOMAIN: "*"
      NFS_OPTION: "fsid=0,rw,sync,no_root_squash,all_squash,anonuid=0,anongid=0,no_subtree_check,insecure"
    volumes:
      - ./nfs:/nfs_share
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "pgrep", "nfsd"]
      interval: 10s
      timeout: 10s
      retries: 10
  # loki
  cx-loki:
    image: grafana/loki:2.9.13
    container_name: cx-loki
    ports:
      - "53100:3100"
    volumes:
      - ./loki-config.yaml:/etc/loki/local-config.yaml
      - ./loki_data:/tmp/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: always
    networks:
      - cx-network
    healthcheck:
        test: ["CMD", "wget", "-qO-", "http://localhost:3100/ready"]
        interval: 10s
        timeout: 10s
        retries: 10
networks:
  cx-network:
    name: cx-network
volumes:
  kong_data: {}
  kong_prefix_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
  kong_tmp_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
FEOF

	fi

    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}

export_configure_api() {
    echo ""
    echo -e "\t => export configure file 'docker-compose.yml' <="
    echo ""

    cat << FEOF > docker-compose.yml
services:
  # callcenter api
  cx-api:
    image: $1
    privileged: true
    container_name: cx-api
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    ports:
      - "9002:8000"
      - "8008:8008"
    depends_on:
      cx-upgrade:
        condition: service_completed_successfully
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
      timeout: 20s
      retries: 10
    networks:
      - cx-network
  cx-upgrade:
    image: $1
    container_name: cx-upgrade
    privileged: true
    extra_hosts:
      - host.docker.internal:host-gateway
    volumes:
      - ./:/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - cx-network
    working_dir: /data
    command: >
      /usr/local/sbin/upgrade
  # kong gateway
  cx-kong:
    image: kong:3.3.0-ubuntu
    privileged: true
    user: kong
    container_name: cx-kong
    environment:
      KONG_DATABASE: "off"
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_PROXY_LISTEN: "0.0.0.0:80, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
      KONG_ADMIN_LISTEN: "0.0.0.0:8001 reuseport backlog=16384, 0.0.0.0:8444 http2 ssl reuseport backlog=16384"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cx_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cx_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cx_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "80:80"
      - "443:443"
      - "9001:9001"
      - "9006:9006"
      - "8001:8001"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    restart: always
    read_only: true
    volumes:
      - kong_prefix_vol:/var/run/kong
      - kong_tmp_vol:/tmp
      - ./:/opt/kong
      - ./kong-nginx.conf:/var/run/kong/nginx.conf
    security_opt:
      - no-new-privileges

networks:
  cx-network:
    name: cx-network
volumes:
  kong_data: {}
  kong_prefix_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
  kong_tmp_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
FEOF
    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}

export_configure_mid() {
    echo ""
    echo -e "\t => export configure file 'docker-compose.yml' <="
    echo ""
	if [ $2 = 'root' ];then
	echo "mariadb user: root"
    cat << FEOF > docker-compose.yml
services:
  # mysql database
  cx-mariadb:
    image: mariadb:10.6.7
    container_name: cx-mariadb
    volumes:
      - ./mariadb_data/data:/var/lib/mysql
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./my.cnf:/etc/mysql/my.cnf:ro
    environment:
      MARIADB_DATABASE: \${MARIADB_DATABASE}
      MYSQL_ROOT_PASSWORD: \${MARIADB_PASSWORD}
    healthcheck:
      test: [ "CMD", "mysqladmin" ,"ping", "-h", "localhost","-p\${MARIADB_PASSWORD}"]
      timeout: 20s
      retries: 10
    # if want expose to external,please uncomment this
    ports:
      - "\${MARIADB_PORT}:3306"
    restart: always
    networks:
      - cx-network
  cx-redis:
    image: redis
    container_name: cx-redis
    ports:
      - "\${REDIS_PORT}:6379"
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./redis.conf:/etc/redis/redis.conf
    command:
      redis-server /etc/redis/redis.conf
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "redis-cli","ping"]
      interval: 1s
      timeout: 3s
      retries: 5
  # elasticsearch
  cx-elasticsearch:
    image: elasticsearch:8.14.3
    container_name: cx-elasticsearch
    ports:
      - "59200:9200"
      - "59300:9300"
    environment:
      ELASTIC_PASSWORD: \${ES_PASSWORD}
      xpack.security.enabled: true
      discovery.type: single-node
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    volumes:
      - ./es/data:/usr/share/elasticsearch/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "curl", "-f", "-u", "elastic:\${ES_PASSWORD}", "http://localhost:9200"]
      interval: 5s
      timeout: 10s
      retries: 10
  # nfs
  cx-nfs:
    image: gists/nfs-server:2.6.4
    container_name: cx-nfs
    privileged: true
    ports:
      - "52049:2049"
    environment:
      NFS_DIR: "/nfs_share"
      NFS_DOMAIN: "*"
      NFS_OPTION: "fsid=0,rw,sync,no_root_squash,all_squash,anonuid=0,anongid=0,no_subtree_check,insecure"
    volumes:
      - ./nfs:/nfs_share
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "pgrep", "nfsd"]
      interval: 10s
      timeout: 10s
      retries: 10

networks:
  cx-network:
    name: cx-network
volumes:
  kong_data: {}
  kong_prefix_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
  kong_tmp_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
FEOF
	else
cat << FEOF > docker-compose.yml
services:
  # mysql database
  cx-mariadb:
    image: mariadb:10.6.7
    container_name: cx-mariadb
    volumes:
      - ./mariadb_data/data:/var/lib/mysql
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./my.cnf:/etc/mysql/my.cnf:ro
    environment:
      MARIADB_DATABASE: \${MARIADB_DATABASE}
      MARIADB_USER: \${MARIADB_USER}
      MARIADB_PASSWORD: \${MARIADB_PASSWORD}
      MYSQL_ROOT_PASSWORD: \${MARIADB_PASSWORD}
    healthcheck:
      test: [ "CMD", "mysqladmin" ,"ping", "-h", "localhost","-p\${MARIADB_PASSWORD}"]
      timeout: 20s
      retries: 10
    # if want expose to external,please uncomment this
    ports:
      - "\${MARIADB_PORT}:3306"
    restart: always
    networks:
      - cx-network
  cx-redis:
    image: redis
    container_name: cx-redis
    ports:
      - "\${REDIS_PORT}:6379"
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
      - ./redis.conf:/etc/redis/redis.conf
    command:
      redis-server /etc/redis/redis.conf
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "redis-cli","ping"]
      interval: 1s
      timeout: 3s
      retries: 5
  # elasticsearch
  cx-elasticsearch:
    image: elasticsearch:8.14.3
    container_name: cx-elasticsearch
    ports:
      - "59200:9200"
      - "59300:9300"
    environment:
      ELASTIC_PASSWORD: \${ES_PASSWORD}
      xpack.security.enabled: true
      discovery.type: single-node
      ES_JAVA_OPTS: -Xms512m -Xmx512m
    volumes:
      - ./es/data:/usr/share/elasticsearch/data
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "curl", "-f", "-u", "elastic:\${ES_PASSWORD}", "http://localhost:9200"]
      interval: 5s
      timeout: 10s
      retries: 10
  # nfs
  cx-nfs:
    image: gists/nfs-server:2.6.4
    container_name: cx-nfs
    privileged: true
    ports:
      - "52049:2049"
    environment:
      NFS_DIR: "/nfs_share"
      NFS_DOMAIN: "*"
      NFS_OPTION: "fsid=0,rw,sync,no_root_squash,all_squash,anonuid=0,anongid=0,no_subtree_check,insecure"
    volumes:
      - ./nfs:/nfs_share
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    restart: always
    networks:
      - cx-network
    healthcheck:
      test: ["CMD", "pgrep", "nfsd"]
      interval: 10s
      timeout: 10s
      retries: 10

networks:
  cx-network:
    name: cx-network
volumes:
  kong_data: {}
  kong_prefix_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
  kong_tmp_vol:
    driver_opts:
     type: tmpfs
     device: tmpfs
FEOF

	fi
    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}


export_nginx_conf() {
    echo ""
    echo -e "\t => export nginx_conf file 'kong-nginx.conf' <="
    echo ""

    cat << FEOF > kong-nginx.conf
pid pids/nginx.pid;
error_log /dev/stderr notice;

# injected nginx_main_* directives
daemon off;
user kong kong;
worker_processes auto;
worker_rlimit_nofile 16384;

lmdb_environment_path dbless.lmdb;
lmdb_map_size         128m;

events {
    # injected nginx_events_* directives
    multi_accept on;
    worker_connections 16384;
}

http {
     include 'nginx-kong.conf';
     include '/usr/local/openresty/nginx/conf/mime.types';

     gzip on;
     gzip_min_length 1k;
     gzip_comp_level 6;
     gzip_types text/plain application/javascript application/x-javascript text/css application/xml text/javascript application/x-httpd-php;
     gzip_vary on;

     server {
             charset UTF-8;
             server_name web;
             listen 0.0.0.0:9000 reuseport backlog=16384;

	     add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' https: data: blob: wss:; base-uri 'self'; script-src 'self' https: 'unsafe-inline' 'unsafe-eval' data: blob:";
             add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
             add_header X-Frame-Options "ALLOW-FROM *";
             add_header X-Content-Type-Options "nosniff";
             add_header Referrer-Policy no-referrer;
             add_header Permissions-Policy "geolocation=()";

             error_page 400 404 405 408 411 412 413 414 417 494 /kong_error_handler;
             error_page 500 502 503 504                     /kong_error_handler;
             access_log /dev/stdout;


             location /chat {
                     root /opt/kong/webapp/static/;
                     index index.htm index.html;
             }

	     location /chatjs {
		     root /opt/kong/webapp/static/;
		     index index.htm index.html;
	     }

	      location /chatpreview {
       		     root /opt/kong/webapp/static/;
		     index index.htm index.html;
	      }

             location / {
                     root /opt/kong/webapp/static/files;
                     index index.htm index.html;
             }
     }

}
FEOF
    echo ""
    echo -e "\t => configure nginx_conf file done <="
    echo ""
    echo ""
}

export_env() {
    echo ""
    echo -e "\t => export export_env file '.env' <="
    echo ""
    physicalNic=$(ip addr | grep -v br- | grep -v veth | grep 'state UP' | awk '/^[0-9]/ { print $2 }' | sed 's/://'| cut -d '@' -f 1)

    if [ -z "$physicalNic" ]; then
        echo "No physical network interfaces found."
        exit 1
    fi

    HOST_IP=""

    for nic in $physicalNic; do
        ips=$(ip addr show dev $nic | grep "inet " | awk '{print $2}' | cut -d '/' -f 1)
        for ip in $ips;do
          HOST_IP="$HOST_IP,$ip"
        done
    done

    HOST_IP=$(echo "$HOST_IP" | cut -c 2-)

    echo "HOST_IP: $HOST_IP"
    CX_CLUSTER_ENABLED=false
    if [ -f ".env"  ];then
      CX_CLUSTER_ENABLED=$(sed '/CX_CLUSTER_ENABLED/!d;s/.*=//'  .env)
      if [ -z "${CX_CLUSTER_ENABLED}" ]; then
        CX_CLUSTER_ENABLED=false
      fi
    fi
    cat << FEOF > .env
ENV=dev
MARIADB_URL=$1
MARIADB_USER=$2
MARIADB_PASSWORD=$3
MARIADB_PORT=$4
MARIADB_DATABASE=$5
REDIS_URL=$6
REDIS_PASSWORD=$7
REDIS_PORT=$8
MIDDLEWARE_HOST=${9}
JVM_MEM=${10}
HOST_IP=${HOST_IP}
ES_URL=${13}
ES_PORT=${11}
ES_PASSWORD=${12}
LOKI_URL=${14}
LOKI_ENABLED=false
LOKI_APPHOST=cx
CX_CLUSTER_ENABLED=${CX_CLUSTER_ENABLED}
FEOF
    echo ""
    echo -e "\t => configure export_env file done <="
    echo ""
    echo ""
}

export_mariadb_conf() {
    echo ""
    echo -e "\t => export export_mariadb_conf file '.env' <="
    echo ""
    cat << FEOF >  my.cnf
[client-server]
# Port or socket location where to connect
# port = 3306

[mysqld]
socket = /run/mysqld/mysqld.sock
#connect_timeout =60
wait_timeout =300000
max_connections =500
max_allowed_packet =128M
max_connect_errors =350

#limits
tmp_table_size =64M
max_heap_table_size =64M
table_cache =512M

#innodb
innodb_buffer_pool_size =${1}M
#innodb_log_file_size =128M
innodb_log_buffer_size =128M
innodb_file_per_table=1
innodb_strict_mode=OFF

thread_cache_size=8
query_cache_size=128M

join_buffer_size=128M
read_buffer_size=128M
read_rnd_buffer_size=128M
key_buffer_size=10M

slow_query_log=1
slow_query_log_file=mariadb-slow.log

skip-name-resolve

# Import all .cnf files from configuration directory
!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mariadb.conf.d/	
FEOF
    echo ""
    echo -e "\t => configure export_mariadb_conf file done <="
    echo ""
    echo ""
}


export_redis_conf() {
    echo ""
    echo -e "\t => export export_redis_conf file '.env' <="
    echo ""
    cat << FEOF >  redis.conf
#bind 127.0.0.1  
 
port 6379 
 
requirepass $1
  
 
daemonize no
 
appendonly yes
 
timeout 60
maxclients 10000
tcp-keepalive 300
 
save 900 1
save 300 10
save 60 10000
 
tcp-backlog 511
 
databases 16
 
appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

slowlog-log-slower-than 10000
slowlog-max-len 128

syslog-enabled yes  

loglevel notice
  
logfile stdout

FEOF
    echo ""
    echo -e "\t => configure export_redis_conf file done <="
    echo ""
    echo ""
}

export_loki_conf() {
    echo ""
    echo -e "\t => export export_loki_conf file '.env' <="
    echo ""
    cat << FEOF >  loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100

common:
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  path_prefix: /tmp/loki
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /tmp/loki/index
    cache_location: /tmp/loki/tsdb-cache

limits_config:
  allow_structured_metadata: true
  reject_old_samples: true
  reject_old_samples_max_age: 720h

compactor:
  working_directory: /tmp/loki/compactor

table_manager:
  retention_deletes_enabled: false
  retention_period: 0s

FEOF
    echo ""
    echo -e "\t => configure export_loki_conf file done <="
    echo ""
    echo ""
}

create() {
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift
	
	options=$(getopt -o i:t:m:r:w:u:b:s:d:e:f:ph --long image:,install_type:,mariadb_password:,redis_password:,middleware_ip:,mariadb_user:,mariadb_port:,redis_port:,mariadb_database:,es_port:,es_password: -- "$@")
	eval set -- "$options"
	 
	while true; do
	  case $1 in 
		-i | --image) shift; image=$1 ; shift ;;
		-t | --install_type) shift; install_type=$1 ; shift ;;
		-m | --mariadb_password) shift; mariadb_password=$1 ; shift ;;
		-r | --redis_password) shift; redis_password=$1 ; shift ;;
		-w | --middleware_ip) shift; middleware_ip=$1 ; shift ;;
		-u | --mariadb_user) shift; mariadb_user=$1 ; shift ;;
		-b | --mariadb_port) shift; mariadb_port=$1 ; shift ;;
		-d | --mariadb_database) shift; mariadb_database=$1 ; shift ;;
		-s | --redis_port) shift; redis_port=$1 ; shift ;;
    -e | --es_port) shift; es_port=$1 ; shift ;;
    -f | --es_password) shift; es_password=$1 ; shift ;;
		-p | --print) print=true; shift ;;
		-h | --help) help=true; shift ;;
		--) shift ; break ;;
		*) echo "Invalid option: $1" exit 1 ;;
	  esac
	done
	
	
	if [ "$help" = true ]; then
		echo "Command run Options:";	
		echo "	-i,--image				the image to install cx-api server";
		echo "	-t,--install_type			install type:api) install cx-api only;mid) install middleware only,all) install cx-api and middleware. defaule all";
		echo "	-m,--mariadb_password			install_type=api) remote middleware mariadb password;install_type=mid/all) local middleware mariadb password,Only the first time it takes effect; default Randomly generated";
		echo "	-r,--redis_password			install_type=api) remote redis mariadb password;install_type=mid/all) local middleware redis password; default Randomly generated";
		echo "	-w,--middleware_ip			install_type=api) remote middleware ip;install_type=mid/all) not effect";
		echo "	-u,--mariadb_user			install_type=api) remote mariadb user;install_type=mid) local mariadb user;install_type=all) not effect; default root";
		echo "	-b,--mariadb_port			install_type=api) remote mariadb port;install_type=mid) local mariadb External mapping port; install_type=all)not effect; default 63306";
		echo "	-d,--mariadb_database			install_type=api) remote mariadb database name;install_type=mid) local mariadb database name; install_type=all)not effect; default cc";
		echo "	-s,--redis_port				install_type=api) remote redis port;install_type=mid) local redis External mapping port ; install_type=all)not effect; default 56379";
		echo "	-e,--es_port				install_type=api) remote elasticsearch port;install_type=mid/all) local elasticsearch External mapping port ; default 59200";
		echo "	-f,--es_password				install_type=api) remote elasticsearch password;install_type=mid/all) local middleware elasticsearch password ; default Randomly generated";
		return
	fi
	 
	ai_agent_image=""
	if [ -z "$install_type" ]; then
		install_type='all'
	fi
	
	if [ "$install_type" != "mid" ];then
		if [ -z "$image" ]; then
			echo "Error: image is required"
			exit 1
		fi
    ai_agent_image=$(echo "$image" | rev | cut -d':' -f2- | rev)"_ai:"$(echo "$image" | rev | cut -d':' -f1 | rev)
    echo "ai_agent_image: $ai_agent_image"
	fi	
	
	FILE=".env"
	
	if [ $install_type = 'api' ];then
		if [ -z "$mariadb_password" ]; then
			if [ -f "$FILE"  ];then
				echo -e "\t => mariadb_password already initialize  <="
				mariadb_password=$(sed '/MARIADB_PASSWORD/!d;s/.*=//'  .env)	
			fi
		
			if [ -z "$mariadb_password" ]; then
				echo "need mariadb_password parameters"
				exit -1
			fi	
		fi
		
		if [ -z "$redis_password" ]; then
			if [ -f "$FILE"  ];then
				echo -e "\t => redis_password already initialize  <="
				redis_password=$(sed '/REDIS_PASSWORD/!d;s/.*=//'  .env)
			fi
			
			if [ -z "$redis_password" ]; then
				echo "need redis_password parameters"
				exit -1
			fi	
		fi
		
		if [ -z "$middleware_ip" ]; then
			if [ -f "$FILE"  ];then
				echo -e "\t => middleware_ip already initialize  <="
				middleware_ip=$(sed '/MIDDLEWARE_HOST/!d;s/.*=//'  .env)
			fi
			
			if [ -z "$middleware_ip" ]; then
				echo "need middleware_ip parameters"
				exit -1
			fi
		fi

		if [ -z "$es_password" ]; then
      if [ -f "$FILE"  ];then
        echo -e "\t => es_password already initialize  <="
        es_password=$(sed '/ES_PASSWORD/!d;s/.*=//'  .env)
      fi

      if [ -z "$es_password" ]; then
        echo "need es_password parameters"
        exit -1
      fi
    fi
	fi	

	if [ $install_type != 'api' ];then
		if [ -f "$FILE"  ];then
			echo -e "\t => mariadb_password already initialize  <="
			mariadb_password=$(sed '/MARIADB_PASSWORD/!d;s/.*=//'  .env)	
			mariadb_user=$(sed '/MARIADB_USER/!d;s/.*=//'  .env)	
			mariadb_database=$(sed '/MARIADB_DATABASE/!d;s/.*=//'  .env)	
			
			if [ -z "$redis_password" ]; then
			  redis_password=$(sed '/REDIS_PASSWORD/!d;s/.*=//'  .env)
			fi
			if [ -z "$es_password" ]; then
        es_password=$(sed '/ES_PASSWORD/!d;s/.*=//'  .env)
      fi
		fi
		
		if [ -z "$mariadb_password" ]; then
		  echo "no mariadb_password parameters"
		  mariadb_password=$(date +%s%N | md5sum | cut -c 1-13)
		  echo "auto init mariadb_password as:${mariadb_password}"
		fi	
			
		if [ -z "$redis_password" ]; then
		  echo "no redis_password parameters"
		  redis_password=$(date +%s%N | md5sum | cut -c 1-13)
		  echo "auto init redis_password as:${redis_password}"
		fi

		if [ -z "$es_password" ]; then
      echo "no es_password parameters"
      es_password=$(date +%s%N | md5sum | cut -c 1-13)
      echo "auto init es_password as:${es_password}"
    fi
	fi
		
	if [ -z "$mariadb_user" ]; then
		mariadb_user='root'
	fi	
		
	if [ -z "$mariadb_port" ]; then
		mariadb_port=63306
	fi
	
	if [ -z "$redis_port" ]; then
		redis_port=56379
	fi

	if [ -z "$mariadb_database" ]; then
		mariadb_database='cc'
	fi
	if [ -z "$es_port" ]; then
    es_port=59200
  fi

	
	if [ "$print" = true ]; then
		echo "image: $image; ai_image: $ai_agent_image;install_type: $install_type; mariadb_password: $mariadb_password;redis_password: $redis_password;middleware_ip: $middleware_ip;mariadb_user: $mariadb_user;es_port:$es_port;es_password:$es_password";
	fi

    
    echo ""
    echo "==> try to create cloud-cx service <=="
    echo ""
    #mariadb_password=$(date +%s%N | md5sum | cut -c 1-13)
	totalMem=$(free -m|awk '/Mem/{print $(NF-5)-0}')
	

	case $install_type in
		api)
			#MARIADB_URL=$1
			#mariadb_user=$2
			#MARIADB_PASSWORD$3
			#MARIADB_PORT=$4
			#MARIADB_DATABASE=$5
			#REDIS_URL=$6
			#REDIS_PASSWORD=$7
			#REDIS_PORT=$8
			jvm_mem=$(awk -v x=${totalMem} -v y=0.6 'BEGIN{printf "%.0f",x*y}')
			export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port $middleware_ip $jvm_mem $es_port $es_password $middleware_ip
			
			echo "export_configure_api"
			export_configure_api $image $ai_agent_image
			export_nginx_conf
			mkdir -p nfs
			;;

		mid)
			echo "export_configure_mid"
			export_configure_mid $image $mariadb_user
			configMem=$(awk -v x=${totalMem} -v y=0.4 'BEGIN{printf "%.0f",x*y}')
			echo "totalMem:${totalMem}  configMem:${configMem}"
			export_mariadb_conf $configMem
			
			middleware_ip='127.0.0.1'
			loki_url='http://cx-loki:3100'
			export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port $middleware_ip $configMem $es_port $es_password $middleware_ip
			export_redis_conf $redis_password
      export_loki_conf

			# chmod es data
      mkdir -p es/data
      chmod 777 -R es
      mkdir -p loki_data
      chmod 777 -R loki_data
      mkdir -p nfs/fileSaved
			;;
		*)
			echo "export_configure_all"
			export_configure_all $image $mariadb_user $ai_agent_image
			configMem=$(awk -v x=${totalMem} -v y=0.2 'BEGIN{printf "%.0f",x*y}')
			jvm_mem=$(awk -v x=${totalMem} -v y=0.3 'BEGIN{printf "%.0f",x*y}')
			echo "totalMem:${totalMem}  configMem:${configMem} jvm_mem:${jvm_mem}"
			export_mariadb_conf $configMem
			
			mariadb_url='cx-mariadb'
			redis_url='cx-redis'
			mariadb_port=3306
			redis_port=6379
			es_port=9200
			middleware_ip='127.0.0.1'
      es_url='cx-elasticsearch'
      loki_url='http://cx-loki:3100'
      echo "$mariadb_url $mariadb_user $mariadb_password $mariadb_port $mariadb_database $redis_url $redis_password $redis_port $middleware_ip  $jvm_mem $es_port $es_password $es_url $loki_url"

			export_env $mariadb_url $mariadb_user $mariadb_password $mariadb_port $mariadb_database $redis_url $redis_password $redis_port $middleware_ip  $jvm_mem $es_port $es_password $es_url $loki_url
			export_redis_conf $redis_password
			export_nginx_conf
			export_loki_conf

			# chmod es data
      mkdir -p es/data
      chmod 777 -R es
      mkdir -p loki_data
      chmod 777 -R loki_data
      mkdir -p nfs/fileSaved
			;;
		esac

    # run cloud-cx service
    docker compose up -d

    echo ""
    echo -e "\t done"
    echo ""
}


status() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo ""
        echo "status all services"
        echo ""
        docker compose ls -a
        docker compose ps -a
    else
        echo ""
        echo "status service $service_name"
        echo ""
        docker compose ps $service_name
    fi
}

restart() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

	# check parameters is exist
    if [ -z "$service_name" ]; then
        echo ""
        echo "restart all services"
        echo ""
        docker compose restart
        exit 0
    else
        echo ""
        echo "restart service $service_name"
        echo ""
        docker compose restart -t 100 $service_name
    fi
}

start() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

    # check parameters is exist
    if [ -z "$service_name" ]; then
        echo ""
        echo "start all services"
        echo ""
        docker compose start
    else
        echo ""
        echo "start service $service_name"
        echo ""
        docker compose start $service_name
    fi
}

stop() {
    # remove command firstly
    shift

    service_name=

    # parse parameters
    while getopts s: option
    do
        case "${option}" in
            s)
                service_name=${OPTARG}
                ;;
        esac
    done

	# check parameters is exist
    if [ -z "$service_name" ]; then
        echo ""
        echo "stop all services"
        echo ""
        docker compose stop
    else
        echo ""
        echo "stop service $service_name"
        echo ""
        docker compose stop  -t 100 $service_name
    fi
}

upgrade() {
   shift
   local image=$1
   if [ -z "$image" ]; then
      echo "Error: Image name is required"
      echo "Usage: $0 upgrade <image>"
      exit 1
   fi
   echo "Upgrading service with image: $image"
   docker run --rm --network cx-network -v $PWD:/data "$image" /usr/local/sbin/upgrade
}

rm() {
    # remove command firstly
    shift

    # remove_data=false

    # # parse parameters
    # while getopts f option
    # do
    #     case "${option}" in
    #         f)
    #             remove_data=true
    #             ;;
    #     esac
    # done

    docker compose down
}

case $1 in
run)
    create $@
    ;;

restart)
    restart $@
    ;;

status)
    status $@
    ;;

stop)
    stop $@
    ;;

upgrade)
    upgrade $@
    ;;

start)
    start $@
    ;;

-h)
    echo "Common Commands:";	
	echo "	run			Create and run a new container from an image";	  
	echo "	start		Start one or more stopped containers";	 
	echo "	stop		Stop one or more running containers";	 
	echo "	restart		Restart one or more containers";	 
	echo "	status		Display a live stream of container(s) resource usage statistics";
	echo "	rm			Remove one or more containers";
    ;;

--help)
    echo "Common Commands:";	
	echo "	run			Create and run a new container from an image";	  
	echo "	start		Start one or more stopped containers";	 
	echo "	stop		Stop one or more running containers";	 
	echo "	restart		Restart one or more containers";	 
	echo "	status		Display a live stream of container(s) resource usage statistics";
	echo "	rm			Remove one or more containers";
    ;;
	
rm)
    rm $@
    ;;	
		

*)
    echo -e "\t error command"
    ;;
esac
