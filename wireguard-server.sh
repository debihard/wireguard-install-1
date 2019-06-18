#!/bin/bash
# Secure WireGuard For CentOS, Debian, Ubuntu, Raspbian, Arch, Fedora, Redhat
# https://github.com/LiveChief/wireguard-install

## Sanity Checks and automagic
function root-check() {
if [[ "$EUID" -ne 0 ]]; then
  echo "Sorry, you need to run this as root"
  exit
fi
}

## Root Check
root-check

## Detect OS
function dist-check() {
  if [ -e /etc/centos-release ]; then
    DISTRO="CentOS"
  elif [ -e /etc/debian_version ]; then
    DISTRO=$( lsb_release -is )
  elif [ -e /etc/arch-release ]; then
    DISTRO="Arch"
  elif [ -e /etc/fedora-release ]; then
    DISTRO="Fedora"
  elif [ -e /etc/redhat-release ]; then
    DISTRO="Redhat"
  else
    echo "Your distribution is not supported (yet)."
    exit
  fi
}

## Check distro
dist-check

  function virt-check() {
  ## Deny OpenVZ
  if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ virtualization is not supported (yet)."
    exit
  fi
  ## Deny LXC
  if [ "$(systemd-detect-virt)" == "lxc" ]; then
    echo "LXC virtualization is not supported (yet)."
    exit
  fi
}

## Virtualization Check
virt-check

function get-ip() {
  ## Test outward facing IPV4
    SERVER_HOST_V4=$(wget -qO- -t1 -T2 ipv4.icanhazip.com)
    read -rp "System public IPV4 address is $SERVER_HOST_V4. Is that correct? (y/n): " -e -i y SERVER_HOST_V4
  ## Test outward facing IPV6
    SERVER_HOST_V6=$(wget -qO- -t1 -T2 ipv6.icanhazip.com)
    read -rp "System public IPV6 address is $SERVER_HOST_V6. Is that correct? (y/n): " -e -i y SERVER_HOST_V6
}

