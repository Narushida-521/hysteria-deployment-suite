#!/bin/bash

# ==============================================================================
# Hysteria 2 (hy2) All-in-One Deployment Script (v3 - Final Fix)
#
# 更新日志:
# - 修复了下载逻辑，确保精确下载 Hysteria v2 版本，避免错下 v1。
# - 增加了 'set -e'，任何命令出错时脚本将立即停止，防止错误继续执行。
# ==============================================================================

# --- 脚本设置 ---
# 如果任何命令失败，则立即退出
set -e

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 静态变量 ---
CONFIG_PATH="/etc/hysteria/config.yaml"
SERVICE_PATH="/etc/systemd/system/hysteria.service"
CERT_PATH="/etc/hysteria/cert.pem"
KEY_PATH="/etc/hysteria/key.pem"
HYSTERIA_BIN="/usr/local/bin/hysteria"

# --- 辅助函数 ---
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# --- 脚本主要功能函数 ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
}

install_dependencies() {
    print_message "$YELLOW" "正在检查并安装依赖 (curl, jq, iproute2)..."
    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null || ! command -v ss &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y curl jq iproute2
        elif command -v yum &>/dev/null; then
            yum install -y curl jq iproute
        elif command -v dnf &>/dev/null; then
            dnf install -y curl jq iproute
        else
            print_message "$RED" "无法确定包管理器。请手动安装 'curl', 'jq' 和 'iproute2'。"
            exit 1
        fi
    fi
}

get_server_ip() {
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    if [ -z "$SERVER_IP" ]; then
        print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
    fi
}

# --- V3 更新：修复下载逻辑 ---
install_hysteria() {
    print_message "$YELLOW" "正在查找并安装 Hysteria 2 最新版本..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
    esac

    # 精确查找最新的 Hysteria 2 版本
    LATEST_V2_TAG=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases" | \
        jq -r '[.[] | select(.tag_name | startswith("app/v2."))] | .[0].tag_name')

    if [ -z "$LATEST_V2_TAG" ] || [ "$LATEST_V2_TAG" == "null" ]; then
        print_message "$RED" "无法找到最新的 Hysteria 2 版本号。"
        print_message "$YELLOW" "这可能是 GitHub API 访问问题。请稍后重试。"
        exit 1
    fi

    print_message "$GREEN" "找到最新的 Hysteria 2 版本: $LATEST_V2_TAG"
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_V2_TAG}/hysteria-linux-${ARCH}"
    
    print_message "$YELLOW" "正在从 $DOWNLOAD_URL 下载..."
    curl -L -o "$HYSTERIA_BIN" "$DOWNLOAD_URL"
    chmod +x "$HYSTERIA_BIN"
    
    # 验证下载的二进制文件
    HYSTERIA_VERSION=$($HYSTERIA_BIN --version)
    if [[ ! "$HYSTERIA_VERSION" == *"Hysteria 2"* ]]; then
        print_message "$RED" "下载的二进制文件不是 Hysteria 2！安装失败。"
        exit 1
    fi
    
    print_message "$GREEN" "Hysteria 2 安装成功！版本：$($HYSTERIA_BIN --version | head -n 1)"
}

is_port_in_use() {
    local port=$1
    if ss -tulpn | grep -q ":${port}\b"; then return 0; else return 1; fi
}

