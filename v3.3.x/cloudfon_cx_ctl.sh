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
    echo "mariadb user: $2"
	if [ $2 != 'root' ];then
	cat << FEOF > docker-compose.yml
version: '3.9'
services:
  # callcenter api
  cx-api:
    image: $1
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
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "https://localhost:8000/time"]
      timeout: 20s
      retries: 10
    depends_on:
      cx-mariadb:
        condition: service_healthy
      cx-redis:
        condition: service_healthy
    networks:
      - cx-network
    build:
      context: ./cx-api
      dockerfile: ./Dockerfile
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
      KONG_PROXY_LISTEN: "0.0.0.0:9001 ssl, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cc_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cc_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cc_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "9001:9001"
      - "443:443"
      - "9006:9006"
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
version: '3.9'
services:
  # callcenter api
  cx-api:
    image: $1
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
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "https://localhost:8000/time"]
      timeout: 20s
      retries: 10
    depends_on:
      cx-mariadb:
        condition: service_healthy
      cx-redis:
        condition: service_healthy
    networks:
      - cx-network
    build:
      context: ./cx-api
      dockerfile: ./Dockerfile
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
      KONG_PROXY_LISTEN: "0.0.0.0:9001 ssl, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cc_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cc_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cc_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "9001:9001"
      - "443:443"
      - "9006:9006"
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
      interval: 1s
      timeout: 3s
      retries: 5

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
version: '3.9'
services:
  # callcenter api
  cx-api:
    image: $1
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
    restart: always
    healthcheck:
      test: [ "CMD", "curl" ,"--fail","-k", "https://localhost:8000/time"]
      timeout: 20s
      retries: 10
    networks:
      - cx-network
    build:
      context: ./cx-api
      dockerfile: ./Dockerfile
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
      KONG_PROXY_LISTEN: "0.0.0.0:9001 ssl, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cc_api/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cc_api/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/cc_api/kong.yaml"
      KONG_UPSTREAM_KEEPALIVE_IDLE_TIMEOUT: 600
    networks:
      - cx-network
    depends_on:
      cx-api:
        condition: service_healthy
    ports:
      - "9001:9001"
      - "443:443"
      - "9006:9006"
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
	if [ $2 != 'root' ];then
    cat << FEOF > docker-compose.yml
version: '3.9'
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
version: '3.9'
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
			 
			 add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' https: data:; base-uri 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'";
			 
             add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";
             add_header X-Frame-Options "ALLOW-FROM *";
             add_header X-Content-Type-Options "nosniff";
             add_header Referrer-Policy no-referrer;
             add_header Permissions-Policy "geolocation=()";
             
             error_page 400 404 405 408 411 412 413 414 417 494 /kong_error_handler;
             error_page 500 502 503 504                     /kong_error_handler;
             access_log /dev/stdout;
              

             location /chat {
                     root /opt/kong/static/;
                     index index.htm index.html;
             }

	     location /chatjs {
		     root /opt/kong/static/;
		     index index.htm index.html;
	     }

	      location /chatpreview {
       		     root /opt/kong/static/;
		     index index.htm index.html;
	      }

             location / {
                     root /opt/kong/static/files;
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
	
    cat << FEOF > .env
MARIADB_URL=$1
MARIADB_USER=$2
MARIADB_PASSWORD=$3
MARIADB_PORT=$4
MARIADB_DATABASE=$5
REDIS_URL=$6
REDIS_PASSWORD=$7
REDIS_PORT=$8

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
max_connections =350
max_allowed_packet =128M
max_connect_errors =350

#limits
tmp_table_size =64M
max_heap_table_size =64M
table_cache =512M

#innodb
innodb_buffer_pool_size =1G
#innodb_log_file_size =128M
innodb_log_buffer_size =32M
innodb_file_per_table=1

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

# Redis服务器配置 
 
# 绑定IP地址
#解除本地限制 注释bind 127.0.0.1  
#bind 127.0.0.1  
 
# 服务器端口号  
port 6379 
 
#配置密码，不要可以删掉
requirepass $1
  
 
#这个配置不要会和docker -d 命令 冲突
# 服务器运行模式，Redis以守护进程方式运行,默认为no，改为yes意为以守护进程方式启动，可后台运行，除非kill进程，改为yes会使配置文件方式启动redis失败，如果后面redis启动失败，就将这个注释掉
daemonize no
 
#当Redis以守护进程方式运行时，Redis默认会把pid写入/var/run/redis.pid文件，可以通过pidfile指定(自定义)
#pidfile /data/dockerData/redis/run/redis6379.pid  
 
#默认为no，redis持久化，可以改为yes
appendonly yes
 
 
#当客户端闲置多长时间后关闭连接，如果指定为0，表示关闭该功能
timeout 60
# 服务器系统默认配置参数影响 Redis 的应用
maxclients 10000
tcp-keepalive 300
 
#指定在多长时间内，有多少次更新操作，就将数据同步到数据文件，可以多个条件配合（分别表示900秒（15分钟）内有1个更改，300秒（5分钟）内有10个更改以及60秒内有10000个更改）
save 900 1
save 300 10
save 60 10000
 
# 按需求调整 Redis 线程数
tcp-backlog 511
 
 
# 设置数据库数量，这里设置为16个数据库  
databases 16
 
 
# 启用 AOF, AOF常规配置
appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
 
 
# 慢查询阈值
slowlog-log-slower-than 10000
slowlog-max-len 128
 
 
# 是否记录系统日志，默认为yes  
syslog-enabled yes  
 
#指定日志记录级别，Redis总共支持四个级别：debug、verbose、notice、warning，默认为verbose
loglevel notice
  
# 日志输出文件，默认为stdout，也可以指定文件路径  
logfile stdout
 
# 日志文件
#logfile /var/log/redis/redis-server.log
 

FEOF
    echo ""
    echo -e "\t => configure export_redis_conf file done <="
    echo ""
    echo ""
}