## Get the IP Address
get-ip

  ## Determine host port
  function set-port() {
    echo "What port do you want WireGuard server to listen to?"
    echo "   1) 51820 (Recommended)"
    echo "   2) Custom (Advanced)"
    echo "   3) Random [1024-65535]"
    until [[ "$PORT_CHOICE" =~ ^[1-3]$ ]]; do
      read -rp "Port choice [1-3]: " -e -i 1 PORT_CHOICE
    done
    ## Apply port response
    case $PORT_CHOICE in
      1)
      SERVER_PORT="51820"
      ;;
      2)
      until [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] && [ "$SERVER_PORT" -ge 1 ] && [ "$SERVER_PORT" -le 65535 ]; do
        read -rp "Custom port [1-65535]: " -e -i 51820 SERVER_PORT
      done
      ;;
      3)
      SERVER_PORT=$(shuf -i1024-65535 -n1)
      echo "Random Port: $SERVER_PORT"
      ;;
    esac
  }

  ## Set Port
  set-port

  ## Determine Keepalive interval.
  function nat-keepalive() {
    echo "What do you want your keepalive interval to be?"
    echo "   1) 25 (Default)"
    echo "   2) Custom (Advanced)"
    until [[ "$NAT_CHOICE" =~ ^[1-2]$ ]]; do
      read -rp "Nat Choice [1-2]: " -e -i 1 NAT_CHOICE
    done
    ## Apply
    case $NAT_CHOICE in
      1)
      NAT_CHOICE="25"
      ;;
      2)
      until [[ "$NAT_CHOICE " =~ ^[0-9]+$ ]] && [ "$NAT_CHOICE " -ge 1 ] && [ "$NAT_CHOICE " -le 25 ]; do
        read -rp "Custom NAT [0-25]: " -e -i 25 NAT_CHOICE
      done
      ;;
    esac
  }

  ## Keepalive
  nat-keepalive

  ## Custom MTU or default settings
  function mtu-set() {
    echo "What MTU do you want to use?"
    echo "   1) 1280 (Recommended)"
    echo "   2) Custom (Advanced)"
    until [[ "$MTU_CHOICE" =~ ^[1-2]$ ]]; do
      read -rp "MTU choice [1-2]: " -e -i 1 MTU_CHOICE
    done
    case $MTU_CHOICE in
    1)
    MTU_CHOICE="1280"
    ;;
    2)
    until [[ "$MTU_CHOICE" =~ ^[0-9]+$ ]] && [ "$MTU_CHOICE" -ge 1 ] && [ "$MTU_CHOICE" -le 1500 ]; do
      read -rp "Custom MTU [1-1500]: " -e -i 1500 MTU_CHOICE
    done
    ;;
    esac
  }

  ## Set MTU
  mtu-set

  ## What ip version would you like to be available on this VPN?
  function ipvx-select() {
    echo "What IPv do you want to use to connect to WireGuard server?"
    echo "   1) IPv4 (Recommended)"
    echo "   2) IPv6 (Advanced)"
    until [[ "$SERVER_HOST" =~ ^[1-2]$ ]]; do
      read -rp "IP Choice [1-2]: " -e -i 1 SERVER_HOST
    done
    case $SERVER_HOST in
    1)
    SERVER_HOST="$SERVER_HOST_V4"
    ;;
    2)
    SERVER_HOST="[$SERVER_HOST_V6]"
    ;;
    esac
  }

  ## IPv4 or IPv6 Selector
  ipvx-select

  ## Do you want to disable IPv4 or IPv6 or leave them both enabled?
  function disable-ipvx() {
    echo "Do you want to disable IPv4 or IPv6 on the server?"
    echo "   1) No (Recommended)"
    echo "   2) IPV4"
    echo "   3) IPV6"
    until [[ "$DISABLE_HOST" =~ ^[1-3]$ ]]; do
      read -rp "Disable Host Choice [1-3]: " -e -i 1 DISABLE_HOST
    done
    case $DISABLE_HOST in
    1)
    DISABLE_HOST="sysctl --system"
    ;;
    2)
    DISABLE_HOST="$(sysctl -w net.ipv4.conf.all.disable_ipv4=1
    sysctl -w net.ipv4.conf.default.disable_ipv4=1
    sysctl --system)"
    ;;
    3)
    DISABLE_HOST="$(sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    sysctl --system)"
    ;;
    esac
  }

  ## Disable Ipv4 or Ipv6
  disable-ipvx

  ## Would you like to allow connections to your LAN neighbors?
  function client-allowed-ip() {
    echo "What traffic do you want the client to forward to wireguard?"
    echo "   1) Everything (Recommended)"
    echo "   2) Exclude Private IPs (Allows LAN IP connections)"
    until [[ "$CLIENT_ALLOWED_IP" =~ ^[1-2]$ ]]; do
      read -rp "Client Allowed IP Choice [1-2]: " -e -i 1 CLIENT_ALLOWED_IP
    done
    case $CLIENT_ALLOWED_IP in
    1)
    CLIENT_ALLOWED_IP="0.0.0.0/0,::/0"
    ;;
    2)
    CLIENT_ALLOWED_IP="0.0.0.0/1,128.0.0.0/1,::/1,8000::/1"
    ;;
    esac
  }

  ## Traffic Forwarding
  client-allowed-ip

  ## Would you like to install Unbound.
  function ask-install-unbound() {
    ## TODO: Explain to the user why in a few echo's they might want this?
    read -rp "Do You Want To Install Unbound (y/n): " -e -i y INSTALL_UNBOUND
    if [ "$INSTALL_UNBOUND" == "n" ]; then
      echo "Which DNS do you want to use with the VPN?"
      echo "   1) AdGuard (Recommended)"
      echo "   2) Google"
      echo "   3) OpenDNS"
      echo "   4) Cloudflare"
      echo "   5) Verisign"
      echo "   6) Quad9"
      echo "   7) FDN"
      echo "   8) DNS.WATCH"
      echo "   9) Yandex Basic"
      echo "   10) Clean Browsing"
      read -rp "DNS [1-10]: " -e -i 1 DNS_CHOICE
      case $DNS_CHOICE in
    1)
    CLIENT_DNS="176.103.130.130,176.103.130.131,2a00:5a60::ad1:0ff,2a00:5a60::ad2:0ff"
    ;;
    2)
    CLIENT_DNS="8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844"
    ;;
    3)
    CLIENT_DNS="208.67.222.222,208.67.220.220,2620:119:35::35,2620:119:53::53"
    ;;
    4)
    CLIENT_DNS="1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001"
    ;;
    5)
    CLIENT_DNS="64.6.64.6,64.6.65.6,2620:74:1b::1:1,2620:74:1c::2:2"
    ;;
    6)
    CLIENT_DNS="9.9.9.9,149.112.112.112,2620:fe::fe,2620:fe::9"
    ;;
    7)
    CLIENT_DNS="80.67.169.40,80.67.169.12,2001:910:800::40,2001:910:800::12"
    ;;
    8)
    CLIENT_DNS="84.200.69.80,84.200.70.40,2001:1608:10:25::1c04:b12f,2001:1608:10:25::9249:d69b"
    ;;
    9)
    CLIENT_DNS="77.88.8.8,77.88.8.1,2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff"
    ;;
    10)
    CLIENT_DNS="185.228.168.9,185.228.169.9,2a0d:2a00:1::2,2a0d:2a00:2::2"
    ;;
      esac
    fi
  }

  ## Unbound or DNS
  ask-install-unbound

  ## What would you like to name your first WireGuard peer?
  function client-name() {
    echo "Tell me a name for the client config file. Use one word only, no special characters. (No Spaces)"
    read -rp "Client Name: " -e CLIENT_NAME
  }

  ## Client Name
  client-name

