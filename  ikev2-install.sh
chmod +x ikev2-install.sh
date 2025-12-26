#!/bin/bash

# IKEv2/IPSec VPN Server with Certificate Authentication - One-click Installation Script
# Tested on Ubuntu 20.04/22.04 and Debian 10/11/12
# Perfect for iOS/macOS clients

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
IPSEC_CONF_DIR="/etc/ipsec.d"
IPSEC_SECRETS="/etc/ipsec.secrets"
IPSEC_CONF="/etc/ipsec.conf"
STRONGSWAN_CONF="/etc/strongswan.conf"
MOBILECONFIG_DIR="/root/ikev2-mobileconfig"

# Server configuration
PUBLIC_IP=$(curl -s --connect-timeout 5 https://ifconfig.me || curl -s --connect-timeout 5 https://ipinfo.io/ip || echo "YOUR_SERVER_IP")
SERVER_IP=$(ip -4 addr show $(ip route | grep default | awk '{print $5}' 2>/dev/null | head -1) 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$PUBLIC_IP
fi

VPN_DNS="8.8.8.8,8.8.4.4"
VPN_DOMAIN="vpn.example.com"
VPN_USERNAME="vpnuser"
VPN_PASSWORD=$(openssl rand -base64 12 | tr -d '=' | head -c 12)

# Certificate configuration
CERT_COUNTRY="US"
CERT_STATE="California"
CERT_CITY="San Francisco"
CERT_ORG="My IKEv2 VPN"
CERT_EMAIL="admin@vpn.example.com"
CERT_CN=$VPN_DOMAIN  # Use domain name as Common Name for better compatibility
CERT_DAYS=3650

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS type"
        exit 1
    fi
    
    log_info "Detected OS: $OS $VERSION"
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        log_error "This script only supports Ubuntu and Debian"
        exit 1
    fi
}

update_system() {
    log_info "Updating system packages..."
    apt-get update
    apt-get upgrade -y
}

install_dependencies() {
    log_info "Installing required packages..."
    
    apt-get update
    apt-get install -y \
        strongswan \
        strongswan-pki \
        libcharon-extra-plugins \
        libcharon-extauth-plugins \
        libstrongswan-extra-plugins \
        libtss2-tcti-tabrmd0 \
        curl \
        openssl
    
    # For mobileconfig generation
    apt-get install -y python3 python3-pip || true
}

generate_certificates() {
    log_info "Generating PKI certificates for IKEv2..."
    
    # Create directories
    mkdir -p $IPSEC_CONF_DIR/{cacerts,certs,private}
    chmod 700 $IPSEC_CONF_DIR/private
    
    # Generate CA certificate
    log_info "Generating CA certificate..."
    ipsec pki --gen --type rsa --size 4096 --outform pem > $IPSEC_CONF_DIR/private/ca-key.pem 2>/dev/null
    
    ipsec pki --self --ca --lifetime $CERT_DAYS \
        --in $IPSEC_CONF_DIR/private/ca-key.pem \
        --dn "C=$CERT_COUNTRY, O=$CERT_ORG, CN=$CERT_CN VPN Root CA" \
        --outform pem > $IPSEC_CONF_DIR/cacerts/ca-cert.pem
    
    # Generate server certificate
    log_info "Generating server certificate..."
    ipsec pki --gen --type rsa --size 4096 --outform pem > $IPSEC_CONF_DIR/private/server-key.pem 2>/dev/null
    
    ipsec pki --pub --in $IPSEC_CONF_DIR/private/server-key.pem \
        | ipsec pki --issue --lifetime $CERT_DAYS \
            --cacert $IPSEC_CONF_DIR/cacerts/ca-cert.pem \
            --cakey $IPSEC_CONF_DIR/private/ca-key.pem \
            --dn "C=$CERT_COUNTRY, O=$CERT_ORG, CN=$CERT_CN" \
            --san "$CERT_CN" \
            --san "$SERVER_IP" \
            --san "$PUBLIC_IP" \
            --flag serverAuth \
            --flag ikeIntermediate \
            --outform pem > $IPSEC_CONF_DIR/certs/server-cert.pem
    
    # Generate client certificate
    log_info "Generating client certificate..."
    ipsec pki --gen --type rsa --size 2048 --outform pem > $IPSEC_CONF_DIR/private/client-key.pem 2>/dev/null
    
    ipsec pki --pub --in $IPSEC_CONF_DIR/private/client-key.pem \
        | ipsec pki --issue --lifetime $CERT_DAYS \
            --cacert $IPSEC_CONF_DIR/cacerts/ca-cert.pem \
            --cakey $IPSEC_CONF_DIR/private/ca-key.pem \
            --dn "C=$CERT_COUNTRY, O=$CERT_ORG, CN=VPN Client" \
            --outform pem > $IPSEC_CONF_DIR/certs/client-cert.pem
    
    # Convert certificates to PKCS12 format
    log_info "Converting certificates for client use..."
    openssl pkcs12 -export \
        -inkey $IPSEC_CONF_DIR/private/client-key.pem \
        -in $IPSEC_CONF_DIR/certs/client-cert.pem \
        -certfile $IPSEC_CONF_DIR/cacerts/ca-cert.pem \
        -name "IKEv2 VPN Client" \
        -password pass: \
        -out /root/ikev2-client.p12
    
    # Create certificate files for easy download
    cp $IPSEC_CONF_DIR/cacerts/ca-cert.pem /root/ikev2-ca.crt
    cp $IPSEC_CONF_DIR/certs/client-cert.pem /root/ikev2-client.crt
    cp $IPSEC_CONF_DIR/private/client-key.pem /root/ikev2-client.key
    cp $IPSEC_CONF_DIR/certs/server-cert.pem /root/ikev2-server.crt
    
    # Create combined PEM file
    cat $IPSEC_CONF_DIR/private/client-key.pem $IPSEC_CONF_DIR/certs/client-cert.pem > /root/ikev2-client-combined.pem
    
    # Set proper permissions
    chmod 600 /root/ikev2-client.key
    chmod 644 /root/ikev2-*.crt /root/ikev2-*.p12
    
    log_info "Certificates generated successfully"
}

configure_strongswan() {
    log_info "Configuring strongSwan for IKEv2..."
    
    # Configure strongswan.conf
    cat > $STRONGSWAN_CONF << EOF
# strongswan.conf - strongSwan configuration file

charon {
    # Number of worker threads
    threads = 16
    
    # Plugins to load
    plugins {
        include strongswan.d/charon/*.conf
    }
    
    # Send strongSwan vendor ID
    send_vendor_id = yes
    
    # IKE port (default 500)
    port = 500
    
    # NAT-Traversal port
    port_nat_t = 4500
    
    # Enable MOBIKE (Mobility and Multihoming)
    mobike = yes
    
    # Maximum number of IKE_SAs (half open connections)
    ikesa_limit = 1000
    
    # Maximum number of CHILD_SAs
    childsa_limit = 1000
}

# Disable unused plugins
libtpm {
    load = no
}
EOF
    
    # Configure ipsec.conf
    cat > $IPSEC_CONF << EOF
# ipsec.conf - strongSwan IPsec configuration file

config setup
    charondebug="ike 2, knl 2, cfg 2"
    uniqueids=no
    strictcrlpolicy=no

conn %default
    ikelifetime=24h
    lifetime=8h
    rekeymargin=3m
    keyingtries=1
    rekey=yes
    dpdaction=clear
    dpddelay=300s
    dpdtimeout=30s
    compress=no

conn ikev2-cp
    left=%any
    leftid=@${CERT_CN}
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    leftfirewall=yes
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=10.10.10.0/24
    rightdns=${VPN_DNS}
    rightsendcert=never
    eap_identity=%identity
    auto=add
    fragmentation=yes
    rekey=yes