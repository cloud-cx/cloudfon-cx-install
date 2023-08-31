#!/usr/bin/env bash
set -e

if [ -z $1 ];
then
    echo -e "\t => need parameters <="
    exit -1
fi

export_configure() {
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
    user: kong
    container_name: cx-kong
    environment: 
      KONG_DATABASE: off
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_PROXY_LISTEN: "0.0.0.0:9001 ssl, 0.0.0.0:443 ssl, 0.0.0.0:9006 ssl"
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_SSL_CERT: "/opt/kong/cert.pem"
      KONG_SSL_CERT_KEY: "/opt/kong/cert_key.pem"
      KONG_PREFIX: /var/run/kong
      KONG_DECLARATIVE_CONFIG: "/opt/kong/kong.yaml"
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
    restart: on-failure:5
    read_only: true
    volumes:
      - kong_prefix_vol:/var/run/kong
      - kong_tmp_vol:/tmp
      - ./cc_api:/opt/kong
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
    environment:
      MYSQL_ROOT_PASSWORD: 8ccDNF77xcJKO
    healthcheck:
      test: [ "CMD", "mysqladmin" ,"ping", "-h", "localhost","-p8ccDNF77xcJKO"]
      timeout: 20s
      retries: 10
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
      - "127.0.0.1:56379:6379"
    volumes:
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
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
    echo ""
    echo -e "\t => configure file done <="
    echo ""
    echo ""
}

create() {
    echo ""
    echo "==> try to create cloudfon-cc service <=="
    echo ""
    #echo " args: $@"
    #echo "The number of arguments passed in are : $#"

    # remove command firstly
    shift

    # 获取镜像名称
    image='puteyun/cloud_contact_center:2.0.4'
    
    while getopts 'i:' opt; do
        case "${opt}" in
            i)
                image="$OPTARG"
            ;;
        esac

    done

    export_configure $image
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

rm)
    rm $@
    ;;

*)
    echo -e "\t error command"
    ;;
esac