## WG Configurator
  WG_CONFIG="/etc/wireguard/wg0.conf"
  if [ ! -f "$WG_CONFIG" ]; then
    INTERACTIVE=${INTERACTIVE:-yes}
    PRIVATE_SUBNET_V4=${PRIVATE_SUBNET_V4:-"10.8.0.0/24"}
    PRIVATE_SUBNET_MASK_V4=$( echo "$PRIVATE_SUBNET_V4" | cut -d "/" -f 2 )
    GATEWAY_ADDRESS_V4="${PRIVATE_SUBNET_V4::-4}1"
    PRIVATE_SUBNET_V6=${PRIVATE_SUBNET_V6:-"fd42:42:42::0/64"}
    PRIVATE_SUBNET_MASK_V6=$( echo "$PRIVATE_SUBNET_V6" | cut -d "/" -f 2 )
    GATEWAY_ADDRESS_V6="${PRIVATE_SUBNET_V6::-4}1"

  function install-wireguard() {
  ## Installation begins here.
  if [ "$DISTRO" == "Ubuntu" ]; then
    apt-get update
    apt-get install software-properties-common -y
    add-apt-repository ppa:wireguard/wireguard -y
    apt-get update
    apt-get install wireguard qrencode ntpdate linux-headers-"$(uname -r)" haveged iptables-persistent -y
  elif [ "$DISTRO" == "Debian" ]; then
    apt-get update
    echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
    printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
    apt-get update
    apt-get install wireguard qrencode ntpdate linux-headers-"$(uname -r)" haveged iptables-persistent -y
  elif [ "$DISTRO" == "Raspbian" ]; then
    apt-get update
    echo "deb http://deb.debian.org/debian/ unstable main" > /etc/apt/sources.list.d/unstable.list
    apt-get install dirmngr -y
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 04EE7237B7D453EC
    printf 'Package: *\nPin: release a=unstable\nPin-Priority: 90\n' > /etc/apt/preferences.d/limit-unstable
    apt-get update
    apt-get install wireguard qrencode ntpdate raspberrypi-kernel-headers haveged iptables-persistent -y
  elif [ "$DISTRO" == "Arch" ]; then
    pacman -S linux-headers wireguard-dkms wireguard-tools haveged qrencode ntp firewalld
  elif [ "$DISTRO" = 'Fedora' ]; then
    dnf update -y
    dnf copr enable jdoss/wireguard -y
    dnf install qrencode ntpdate kernel-headers-"$(uname -r)" kernel-devel-"$(uname -r)" wireguard-dkms wireguard-tools haveged firewalld -y
  elif [ "$DISTRO" == "CentOS" ]; then
    yum update -y
    wget -O /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install epel-release -y
    yum install wireguard-dkms wireguard-tools qrencode ntpdate kernel-headers-"$(uname -r)" kernel-devel-"$(uname -r)" haveged firewalld -y
  elif [ "$DISTRO" == "Redhat" ]; then
    yum update -y
    wget -O /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install epel-release -y
    yum install wireguard-dkms wireguard-tools qrencode ntpdate kernel-headers-"$(uname -r)" kernel-devel-"$(uname -r)" haveged firewalld -y
  fi
}

  ## Install WireGuard
  install-wireguard

  function ip-forwaring() {
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/wireguard.conf
  echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.d/wireguard.conf
}

  ## Ip Forwarding
  ip-forwaring

   ## Restart WireGuard
  function restart-wireguard(){
      if pgrep systemd-journal; then
        systemctl restart wg-quick@wg0
      else
        service wg-quick@wg0 restart
      fi
  }

  ## Restart unbound
  function restart-unbound(){
      if pgrep systemd-journal; then
        systemctl enable unbound
        systemctl restart unbound
      else
        service unbound restart
      fi
  }

  function install-firewall() {
  ## Firewall Rules
  if [ "$DISTRO" == "CentOS" ]; then
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --permanent --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
  elif [ "$DISTRO" == "Debian" ]; then
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir in -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir in -j ACCEPT
    iptables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir out -j MASQUERADE
    ip6tables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir out -j MASQUERADE
    iptables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    ip6tables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
  elif [ "$DISTRO" == "Ubuntu" ]; then
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir in -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir in -j ACCEPT
    iptables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir out -j MASQUERADE
    ip6tables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir out -j MASQUERADE
    iptables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    ip6tables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
  elif [ "$DISTRO" == "Raspbian" ]; then
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir in -j ACCEPT
    ip6tables -A FORWARD -m conntrack --ctstate NEW -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir in -j ACCEPT
    iptables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V4 -m policy --pol none --dir out -j MASQUERADE
    ip6tables -t nat -A POSTROUTING -s $PRIVATE_SUBNET_V6 -m policy --pol none --dir out -j MASQUERADE
    iptables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    ip6tables -A INPUT -p udp --dport $SERVER_PORT -j ACCEPT
    iptables-save > /etc/iptables/rules.v4
  elif [ "$DISTRO" == "Arch" ]; then
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --permanent --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
  elif [ "$DISTRO" == "Fedora" ]; then
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --permanent --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
  elif [ "$DISTRO" == "Redhat" ]; then
    systemctl enable firewalld
    systemctl start firewalld
    firewall-cmd --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --permanent --zone=public --add-port=$SERVER_PORT/udp
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V4
    firewall-cmd --permanent --zone=trusted --add-source=$PRIVATE_SUBNET_V6
    firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
    firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V4 ! -d $PRIVATE_SUBNET_V4 -j SNAT --to $SERVER_HOST_V4
    firewall-cmd --permanent --direct --add-rule ipv6 nat POSTROUTING 0 -s $PRIVATE_SUBNET_V6 ! -d $PRIVATE_SUBNET_V6 -j SNAT --to $SERVER_HOST_V6
fi
}

  ## Install Firewall
  install-firewall

  function install-unbound() {
    ## Set DNS Root Servers
    wget -O /etc/unbound/root.hints https://www.internic.net/domain/named.cache
    ## Installation Begins Here For Systems
    if [ "$DISTRO" == "Ubuntu" ]; then
    # Install Unbound
    apt-get install unbound unbound-host e2fsprogs -y
    ## Set Config
    echo 'server:
    num-threads: 4
    verbosity: 1
    root-hints: "/etc/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    interface: 0.0.0.0
    interface: ::0
    max-udp-size: 3072
    access-control: 0.0.0.0/0                 refuse
    access-control: 10.8.0.0/24               allow
    private-address: 10.8.0.0/24
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000000
    val-log-level: 1
    cache-min-ttl: 1800
    cache-max-ttl: 14400
    prefetch: yes
    qname-minimisation: yes
    prefetch-key: yes' > /etc/unbound/unbound.conf
    ## Apply settings
    systemctl stop systemd-resolved
    systemctl disable systemd-resolved
    # Firewall Rule For Unbound
    iptables -A INPUT -s 10.8.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
  elif [ "$DISTRO" == "Debian" ]; then
    # Install Unbound
    apt-get install unbound unbound-host e2fsprogs -y
    ## Set Config
    echo 'server:
    num-threads: 4
    verbosity: 1
    root-hints: "/etc/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    interface: 0.0.0.0
    interface: ::0
    max-udp-size: 3072
    access-control: 0.0.0.0/0                 refuse
    access-control: 10.8.0.0/24               allow
    private-address: 10.8.0.0/24
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000000
    val-log-level: 1
    cache-min-ttl: 1800
    cache-max-ttl: 14400
    prefetch: yes
    qname-minimisation: yes
    prefetch-key: yes' > /etc/unbound/unbound.conf
    # Firewall Rule For Unbound
    iptables -A INPUT -s 10.8.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
  elif [ "$DISTRO" == "Raspbian" ]; then
    # Install Unbound
    apt-get install unbound unbound-host e2fsprogs -y
    ## Set Config
    echo 'server:
    num-threads: 4
    verbosity: 1
    root-hints: "/etc/unbound/root.hints"
    auto-trust-anchor-file: "/var/lib/unbound/root.key"
    interface: 0.0.0.0
    interface: ::0
    max-udp-size: 3072
    access-control: 0.0.0.0/0                 refuse
    access-control: 10.8.0.0/24               allow
    private-address: 10.8.0.0/24
    hide-identity: yes
    hide-version: yes
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: yes
    unwanted-reply-threshold: 10000000
    val-log-level: 1
    cache-min-ttl: 1800
    cache-max-ttl: 14400
    prefetch: yes
    qname-minimisation: yes
    prefetch-key: yes' > /etc/unbound/unbound.conf
    # Firewall Rule For Unbound
    iptables -A INPUT -s 10.8.0.0/24 -p udp -m udp --dport 53 -m conntrack --ctstate NEW -j ACCEPT
  elif [[ "$DISTRO" = "CentOS" ]]; then
    # Install Unbound
    yum install unbound unbound-host -y
    sed -i 's|# interface: 0.0.0.0$|interface: 10.8.0.1|' /etc/unbound/unbound.conf
    sed -i 's|# access-control: 127.0.0.0/8 allow|access-control: 10.8.0.1/24 allow|' /etc/unbound/unbound.conf
    sed -i 's|# hide-identity: no|hide-identity: yes|' /etc/unbound/unbound.conf
    sed -i 's|# hide-version: no|hide-version: yes|' /etc/unbound/unbound.conf
    sed -i 's|use-caps-for-id: no|use-caps-for-id: yes|' /etc/unbound/unbound.conf
    # Firewall Rule For Unbound
    firewall-cmd --add-service=dns --permanent
  elif [[ "$DISTRO" = "Fedora" ]]; then
    dnf install unbound unbound-host -y
    ## TODO: Make these files in {gitroot}/config/unbound-distro.conf then install it via curl/wget
    sed -i 's|# interface: 0.0.0.0$|interface: 10.8.0.1|' /etc/unbound/unbound.conf
    sed -i 's|# access-control: 127.0.0.0/8 allow|access-control: 10.8.0.1/24 allow|' /etc/unbound/unbound.conf
    sed -i 's|# hide-identity: no|hide-identity: yes|' /etc/unbound/unbound.conf
    sed -i 's|# hide-version: no|hide-version: yes|' /etc/unbound/unbound.conf
    sed -i 's|use-caps-for-id: no|use-caps-for-id: yes|' /etc/unbound/unbound.conf
    # Firewall Rule For Unbound
    firewall-cmd --add-service=dns --permanent
  elif [[ "$DISTRO" = "Arch" ]]; then
    pacman -Syu unbound unbound-host
    ## TODO: Make these files in {gitroot}/config/unbound-distro.conf then install it via curl/wget
    mv /etc/unbound/unbound.conf /etc/unbound/unbound.conf.old
    echo 'server:
    use-syslog: yes
    do-daemonize: no
    username: "unbound"
    directory: "/etc/unbound"
    trust-anchor-file: trusted-key.key
    root-hints: root.hints
    interface: 10.8.0.0
    access-control: 10.8.0.0 allow
    port: 53
    num-threads: 2
    use-caps-for-id: yes
    harden-glue: yes
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes
    prefetch: yes' > /etc/unbound/unbound.conf
    # Firewall Rule For Unbound
    firewall-cmd --add-service=dns --permanent
      fi
        # Setting Client DNS For Unbound On WireGuard
        CLIENT_DNS="10.8.0.1"
        ## Setting correct nameservers for system.
        chattr -i /etc/resolv.conf
        sed -i "/nameserver/#nameserver/" /etc/resolv.conf
        sed -i "/search/#search/" /etc/resolv.conf
        echo "nameserver 127.0.0.1" >> /etc/resolv.conf
        chattr +i /etc/resolv.conf
  }
  ## Install Unbound
  install-unbound
  ## Restart Unbound
  restart-unbound

  ## WireGuard Set Config
  function wireguard-setconf() {
    SERVER_PRIVKEY=$( wg genkey )
    SERVER_PUBKEY=$( echo "$SERVER_PRIVKEY" | wg pubkey )
    CLIENT_PRIVKEY=$( wg genkey )
    CLIENT_PUBKEY=$( echo "$CLIENT_PRIVKEY" | wg pubkey )
    CLIENT_ADDRESS_V4="${PRIVATE_SUBNET_V4::-4}3"
    CLIENT_ADDRESS_V6="${PRIVATE_SUBNET_V6::-4}3"
    PRESHARED_KEY=$( wg genpsk )
    mkdir -p /etc/wireguard
    touch $WG_CONFIG && chmod 600 $WG_CONFIG
    ## Set Wireguard settings for this host and first peer.

echo "# $PRIVATE_SUBNET_V4 $PRIVATE_SUBNET_V6 $SERVER_HOST:$SERVER_PORT $SERVER_PUBKEY $CLIENT_DNS $MTU_CHOICE $NAT_CHOICE $CLIENT_ALLOWED_IP
[Interface]
Address = $GATEWAY_ADDRESS_V4/$PRIVATE_SUBNET_MASK_V4,$GATEWAY_ADDRESS_V6/$PRIVATE_SUBNET_MASK_V6
ListenPort = $SERVER_PORT
PrivateKey = $SERVER_PRIVKEY
SaveConfig = false
# $CLIENT_NAME start
[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_ADDRESS_V4/32,$CLIENT_ADDRESS_V6/128
# $CLIENT_NAME end" > $WG_CONFIG

echo "# $CLIENT_NAME
[Interface]
Address = $CLIENT_ADDRESS_V4/$PRIVATE_SUBNET_MASK_V4,$CLIENT_ADDRESS_V6/$PRIVATE_SUBNET_MASK_V6
DNS = $CLIENT_DNS
MTU = $MTU_CHOICE
PrivateKey = $CLIENT_PRIVKEY
[Peer]
AllowedIPs = $CLIENT_ALLOWED_IP
Endpoint = $SERVER_HOST:$SERVER_PORT
PersistentKeepalive = $NAT_CHOICE
PresharedKey = $PRESHARED_KEY
PublicKey = $SERVER_PUBKEY" > "$HOME"/"$CLIENT_NAME"-wg0.conf
qrencode -t ansiutf8 -l L < "$HOME"/"$CLIENT_NAME"-wg0.conf
}
  ## Setting Up Wireguard Config
  wireguard-setconf

  ## WireGuard restart
  restart-wireguard

  ## Setup Network Time Protocol To Correct Server.
  ntpdate pool.ntp.org

  ## Echo Client Config File
  echo "Client Config --> "$HOME"/"$CLIENT_NAME"-wg0.conf"

else
  ## Already installed what next?
  function wireguard-next-questions() {
  echo "Looks like Wireguard is already installed."
  echo "What do you want to do?"
  echo "   1) Add A New WireGuard User"
  echo "   2) Remove User From WireGuard"
  echo "   3) Uninstall WireGuard"
  echo "   4) Exit"
  until [[ "$WIREGUARD_OPTIONS" =~ ^[1-4]$ ]]; do
    read -rp "Select an Option [1-4]: " -e -i 1 WIREGUARD_OPTIONS
  done
  case $WIREGUARD_OPTIONS in
    1)
    echo "Tell me a new name for the client config file. Use one word only, no special characters. (No Spaces)"
    read -rp "New client name: " -e NEW_CLIENT_NAME
    adding-wireguard-client
    ;;
    2)
      ## Remove User
      echo "Which WireGuard User Do You Want To Remove?"
      cat $WG_CONFIG|grep start| awk '{ print $2 }'
      read -rp "Type  in Client ID : " -e REMOVECLIENT
      read -rp "Are you sure you want to remove $REMOVECLIENT ? (y/n): " -n 1 -r
      if [[ $REPLY =~ ^[Yy]$ ]]
      then
         echo
         sed -i "/\# $REMOVECLIENT start/,/\# $REMOVECLIENT end/d" $WG_CONFIG
      fi
      exit
      restart-wireguard
      echo "Client named $REMOVECLIENT has been removed."
    ;;
    3)
    ## Uninstall Wireguard
    read -rp "Do you really want to remove Wireguard? [y/n]:" -e -i n REMOVE_WIREGUARD
    uninstall-wireguard
    ;;
    4)
    exit
    ;;
  esac
}

