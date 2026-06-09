#!/bin/bash
set -e

system_check(){
    timezone_check

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "====> Docker is already installed, skipping."
        echo ""
        return
    fi

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
    echo "====> Firewall configuration"
    echo ""

    # --------------------------------------------------
    # 1. Detect firewall -- priority: (active) firewalld > ufw > (installed) firewalld > ufw
    # --------------------------------------------------

    # --- Case A: firewalld is ACTIVE (running) -> configure and reload ---
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        echo ""
        echo "====> [WARNING] firewalld detected (active)"
        echo "====> Adding required ports (9001, 9006, 443) and allowing SSH"
        echo ""

        firewall-cmd --zone=trusted --remove-interface=docker0 --permanent || true
        firewall-cmd --permanent --add-service=ssh || true
        firewall-cmd --zone=public --add-port=9001/tcp --permanent || true
        firewall-cmd --zone=public --add-port=9006/tcp --permanent || true
        firewall-cmd --zone=public --add-port=443/tcp --permanent || true
        firewall-cmd --reload || true

        echo ""
        echo "====> firewalld rule configuration completed"
        echo ""
        return
    fi

    # --- Case B: UFW is ACTIVE -> configure ---
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "active"; then
        echo ""
        echo "====> [WARNING] UFW detected (active)"
        echo "====> Adding required ports (9001, 9006, 443) and allowing SSH"
        echo ""

        ufw allow ssh || true
        ufw allow 9001/tcp || true
        ufw allow 9006/tcp || true
        ufw allow 443/tcp || true

        echo ""
        echo "====> UFW rule configuration completed"
        echo ""
        return
    fi

    # --- Case C: firewalld installed but INACTIVE -> add permanent rules only, don't start ---
    if command -v firewall-cmd >/dev/null 2>&1 || systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
        echo ""
        echo "====> [WARNING] firewalld detected (inactive) - adding permanent rules"
        echo ""

        firewall-cmd --zone=trusted --remove-interface=docker0 --permanent || true
        firewall-cmd --permanent --add-service=ssh || true
        firewall-cmd --zone=public --add-port=9001/tcp --permanent || true
        firewall-cmd --zone=public --add-port=9006/tcp --permanent || true
        firewall-cmd --zone=public --add-port=443/tcp --permanent || true

        echo ""
        echo "====> firewalld permanent rules added (service remains inactive)"
        echo ""
        return
    fi

    # --- Case D: UFW installed but INACTIVE -> add rules only, don't enable ---
    if command -v ufw >/dev/null 2>&1; then
        echo ""
        echo "====> [WARNING] UFW detected (inactive) - adding rules"
        echo ""

        ufw allow ssh || true
        ufw allow 9001/tcp || true
        ufw allow 9006/tcp || true
        ufw allow 443/tcp || true

        echo ""
        echo "====> UFW rules added (service remains inactive)"
        echo ""
        return
    fi

    # --------------------------------------------------
    # 2. No firewall at all -- install firewalld first
    # --------------------------------------------------

    echo ""
    echo "====> No firewall found, installing firewalld..."
    echo ""

    # Determine package manager
    if command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
    else
        echo "====> WARNING: Unknown package manager, cannot install firewall. Skipping."
        return
    fi

    # --- Try firewalld ---
    FIREWALLD_OK=false

    if [ "$PKG_MGR" = "yum" ]; then
        yum install -y firewalld || true
    elif [ "$PKG_MGR" = "apt" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y firewalld || true
    fi

    if command -v firewall-cmd >/dev/null 2>&1 || systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
        systemctl enable firewalld 2>/dev/null || true
        systemctl start firewalld 2>/dev/null || true
        systemctl is-active --quiet firewalld 2>/dev/null && FIREWALLD_OK=true
    fi

    if [ "$FIREWALLD_OK" = true ]; then
        echo ""
        echo "====> firewalld installed and started successfully"
        echo ""

        firewall-cmd --zone=trusted --remove-interface=docker0 --permanent || true
        firewall-cmd --permanent --add-service=ssh || true
        firewall-cmd --zone=public --add-port=9001/tcp --permanent || true
        firewall-cmd --zone=public --add-port=9006/tcp --permanent || true
        firewall-cmd --zone=public --add-port=443/tcp --permanent || true
        firewall-cmd --reload || true

        echo ""
        echo "====> firewalld rule configuration completed"
        echo ""
        return
    fi

    # --- firewalld failed → try UFW ---
    echo ""
    echo "====> firewalld installation failed, attempting UFW..."
    echo ""

    UFW_OK=false

    if [ "$PKG_MGR" = "yum" ]; then
        yum install -y ufw || true
    elif [ "$PKG_MGR" = "apt" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw || true
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw --force enable 2>/dev/null || true
        ufw status 2>/dev/null | grep -qi "active" && UFW_OK=true
    fi

    if [ "$UFW_OK" = true ]; then
        echo ""
        echo "====> UFW installed and started successfully"
        echo ""

        ufw allow ssh || true
        ufw allow 9001/tcp || true
        ufw allow 9006/tcp || true
        ufw allow 443/tcp || true

        echo ""
        echo "====> UFW rule configuration completed"
        echo ""
        return
    fi

    # --- Both failed ---
    echo ""
    echo -e "\e[1;31m====> [ERROR] Failed to install firewalld or UFW.\e[0m"
    echo -e "\e[1;31m====> Please manually configure firewall rules: allow ports 9001, 9006, 443 (TCP) and SSH.\e[0m"
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
    yum install -y yum-utils device-mapper-persistent-data lvm2
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
    echo "====>Install base dependencies"
    echo ""
    DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg software-properties-common lsb-release
    echo ""
    echo "====>Base dependencies installed"
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
    echo "====> Install base packages"
    apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release || true

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