configure_hysteria() {
    print_message "$YELLOW" "开始配置 Hysteria 2..."
    
    DEFAULT_PORT=$((RANDOM % 45536 + 20000))
    while is_port_in_use "$DEFAULT_PORT"; do
        DEFAULT_PORT=$((RANDOM % 45536 + 20000))
    done

    read -p "请输入 Hysteria 2 的监听端口 [默认: $DEFAULT_PORT]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-$DEFAULT_PORT}

    if is_port_in_use "$LISTEN_PORT"; then
        print_message "$RED" "错误：端口 $LISTEN_PORT 已被占用。"; exit 1
    fi

    DEFAULT_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    read -p "请输入连接密码 (obfs) [默认: 随机生成]: " OBFS_PASSWORD
    OBFS_PASSWORD=${OBFS_PASSWORD:-$DEFAULT_PASSWORD}

    mkdir -p /etc/hysteria
    print_message "$YELLOW" "正在为 $SERVER_IP 生成自签名证书..."
    $HYSTERIA_BIN cert --self-signed --host "$SERVER_IP" --out "$CERT_PATH" --key "$KEY_PATH"
    
    print_message "$YELLOW" "正在创建配置文件: $CONFIG_PATH"
    cat > "$CONFIG_PATH" <<EOF
server:
  listen: :$LISTEN_PORT
  tls:
    cert: $CERT_PATH
    key: $KEY_PATH
  
auth:
  type: password
  password: $OBFS_PASSWORD
EOF
}

setup_systemd_service() {
    print_message "$YELLOW" "正在设置 Systemd 服务..."
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server --config $CONFIG_PATH
WorkingDirectory=/etc/hysteria
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria
}

configure_firewall() {
    print_message "$YELLOW" "正在配置防火墙..."
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp
        firewall-cmd --reload
        print_message "$GREEN" "Firewalld: 已开放端口 ${LISTEN_PORT}/udp"
    elif command -v ufw &>/dev/null; then
        ufw allow ${LISTEN_PORT}/udp >/dev/null
        print_message "$GREEN" "UFW: 已开放端口 ${LISTEN_PORT}/udp"
    else
        print_message "$YELLOW" "未检测到 firewalld 或 ufw。请手动开放 UDP 端口: $LISTEN_PORT"
        print_message "$YELLOW" "如果您的服务器商有外部防火墙 (安全组), 请务必手动放行该 UDP 端口。"
    fi
}

start_and_display_results() {
    print_message "$YELLOW" "正在启动 Hysteria 2 服务..."
    systemctl restart hysteria
    sleep 2
    
    if ! systemctl is-active --quiet hysteria; then
        print_message "$RED" "Hysteria 2 服务启动失败！"
        print_message "$YELLOW" "请检查日志获取详细错误信息: journalctl -u hysteria --no-pager -n 50"
        exit 1
    fi
    
    SHARE_LINK="hy2://$OBFS_PASSWORD@$SERVER_IP:$LISTEN_PORT?insecure=1&sni=$SERVER_IP"

    print_message "$GREEN" "=================================================================="
    print_message "$GREEN" " Hysteria 2 已部署完成！"
    print_message "$GREEN" "=================================================================="
    print_message "$YELLOW" "服务器地址:      ${SERVER_IP}"
    print_message "$YELLOW" "服务器端口:      ${LISTEN_PORT}"
    print_message "$YELLOW" "连接密码 (obfs): ${OBFS_PASSWORD}"
    print_message "$NC"     "------------------------------------------------------------------"
    print_message "$YELLOW" "分享链接 (可直接导入 V2rayN / NekoBox 等客户端):"
    print_message "$GREEN"  "$SHARE_LINK"
    print_message "$NC"     "------------------------------------------------------------------"
    print_message "$YELLOW" "管理命令:"
    print_message "$NC"     "查看状态: systemctl status hysteria"
    print_message "$NC"     "查看日志: journalctl -u hysteria"
    print_message "$NC"     "配置文件: $CONFIG_PATH"
    print_message "$GREEN" "=================================================================="
}

# --- 主执行流程 ---
main() {
    check_root
    # 清理旧的安装 (如果存在)
    systemctl stop hysteria >/dev/null 2>&1 || true
    rm -f "$HYSTERIA_BIN" "$SERVICE_PATH"
    
    install_dependencies
    get_server_ip
    install_hysteria
    configure_hysteria
    setup_systemd_service
    configure_firewall
    start_and_display_results
}

main
