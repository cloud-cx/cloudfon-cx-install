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
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
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
      context: ./cx_api
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
      KONG_PROXY_LISTEN: "0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
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
      - "443:443"
      - "9001:9001"
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
      - ./conf/kong-nginx.conf:/var/run/kong/nginx.conf
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
      - ./conf/my.cnf:/etc/mysql/my.cnf:ro
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
      - ./conf/redis.conf:/etc/redis/redis.conf
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
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
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
      context: ./cx_api
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
      KONG_PROXY_LISTEN: "0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
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
      - "443:443"
      - "9001:9001"
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
      - ./conf/kong-nginx.conf:/var/run/kong/nginx.conf
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
      - ./conf/my.cnf:/etc/mysql/my.cnf:ro
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
      - ./conf/redis.conf:/etc/redis/redis.conf
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
      test: [ "CMD", "curl" ,"--fail","-k", "http://localhost:8000/time"]
      timeout: 20s
      retries: 10
    networks:
      - cx-network
    build:
      context: ./cx_api
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
      KONG_PROXY_LISTEN: "0.0.0.0:443 ssl, 0.0.0.0:9006 ssl, 0.0.0.0:9001 ssl"
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
      - "443:443"
      - "9001:9001"
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
      - ./conf/kong-nginx.conf:/var/run/kong/nginx.conf
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
      - ./conf/my.cnf:/etc/mysql/my.cnf:ro
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
      - ./conf/redis.conf:/etc/redis/redis.conf
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
      - ./conf/my.cnf:/etc/mysql/my.cnf:ro
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
      - ./conf/redis.conf:/etc/redis/redis.conf
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

    cat << FEOF > conf/kong-nginx.conf
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

	     add_header Content-Security-Policy "default-src 'self' 'unsafe-inline' https: data: blob: wss:; base-uri 'self'; script-src 'self' https: 'unsafe-inline' 'unsafe-eval'";
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

    cat << FEOF > .env
MARIADB_URL=$1
MARIADB_USER=$2
MARIADB_PASSWORD=$3
MARIADB_PORT=$4
MARIADB_DATABASE=$5
REDIS_URL=$6
REDIS_PASSWORD=$7
REDIS_PORT=$8
MIDDLEWARE_HOST=$9
JVM_MEM=${10}

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
    cat << FEOF >  conf/my.cnf
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
innodb_log_buffer_size =${1}M
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
    cat << FEOF >  conf/redis.conf
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

create() {
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

	options=$(getopt -o i:t:m:r:w:u:b:s:d:ph --long image:,install_type:,mariadb_password:,redis_password:,middleware_ip:,mariadb_user:,mariadb_port:,redis_port:,mariadb_database: -- "$@")
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


	if [ -z "$install_type" ]; then
		install_type='all'
	fi

	if [ "$install_type" != "mid" ];then
		if [ -z "$image" ]; then
			echo "Error: image is required"
			exit 1
		fi
	fi

	FILE=".env"
	#创建配置文件路径
	mkdir -p conf
	#迁移目录cc_api到cx_api目录
	if [ -d "./cc_api" ];then
		mv ./cc_api ./cx_api
	fi
	###########
	#迁移配置文件到conf目录
	if [ -f "./my.cnf" ];then
		mv ./my.cnf ./conf
	fi

	if [ -f "./redis.conf" ];then
		mv ./redis.conf ./conf
	fi

	if [ -f "./kong-nginx.conf" ];then
		mv ./kong-nginx.conf ./conf
	fi
	############
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
			export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port $middleware_ip $jvm_mem
			
			echo "export_configure_api"
			export_configure_api $image
			export_nginx_conf
			;;

		mid)
			echo "export_configure_mid"
			export_configure_mid $image $mariadb_user
			configMem=$(awk -v x=${totalMem} -v y=0.4 'BEGIN{printf "%.0f",x*y}')
			echo "totalMem:${totalMem}  configMem:${configMem}"
			export_mariadb_conf $configMem
			
			middleware_ip='127.0.0.1'			
            export_env $middleware_ip $mariadb_user $mariadb_password $mariadb_port $mariadb_database $middleware_ip $redis_password $redis_port $middleware_ip
			export_redis_conf $redis_password
			;;
		*)
			echo "export_configure_all"
			export_configure_all $image $mariadb_user
			configMem=$(awk -v x=${totalMem} -v y=0.4 'BEGIN{printf "%.0f",x*y}')
			jvm_mem=$(awk -v x=${totalMem} -v y=0.4 'BEGIN{printf "%.0f",x*y}')
			echo "totalMem:${totalMem}  configMem:${configMem} jvm_mem:${jvm_mem}"
			export_mariadb_conf $configMem
			
			mariadb_url='cx-mariadb'
			redis_url='cx-redis'
			mariadb_port=3306
			redis_port=6379
			middleware_ip='127.0.0.1'

            export_env $mariadb_url $mariadb_user $mariadb_password $mariadb_port $mariadb_database $redis_url $redis_password $redis_port $middleware_ip $jvm_mem
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
