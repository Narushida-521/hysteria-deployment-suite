#!/bin/bash

# ==============================================================================
# Hysteria 2 (hy2) All-in-One Deployment Script
#
# 功能:
# 1. 自动检测系统并安装依赖 (curl, jq)
# 2. 下载并安装最新的 Hysteria 2 二进制文件
# 3. 交互式地获取用户配置 (端口, 密码)
# 4. 自动为服务器 IP 生成自签名证书
# 5. 创建完整的服务器配置文件 (config.yaml)
# 6. 设置 Systemd 服务，用于进程管理和开机自启
# 7. 自动检测并配置防火墙 (firewalld, ufw)
# 8. 启动服务并验证运行状态
# 9. 清晰地显示客户端连接信息和分享链接
# ==============================================================================

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

# 1. 检查 Root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        print_message "$YELLOW" "请尝试使用 'sudo ./install.sh' 命令运行。"
        exit 1
    fi
}

# 2. 安装依赖
install_dependencies() {
    print_message "$YELLOW" "正在检查并安装依赖 (curl, jq)..."
    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y curl jq
        elif command -v yum &>/dev/null; then
            yum install -y curl jq
        elif command -v dnf &>/dev/null; then
            dnf install -y curl jq
        else
            print_message "$RED" "无法确定包管理器。请手动安装 'curl' 和 'jq'。"
            exit 1
        fi
    fi
}

# 3. 获取服务器公网 IP
get_server_ip() {
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    if [ -z "$SERVER_IP" ]; then
        print_message "$RED" "无法自动获取服务器公网 IP 地址。"
        read -p "请输入您的服务器公网 IP: " SERVER_IP
        if [ -z "$SERVER_IP" ]; then
            print_message "$RED" "未提供 IP 地址，脚本终止。"
            exit 1
        fi
    fi
}

# 4. 安装 Hysteria 2 程序
install_hysteria() {
    print_message "$YELLOW" "正在安装 Hysteria 2..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            print_message "$RED" "不支持的架构: $ARCH"
            exit 1
            ;;
    esac

    LATEST_TAG=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | jq -r '.tag_name')
    if [ -z "$LATEST_TAG" ]; then
        print_message "$RED" "无法获取最新的 Hysteria 2 版本号。"
        exit 1
    fi

    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_TAG}/hysteria-linux-${ARCH}"
    
    print_message "$YELLOW" "正在从 $DOWNLOAD_URL 下载..."
    if ! curl -L -o "$HYSTERIA_BIN" "$DOWNLOAD_URL"; then
        print_message "$RED" "下载失败！"
        exit 1
    fi
    chmod +x "$HYSTERIA_BIN"
    print_message "$GREEN" "Hysteria 2 安装成功！版本：$($HYSTERIA_BIN --version | head -n 1)"
}

# 5. 配置 Hysteria 2 参数
configure_hysteria() {
    print_message "$YELLOW" "开始配置 Hysteria 2..."
    
    # 询问端口
    DEFAULT_PORT=$(shuf -i 20000-60000 -n 1)
    read -p "请输入 Hysteria 2 的监听端口 [默认: $DEFAULT_PORT]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-$DEFAULT_PORT}

    # 询问密码
    DEFAULT_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    read -p "请输入连接密码 (obfs) [默认: 随机生成]: " OBFS_PASSWORD
    OBFS_PASSWORD=${OBFS_PASSWORD:-$DEFAULT_PASSWORD}

    # 创建配置目录
    mkdir -p /etc/hysteria

    # 生成自签名证书
    print_message "$YELLOW" "正在为 $SERVER_IP 生成自签名证书..."
    $HYSTERIA_BIN cert --self-signed --host "$SERVER_IP" --out "$CERT_PATH" --key "$KEY_PATH"
    
    # 创建配置文件
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

# 6. 设置 Systemd 服务
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

# 7. 配置防火墙
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
    fi
}

# 8. 启动服务并显示结果
start_and_display_results() {
    print_message "$YELLOW" "正在启动 Hysteria 2 服务..."
    systemctl restart hysteria
    sleep 2
    
    # 检查服务状态
    if ! systemctl is-active --quiet hysteria; then
        print_message "$RED" "Hysteria 2 服务启动失败！请检查日志："
        journalctl -u hysteria --no-pager -n 50
        exit 1
    fi
    
    # 生成客户端配置和分享链接
    CLIENT_CONFIG=$(cat <<EOF
# 客户端配置文件 (config.yaml)
server: $SERVER_IP:$LISTEN_PORT
auth:
  type: password
  password: $OBFS_PASSWORD

tls:
  insecure: true # 因为我们用的是自签名证书
  # 或者使用 sni 来验证
  # sni: $SERVER_IP
EOF
)
    SHARE_LINK="hy2://$OBFS_PASSWORD@$SERVER_IP:$LISTEN_PORT?insecure=1&sni=$SERVER_IP"

    # 显示所有信息
    print_message "$GREEN" "=================================================================="
    print_message "$GREEN" " Hysteria 2 已部署完成！"
    print_message "$GREEN" "=================================================================="
    print_message "$YELLOW" "服务器地址:      ${SERVER_IP}"
    print_message "$YELLOW" "服务器端口:      ${LISTEN_PORT}"
    print_message "$YELLOW" "连接密码 (obfs): ${OBFS_PASSWORD}"
    print_message "$NC"     "------------------------------------------------------------------"
    print_message "$YELLOW" "V2rayN / NekoBox 等客户端支持的分享链接:"
    print_message "$GREEN"  "$SHARE_LINK"
    print_message "$NC"     "------------------------------------------------------------------"
    print_message "$YELLOW" "通用客户端配置文件 (config.yaml):"
    echo -e "${GREEN}$CLIENT_CONFIG${NC}"
    print_message "$NC"     "------------------------------------------------------------------"
    print_message "$YELLOW" "管理命令:"
    print_message "$NC"     "启动服务: systemctl start hysteria"
    print_message "$NC"     "停止服务: systemctl stop hysteria"
    print_message "$NC"     "查看状态: systemctl status hysteria"
    print_message "$NC"     "查看日志: journalctl -u hysteria"
    print_message "$NC"     "配置文件: $CONFIG_PATH"
    print_message "$GREEN" "=================================================================="
}

# --- 主执行流程 ---
main() {
    check_root
    install_dependencies
    get_server_ip
    install_hysteria
    configure_hysteria
    setup_systemd_service
    configure_firewall
    start_and_display_results
}

# 运行主函数
main
