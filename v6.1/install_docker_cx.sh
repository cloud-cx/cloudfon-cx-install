#!/bin/bash
set -e

system_check(){
    timezone_check
    if [ -f "/etc/redhat-release" ]; then
        install_docker_on_centos
    elif [ -f "/etc/lsb-release" ]; then
        install_docker_on_ubuntu
    elif [ -f "/etc/debian_version" ]; then
        install_docker_on_debian
    else
        echo "Unknown operating system"
        exit 1
    fi
}

set_firewall(){
    echo ""

    # ===== Debian: use UFW, NEVER firewalld =====
    if [ -f /etc/debian_version ]; then
        echo "====> Debian detected, use UFW (skip firewalld)"
        echo ""

        apt-get install -y ufw || true

        ufw allow ssh || true
        ufw allow 9001/tcp || true
        ufw allow 9006/tcp || true
        ufw allow 443/tcp || true

        ufw --force enable || true

        echo ""
        echo "====> UFW configure done"
        echo ""
        return
    fi


    # ===== Non-Debian: use firewalld =====
    echo "====> Disable UFW (if exists)"
    ufw --force disable || true

    echo ""
    echo "====> Enable firewalld"
    systemctl enable firewalld
    systemctl start firewalld

    echo ""
    echo "====> Configure cloudfon-cc firewall rules"
    firewall-cmd --zone=trusted --remove-interface=docker0 --permanent || true
    firewall-cmd --reload

    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --zone=public --add-port=9001/tcp --permanent
    firewall-cmd --zone=public --add-port=9006/tcp --permanent
    firewall-cmd --zone=public --add-port=443/tcp --permanent

    firewall-cmd --reload
    systemctl restart firewalld

    echo ""
    echo "====> Firewalld configure done"
    echo ""
}

# =========================
# CentOS / Rocky
# =========================
install_docker_on_centos(){
    echo ""
    echo "====> Starting to install on centos"
    echo ""
    yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine || true
    yum install -y yum-utils device-mapper-persistent-data lvm2 firewalld
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum makecache
    echo ""
    echo "====> Try to install docker"
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl stop docker
    echo ""
    echo "====> Docker installed"

    set_firewall

    systemctl start docker
}

# =========================
# Ubuntu
# =========================
install_docker_on_ubuntu(){
    echo ""
    echo "====> Starting to install on ubuntu"
    echo ""
    echo "====>Try to update system"
    echo ""
    apt-get remove -y docker docker-engine docker.io containerd runc || true
	  echo "====>remove docker end"
    apt update -y
    dpkg --configure -a || true
    DEBIAN_FRONTEND=noninteractive apt upgrade -y || true
    echo ""
    echo "====>System updated"
    echo ""
    echo "====>Try to install the firewalld"
    echo ""
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common firewalld lsb-release
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

# =========================
# Debian (7 ~ 13)
# =========================
install_docker_on_debian(){
    echo ""
    echo "====> Starting to install on debian"
    echo ""

    apt-get remove -y docker docker-engine docker.io containerd runc || true
    apt update -y
    apt upgrade -y
    echo ""
    echo "====> Install base packages (NO firewalld)"
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release ufw || true

    echo ""
    echo "====> Try to install docker"

    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable"  | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    systemctl enable docker
    systemctl stop docker

    echo ""
    echo "====> Docker installed"

    set_firewall

    systemctl start docker
}

timezone_check(){
  	tz=$(timedatectl show -p Timezone --value 2>/dev/null)
    if [ -z "$tz" ] && [ -f /etc/localtime ]; then
        tz=$(readlink /etc/localtime | sed "s|.*/zoneinfo/||")
    fi
    if [ ! -f "/etc/timezone" ]; then
        echo "$tz" > /etc/timezone
    fi
}

system_check
