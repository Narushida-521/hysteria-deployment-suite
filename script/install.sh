#!/bin/bash

# ==============================================================================
# Hysteria 2 (hy2) All-in-One Deployment Script (v9 - Guaranteed Output)
#
# 特点:
# - 已修正 Hysteria 2 的兼容性问题。
# - 使用 openssl 生成证书，替代已被移除的 `hysteria cert` 命令。
# - 生成 Hysteria 2 的正确配置文件格式。
# - 脚本结束时自动生成清晰的配置详情和订阅链接。
# - 在最终诊断阶段禁用 "exit on error"，确保配置信息和链接总是能显示。
# - 内置调试模式 (`set -ex`)，会打印所有执行的命令和结果。
# - 在关键步骤增加明确的输出信息。
# - 脚本结束时自动运行诊断命令，收集所有必要信息。
# ==============================================================================

# --- 脚本设置 ---
# 如果任何命令失败，则立即退出 (e)
# 打印所有执行的命令到终端 (x)
set -ex

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
    # 在调试模式下，让输出更显眼
    echo "=================================================================="
    echo -e "${color}${message}${NC}"
    echo "=================================================================="
}

# --- 主执行流程 ---
main() {
    print_message "$YELLOW" "开始执行脚本，当前用户: $(whoami)"
    
    # 1. 检查 Root 权限
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
    print_message "$GREEN" "Root 权限检查通过。"

    # 清理旧的安装 (如果存在)
    print_message "$YELLOW" "正在停止并清理任何旧的 Hysteria 服务..."
    systemctl stop hysteria >/dev/null 2>&1 || true
    rm -f "$HYSTERIA_BIN" "$SERVICE_PATH" /etc/hysteria/config.yaml
    print_message "$GREEN" "旧文件清理完毕。"

    # 2. 安装依赖
    print_message "$YELLOW" "正在检查并安装依赖 (curl, jq, iproute2, openssl, coreutils)..."
    if command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y curl jq iproute2 openssl coreutils
    elif command -v yum &>/dev/null; then
        yum install -y curl jq iproute openssl coreutils
    elif command -v dnf &>/dev/null; then
        dnf install -y curl jq iproute openssl coreutils
    else
        print_message "$RED" "无法确定包管理器。请手动安装 'curl', 'jq', 'iproute2', 'openssl', 'coreutils'。"
        exit 1
    fi
    print_message "$GREEN" "依赖安装完毕。"

    # 3. 获取服务器IP
    print_message "$YELLOW" "正在获取公网 IP..."
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    if [ -z "$SERVER_IP" ]; then
        print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
    fi
    print_message "$GREEN" "获取到公网 IP: $SERVER_IP"

    # 4. 安装 Hysteria
    print_message "$YELLOW" "正在查找并安装 Hysteria 2 最新版本..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
    esac

    LATEST_V2_TAG=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases" | \
        jq -r '[.[] | select(.tag_name | startswith("app/v2."))] | .[0].tag_name')

    if [ -z "$LATEST_V2_TAG" ] || [ "$LATEST_V2_TAG" == "null" ]; then
        print_message "$RED" "无法找到最新的 Hysteria 2 版本号。"; exit 1
    fi

    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_V2_TAG}/hysteria-linux-${ARCH}"
    
    print_message "$YELLOW" "正在从 $DOWNLOAD_URL 下载..."
    curl -L -o "$HYSTERIA_BIN" "$DOWNLOAD_URL"
    chmod +x "$HYSTERIA_BIN"
    
    print_message "$YELLOW" "正在验证 Hysteria 版本..."
    $HYSTERIA_BIN version
    print_message "$GREEN" "Hysteria 2 安装和验证成功。"

    # 5. 配置 Hysteria
    print_message "$YELLOW" "开始配置 Hysteria 2..."
    LISTEN_PORT=35888 # 使用一个固定的端口进行测试，避免随机性问题
    OBFS_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16) # 随机生成密码
    
    mkdir -p /etc/hysteria

    # --- 使用 openssl 替代旧的 cert 命令 ---
    print_message "$YELLOW" "正在使用 openssl 生成自签名证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=bing.com" -days 3650
    
    # --- 使用 Hysteria 2 的正确配置格式 ---
    print_message "$YELLOW" "正在创建配置文件..."
    cat > "$CONFIG_PATH" <<EOF
