#!/bin/bash
# Hysteria 2 All-in-One Installation Script
#
# v2.6: Changed all user-facing text and comments to English to prevent parsing errors in non-UTF8 environments.
# v2.5: Changed single-line function definitions to standard multi-line format.
# v2.4: Adopted a download-to-temp-file-then-move pattern to fix "Text file busy" error.
# v2.3: Added automatic generation of standard hy2:// subscription link.
# v2.2: Added logic to stop the old service before installation.
# v2.1: Added interactive port selection.
# v2.0: Refactored download logic to fetch binary directly.

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- Global Variables ---
INSTALL_DIR="/etc/hysteria"
HY2_VERSION_TAG="app/v2.6.2"

# --- Functions ---

# Check if user is root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root. Please use 'sudo -i' and try again.${NC}"
        exit 1
    fi
}

# Get system architecture
get_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64 | amd64)
            ARCH="amd64"
            ;;
        aarch64 | arm64)
            ARCH="arm64"
            ;;
        *)
            echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo "Detected architecture: $ARCH"
}

# Install required dependencies
install_dependencies() {
    echo -e "${GREEN}--- Step 1/8: Checking and installing dependencies...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl tar openssl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl tar openssl
    else
        echo -e "${RED}Error: Could not determine package manager (apt/yum). Please install curl, tar, and openssl manually.${NC}"
        exit 1
    fi
}

# URL-encode a string
url_encode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Main setup logic for Hysteria 2
setup_hysteria() {
    echo -e "${GREEN}--- Step 2/8: Port Configuration ---${NC}"
    read -rp "Please enter the port you want to use (443 is recommended, use 1024-65535 if it fails) [Default: 443]: " USER_PORT
    USER_PORT=${USER_PORT:-443}
    if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
        echo -e "${RED}Error: Invalid port number. Please enter a number between 1-65535.${NC}"; exit 1
    fi
    echo "Using port: ${USER_PORT}"

    echo -e "${GREEN}--- Step 3/8: Downloading Hysteria 2 (Version: ${HY2_VERSION_TAG}) ---${NC}"
    mkdir -p $INSTALL_DIR
    URL_ENCODED_VERSION_TAG="${HY2_VERSION_TAG//\//%2F}"
    ASSET_NAME="hysteria-linux-${ARCH}"
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${URL_ENCODED_VERSION_TAG}/${ASSET_NAME}"
    
    HYSTERIA_TMP_PATH="/tmp/hysteria.new"
    echo "Downloading from $DOWNLOAD_URL to temporary file ${HYSTERIA_TMP_PATH}..."
    curl -Lf -o "${HYSTERIA_TMP_PATH}" "$DOWNLOAD_URL"
    echo "Download complete."
    
    echo -e "${GREEN}--- Step 4/8: Stopping old service and replacing binary ---${NC}"
    systemctl stop hysteria.service >/dev/null 2>&1 || true
    pkill -f "hysteria server" >/dev/null 2>&1 || true
    sleep 1
    
    echo "Moving new binary to installation directory..."
    mv "${HYSTERIA_TMP_PATH}" "${INSTALL_DIR}/hysteria"
    chmod +x "${INSTALL_DIR}/hysteria"
    echo "Binary replaced and installed successfully."

    echo -e "${GREEN}--- Step 5/8: Generating self-signed certificate and config file ---${NC}"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${INSTALL_DIR}/server.key" -out "${INSTALL_DIR}/server.crt" -subj "/CN=bing.com" -days 3650
    read -rp "Please enter your connection password (leave blank for a random one): " USER_PASSWORD; [ -z "${USER_PASSWORD}" ] && USER_PASSWORD=$(openssl rand -base64 16);
    cat > "${INSTALL_DIR}/config.yaml" <<EOF
listen: :${USER_PORT}
tls:
  cert: ${INSTALL_DIR}/server.crt
  key: ${INSTALL_DIR}/server.key
auth:
  type: password
  password: ${USER_PASSWORD}
congestion_control:
  type: bbr
bandwidth:
  up: 100 mbps
  down: 500 mbps
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

    echo -e "${GREEN}--- Step 6/8: Setting up Systemd service ---${NC}"
    cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria 2 Service (managed by script)
After=network.target
[Service]
Type=simple
ExecStart=${INSTALL_DIR}/hysteria server -c ${INSTALL_DIR}/config.yaml
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    echo "Reloading, enabling, and starting service..."; systemctl daemon-reload; systemctl enable hysteria.service; systemctl restart hysteria.service

    echo -e "${GREEN}--- Step 7/8: Configuring firewall ---${NC}"
    if command -v ufw >/dev/null 2>&1; then ufw allow ${USER_PORT}/udp >/dev/null 2>&1 || true; fi
    if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=${USER_PORT}/udp --permanent >/dev/null 2>&1 || true && firewall-cmd --reload >/dev/null 2>&1 || true; fi

    echo -e "${GREEN}--- Step 8/8: Generating final connection info ---${NC}"; PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com); clear
    ENCODED_PASSWORD=$(url_encode "${USER_PASSWORD}")
    NODE_NAME="Hysteria-Node-$(date +%s)"
    HY2_URI="hy2://${ENCODED_PASSWORD}@${PUBLIC_IP}:${USER_PORT}/?insecure=1&sni=bing.com#${NODE_NAME}"

    echo -e "========================================================================"
    echo -e "${GREEN}✅ Hysteria 2 has been installed and started successfully!${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "   Your client connection details are as follows:"
    echo -e "   ${YELLOW}Address:      ${PUBLIC_IP}${NC}"
    echo -e "   ${YELLOW}Port:         ${USER_PORT}${NC}"
    echo -e "   ${YELLOW}Password:     ${USER_PASSWORD}${NC}"
    echo -e "   ${YELLOW}SNI:          bing.com${NC}"
    echo -e "   ${YELLOW}Skip Cert Verify: true${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "   ${GREEN}>>> Subscription URI (copy and import to your client) <<<${NC}"
    echo -e "   ${YELLOW}${HY2_URI}${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "Hint: You can check the service status with 'systemctl status hysteria'."
    echo -e "========================================================================"
}

# --- Main Logic ---
clear
echo -e "${YELLOW}Welcome to the Hysteria 2 All-in-One Installation Script.${NC}"
check_root
get_arch
install_dependencies