create() {
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift
	
	# 解析命令行参数
	options=$(getopt -o i:t:m:r:w:u:b:s:d:ph --long image:,install_type:,mariadb_password:,redis_password:,middleware_ip:,mariadb_user:,mariadb_port:,redis_port:,mariadb_database: -- "$@")
	eval set -- "$options"
	 
	# 提取选项和参数
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
		return
	fi
	 
	# 检查变量
	if [ -z "$install_type" ]; then
		install_type='all'
	fi
	
	if [ "$install_type" != "mid" ];then
		if [ -z "$image" ]; then
			echo "Error: image is required"
			exit 1
		fi
	fi	
	
	if [ $install_type = 'api' ];then
		if [ -z "$mariadb_password" ]; then
		  echo "need mariadb_password parameters"
		  exit -1
		fi
		
		if [ -z "$redis_password" ]; then
		  echo "need redis_password parameters"
		  exit -1
		fi
		
		if [ -z "$middleware_ip" ]; then
		  echo "need middleware_ip parameters"
		  exit -1
		fi
	fi	

	if [ $install_type != 'api' ];then
		FILE=".env"
		if [ -f "$FILE"  ];then
			echo -e "\t => mariadb_password already initialize  <="
			mariadb_password=$(sed '/MARIADB_PASSWORD/!d;s/.*=//'  .env)	
			mariadb_user=$(sed '/MARIADB_USER/!d;s/.*=//'  .env)	
			mariadb_database=$(sed '/MARIADB_DATABASE/!d;s/.*=//'  .env)	
			
			if [ -z "$redis_password" ]; then
			  redis_password=$(sed '/REDIS_PASSWORD/!d;s/.*=//'  .env)
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
	
	if [ "$print" = true ]; then
		echo "image: $image; install_type: $install_type; mariadb_password: $mariadb_password;redis_password: $redis_password;middleware_ip: $middleware_ip;mariadb_user: $mariadb_user";
	fi

    
    echo ""
    echo "==> try to create cloudfon-cc service <=="
    echo ""
    #mariadb_password=$(date +%s%N | md5sum | cut -c 1-13)

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
			
			export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port 
			
			echo "export_configure_api"
			export_configure_api $image
			export_nginx_conf
			;;

		mid)
			echo "export_configure_mid"
			export_configure_mid $image $mariadb_user
			export_mariadb_conf
			middleware_ip='127.0.0.1'
			
            export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port 
			export_redis_conf $redis_password
			;;
		*)
			echo "export_configure_all"
			export_configure_all $image $mariadb_user
			export_mariadb_conf
			
			mariadb_url='cx-mariadb'
			redis_url='cx-redis'
			mariadb_port=3306
			redis_port=6379
			
            export_env $mariadb_url $mariadb_user $mariadb_password $mariadb_port $mariadb_database $redis_url $redis_password $redis_port 
			export_redis_conf $redis_password
			export_nginx_conf
			;;
		esac

	
    # run cloudfon-cc service
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