# 监听端口
listen: :$LISTEN_PORT

# TLS 证书配置
tls:
  cert: $CERT_PATH
  key: $KEY_PATH

# 混淆密码
obfs:
  type: password
  password: $OBFS_PASSWORD
EOF
    
    print_message "$GREEN" "配置完成。"

    # 6. 设置 Systemd 服务
    print_message "$YELLOW" "正在设置 Systemd 服务..."
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $CONFIG_PATH
WorkingDirectory=/etc/hysteria
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hysteria
    print_message "$GREEN" "Systemd 服务设置完毕。"

    # 7. 配置防火墙
    print_message "$YELLOW" "正在配置防火墙..."
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port=${LISTEN_PORT}/udp
        firewall-cmd --reload
    elif command -v ufw &>/dev/null; then
        ufw allow ${LISTEN_PORT}/udp >/dev/null
    else
        print_message "$YELLOW" "未检测到 firewalld 或 ufw。"
    fi
    print_message "$GREEN" "防火墙配置完毕。"

    # 8. 启动并进行最终诊断
    print_message "$YELLOW" "正在启动 Hysteria 2 服务..."
    systemctl restart hysteria
    sleep 3 # 等待3秒让服务有时间启动或失败
    
    # --- FIX START: 临时禁用 "exit on error" 以确保诊断和配置信息总是能显示 ---
    set +e
    
    print_message "$GREEN" "脚本执行完毕。下面是最终的诊断和配置信息。"
    
    # 自动诊断
    print_message "$YELLOW" "诊断 1: 检查服务状态 (systemctl status)"
    systemctl status hysteria --no-pager
    
    print_message "$YELLOW" "诊断 2: 检查服务日志 (journalctl)"
    journalctl -u hysteria -n 20 --no-pager
    
    print_message "$YELLOW" "诊断 3: 检查端口监听 (ss)"
    if ! ss -ulpn | grep -q ":$LISTEN_PORT"; then
        print_message "$RED" "警告: 未发现程序在监听端口 $LISTEN_PORT"
    else
        print_message "$GREEN" "端口 $LISTEN_PORT 监听正常。"
    fi
    
    print_message "$GREEN" "所有诊断步骤已完成。"
    
    # --- 输出详细配置信息和订阅链接 ---
    CLIENT_JSON=$(cat <<EOF
{
  "server": "$SERVER_IP:$LISTEN_PORT",
  "obfs": {
    "type": "password",
    "password": "$OBFS_PASSWORD"
  },
  "tls": {
    "insecure": true,
    "sni": "bing.com"
  }
}
EOF
)
    BASE64_CONFIG=$(echo "$CLIENT_JSON" | base64 -w 0)
    SUBSCRIPTION_LINK="hy2://${BASE64_CONFIG}"

    print_message "$YELLOW" "您的 Hysteria 2 配置信息:"
    echo -e "${GREEN}服务器地址: ${NC}$SERVER_IP"
    echo -e "${GREEN}端口:       ${NC}$LISTEN_PORT"
    echo -e "${GREEN}密码:       ${NC}$OBFS_PASSWORD"
    echo -e "${GREEN}SNI/主机名: ${NC}bing.com"
    echo -e "${GREEN}跳过证书验证: ${NC}true"

    print_message "$YELLOW" "您的客户端订阅链接 (hy2://):"
    echo "$SUBSCRIPTION_LINK"
    # --- FIX END ---
}

# --- 运行主函数 ---
main