## Running Questions Command
wireguard-next-questions

  function adding-wireguard-client() {
CLIENT_PRIVKEY=$( wg genkey )
CLIENT_PUBKEY=$( echo "$CLIENT_PRIVKEY" | wg pubkey )
PRESHARED_KEY=$( wg genpsk )
PRIVATE_SUBNET_V4=$( head -n1 $WG_CONFIG | awk '{print $2}')
PRIVATE_SUBNET_MASK_V4=$( echo "$PRIVATE_SUBNET_V4" | cut -d "/" -f 2 )
PRIVATE_SUBNET_V6=$( head -n1 $WG_CONFIG | awk '{print $3}')
PRIVATE_SUBNET_MASK_V6=$( echo "$PRIVATE_SUBNET_V6" | cut -d "/" -f 2 )
SERVER_HOST=$( head -n1 $WG_CONFIG | awk '{print $4}')
SERVER_PUBKEY=$( head -n1 $WG_CONFIG | awk '{print $5}')
CLIENT_DNS=$( head -n1 $WG_CONFIG | awk '{print $6}')
MTU_CHOICE=$( head -n1 $WG_CONFIG | awk '{print $7}')
NAT_CHOICE=$( head -n1 $WG_CONFIG | awk '{print $8}')
CLIENT_ALLOWED_IP=$( head -n1 $WG_CONFIG | awk '{print $9}')
LASTIP4=$( grep "/32" $WG_CONFIG | tail -n1 | awk '{print $3}' | cut -d "/" -f 1 | cut -d "." -f 4 )
## TODO: Implement this variable wherever it is intended to go.
LASTIP6=$( grep "/128" $WG_CONFIG | tail -n1 | awk '{print $6}' | cut -d "/" -f 1 | cut -d "." -f 4 )
CLIENT_ADDRESS_V4="${PRIVATE_SUBNET_V4::-4}$((LASTIP4+1))"
CLIENT_ADDRESS_V6="${PRIVATE_SUBNET_V6::-4}$((LASTIP4+1))"
echo "# $NEW_CLIENT_NAME start
[Peer]
PublicKey = $CLIENT_PUBKEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_ADDRESS_V4/32,$CLIENT_ADDRESS_V6/128
# $NEW_CLIENT_NAME end" >> $WG_CONFIG
echo "## $NEW_CLIENT_NAME
[Interface]
Address = $CLIENT_ADDRESS_V4/$PRIVATE_SUBNET_MASK_V4,$CLIENT_ADDRESS_V6/$PRIVATE_SUBNET_MASK_V6
DNS = $CLIENT_DNS
MTU = $MTU_CHOICE
PrivateKey = $CLIENT_PRIVKEY
[Peer]
AllowedIPs = $CLIENT_ALLOWED_IP
Endpoint = $SERVER_HOST$SERVER_PORT
PersistentKeepalive = $NAT_CHOICE
PresharedKey = $PRESHARED_KEY
PublicKey = $SERVER_PUBKEY" > "$HOME"/"$NEW_CLIENT_NAME"-wg0.conf
qrencode -t ansiutf8 -l L < "$HOME"/"$NEW_CLIENT_NAME"-wg0.conf
echo "Client config --> "$HOME"/"$NEW_CLIENT_NAME"-wg0.conf"
restart-wireguard
}

  ## Uninstall WireGuard Functions
  function uninstall-wireguard() {
  if [ "$DISTRO" == "CentOS" ]; then
        wg-quick down wg0
        yum remove wireguard qrencode ntpdate haveged unbound unbound-host firewalld -y
  elif [ "$DISTRO" == "Debian" ]; then
        wg-quick down wg0
        apt-get remove --purge wireguard qrencode ntpdate haveged unbound unbound-host e2fsprogs iptables-persistent -y
  elif [ "$DISTRO" == "Ubuntu" ]; then
        wg-quick down wg0
        apt-get remove --purge wireguard qrencode ntpdate haveged unbound unbound-host e2fsprogs iptables-persistent -y
  elif [ "$DISTRO" == "Raspbian" ]; then
        wg-quick down wg0
        apt-get remove --purge wireguard qrencode ntpdate haveged unbound unbound-host e2fsprogs dirmngr iptables-persistent -y
  elif [ "$DISTRO" == "Arch" ]; then
        wg-quick down wg0
        pacman -Rs wireguard qrencode ntpdate haveged unbound unbound-host firewalld -y
  elif [ "$DISTRO" == "Fedora" ]; then
        wg-quick down wg0
        dnf remove wireguard qrencode ntpdate haveged unbound unbound-host firewalld -y
  elif [ "$DISTRO" == "Redhat" ]; then
        wg-quick down wg0
        yum remove wireguard qrencode ntpdate haveged unbound unbound-host firewalld -y
  fi
        rm -rf /etc/wireguard
        rm -rf /etc/unbound
        rm -rf /etc/qrencode
        rm /etc/sysctl.d/wireguard.conf
        rm /etc/ntp.conf
        rm /etc/iptables/rules.v4
        rm /etc/firewalld/firewalld.conf
        rm /etc/default/haveged
        ## Echo Uninstall Message
  echo "Wireguard successfully uninstalled"
}
