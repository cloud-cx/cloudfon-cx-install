#!/bin/bash

set -e

system_check(){
    if [  -f "/etc/redhat-release" ];then
        install_docker_on_centos
    elif [ -f "/etc/lsb-release" ];then
        install_docker_on_ubuntu
    elif [ -f "/etc/debian_version" ];then
        install_docker_on_debian
    else
        echo "Unknown operating system"
        exit
    fi
}

set_firewall(){
    echo ""
    echo "====>Stop the ufw"
    echo ""
    systemctl stop ufw || true
    systemctl disable ufw  || true
    echo ""
    echo "====>Enable the firewalld"
    echo ""
    systemctl enable firewalld
    systemctl start firewalld
    echo ""
    echo "====>Configure cloud-cx's default firewall rules"
    echo ""
    firewall-cmd --zone=trusted --remove-interface=docker0 --permanent
    firewall-cmd --reload
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --permanent --zone=public --new-service=cloud-cx || true
    firewall-cmd --permanent --zone=public --add-service=cloud-cx
	  firewall-cmd --zone=public --add-port=9001/tcp --permanent
	  firewall-cmd --zone=public --add-port=9006/tcp --permanent
	  firewall-cmd --zone=public --add-port=443/tcp --permanent
    firewall-cmd --permanent --zone=public --service=cloud-cx --add-port=9001/tcp --set-description="cloud-cx"
    firewall-cmd --permanent --zone=public --service=cloud-cx --add-port=9006/tcp --set-description="cloud-cx"
    firewall-cmd --permanent --zone=public --service=cloud-cx --add-port=443/tcp --set-description="cloud-cx"
    firewall-cmd --reload
    systemctl restart firewalld
    echo ""
    echo "====>Firewalld configure done"
    echo ""
}

# install docker and docker compose plugin
install_docker_on_centos(){
    echo ""
    echo "====>Starting to install on centos"
    echo ""
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    yum install -y yum-utils device-mapper-persistent-data lvm2 firewalld
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache fast
    echo ""
    echo "====>Try to install docker"
    echo ""
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====>Successfully to install the docker"
    echo ""

    set_firewall

    systemctl start docker
}

# install docker and docker compose plugin
install_docker_on_ubuntu(){
    echo ""
    echo "====>Starting to install on ubuntu"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove -y  docker docker-engine docker.io containerd runc || true
	  echo "====>remove docker end"
    apt update -y
    dpkg --configure -a || true
    DEBIAN_FRONTEND=noninteractive apt upgrade -y || true
    echo ""
    echo "====>System updated"
    echo ""
    echo "====>Try to install the firewalld"
    echo ""
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg gnupg-agent software-properties-common firewalld lsb-release
    echo ""
    echo "====>Firewalld installed"
    echo ""
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update -y
    echo ""
    echo "====>Try to install the docker"
    echo ""
    apt-get install docker-ce docker-compose-plugin -y
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====Successfully to install the docker"
    echo ""

    set_firewall

    systemctl start docker
}

# install docker and docker compose plugin
install_docker_on_debian(){
    echo ""
    echo "====>Starting to install on debian"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove docker docker-engine docker.io containerd runc || true
    apt update -y
    apt upgrade -y
    echo ""
    echo "====>System updated"

    echo ""
    echo "====>Try to install the firewalld"
    echo ""
    apt-get install apt-transport-https ca-certificates curl gnupg lsb-release firewalld -y
    systemctl stop firewalld
    echo ""
    echo "====>Firewalld installed"
    echo ""

    echo "====>Try to install docker"
    echo ""
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin -y
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====>Successfully to install the docker"
    echo ""

    sed -i 's#IndividualCalls=no#IndividualCalls=yes#g' /etc/firewalld/firewalld.conf

    set_firewall

    systemctl start docker
}

system_check