#!/bin/bash

# ==============================================================================
# Hysteria 2 (hy2) All-in-One Deployment Script (v16 - Final Memory Optimization)
#
# 特点:
# - [核心] 完全移除 Swap 相关操作，以兼容不允许 Swap 的 OpenVZ/LXC 环境。
# - [核心] 极致优化 apt-get 命令，最大限度减少内存消耗。
# - [核心] 对依赖安装结果进行检查，如果失败则明确提示。
# - 完全移除对 systemd 的依赖，使用 nohup 管理进程。
# - 使用最终正确格式的 hysteria2:// 订阅链接。
# - 内置调试模式 (`set -ex`)。
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
CERT_PATH="/etc/hysteria/cert.pem"
KEY_PATH="/etc/hysteria/key.pem"
HYSTERIA_BIN="/usr/local/bin/hysteria"
HYSTERIA_LOG="/tmp/hysteria.log"

# --- 辅助函数 ---
print_message() {
    local color=$1
    local message=$2
    echo "=================================================================="
    echo -e "${color}${message}${NC}"
    echo "=================================================================="
}

# --- 主执行流程 ---
main() {
    print_message "$YELLOW" "开始执行脚本，当前用户: $(whoami)"
    
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
    print_message "$GREEN" "Root 权限检查通过。"
    
    # 清理旧的安装
    print_message "$YELLOW" "正在停止任何旧的 Hysteria 进程..."
    pkill -f "$HYSTERIA_BIN" || true
    rm -f "$HYSTERIA_BIN" "$CONFIG_PATH" "$CERT_PATH" "$KEY_PATH"
    print_message "$GREEN" "旧文件和进程清理完毕。"

    # 安装依赖
    print_message "$YELLOW" "正在检查并安装依赖 (curl, jq, iproute2, openssl, coreutils)..."
    if command -v apt-get &>/dev/null; then
        # 极致优化 apt-get 操作以减少内存和磁盘占用
        apt-get update -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false
        apt-get install -y --no-install-recommends curl jq iproute2 openssl coreutils
        apt-get clean
        rm -rf /var/lib/apt/lists/*
    elif command -v yum &>/dev/null; then
        yum install -y curl jq iproute openssl coreutils
        yum clean all
    elif command -v dnf &>/dev/null; then
        dnf install -y curl jq iproute openssl coreutils
        dnf clean all
    else
        print_message "$RED" "无法确定包管理器，请手动安装 'curl', 'jq', 'iproute2', 'openssl', 'coreutils'。"
        exit 1
    fi
    
    # 检查依赖是否真的安装成功
    for cmd in curl jq ip openssl; do
        if ! command -v "$cmd" &>/dev/null; then
            print_message "$RED" "致命错误：依赖 '$cmd' 未能成功安装，很可能是内存不足导致。安装无法继续。"
            exit 1
        fi
    done
    print_message "$GREEN" "依赖安装成功。"

    # 获取服务器IP
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    if [ -z "$SERVER_IP" ]; then
        print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
    fi
    print_message "$GREEN" "获取到公网 IP: $SERVER_IP"

    # 安装 Hysteria
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
    esac
    LATEST_V2_TAG=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases" | jq -r '[.[] | select(.tag_name | startswith("app/v2."))] | .[0].tag_name')
    if [ -z "$LATEST_V2_TAG" ] || [ "$LATEST_V2_TAG" == "null" ]; then
        print_message "$RED" "无法找到最新的 Hysteria 2 版本号。"; exit 1
    fi
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_V2_TAG}/hysteria-linux-${ARCH}"
    print_message "$YELLOW" "正在从 $DOWNLOAD_URL 下载..."
    curl -L -o "$HYSTERIA_BIN" "$DOWNLOAD_URL"
    chmod +x "$HYSTERIA_BIN"
    "$HYSTERIA_BIN" version
    print_message "$GREEN" "Hysteria 2 安装和验证成功。"

    # 配置 Hysteria
    LISTEN_PORT=35888
    OBFS_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    mkdir -p /etc/hysteria
    print_message "$YELLOW" "正在使用 openssl 生成自签名证书..."
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=bing.com" -days 3650
    print_message "$YELLOW" "正在创建配置文件..."
    cat > "$CONFIG_PATH" <<EOF
listen: :$LISTEN_PORT
tls:
  cert: $CERT_PATH
  key: $KEY_PATH
obfs:
  type: password
  password: $OBFS_PASSWORD
EOF
    print_message "$GREEN" "配置完成。"

    # 配置防火墙
    print_message "$YELLOW" "正在配置防火墙..."
    if command -v ufw &>/dev/null; then
        ufw allow "${LISTEN_PORT}/udp" >/dev/null
    else
        print_message "$YELLOW" "未检测到 ufw，请手动开放端口 ${LISTEN_PORT}/udp。"
    fi
    print_message "$GREEN" "防火墙配置完毕。"

    # 启动并诊断 (非 Systemd 方式)
    print_message "$YELLOW" "正在使用 nohup 启动 Hysteria 2 服务..."
    pkill -f "$HYSTERIA_BIN" || true
    nohup "$HYSTERIA_BIN" server -c "$CONFIG_PATH" > "$HYSTERIA_LOG" 2>&1 &
    sleep 3
    
    set +e
    print_message "$GREEN" "脚本执行完毕。下面是最终的诊断和配置信息。"
    
    print_message "$YELLOW" "诊断 1: 检查进程状态 (ps)"
    if pgrep -f "$HYSTERIA_BIN"; then
        print_message "$GREEN" "Hysteria 进程正在运行。"
    else
        print_message "$RED" "警告: 未发现 Hysteria 进程在运行。"
    fi

    print_message "$YELLOW" "诊断 2: 检查服务日志"
    tail -n 20 "$HYSTERIA_LOG"
    
    print_message "$YELLOW" "诊断 3: 检查端口监听 (ss)"
    if ! ss -ulpn | grep -q ":$LISTEN_PORT"; then
        print_message "$RED" "警告: 未发现程序在监听端口 $LISTEN_PORT"
    else
        print_message "$GREEN" "端口 $LISTEN_PORT 监听正常。"
    fi
    
    print_message "$GREEN" "所有诊断步骤已完成。"
    
    # 生成订阅链接
    SNI_HOST="bing.com"
    NODE_TAG="Hysteria-Node"
    SUBSCRIPTION_LINK="hysteria2://${OBFS_PASSWORD}@${SERVER_IP}:${LISTEN_PORT}?sni=${SNI_HOST}&insecure=1#${NODE_TAG}"

    print_message "$YELLOW" "您的 Hysteria 2 配置信息:"
    echo -e "${GREEN}服务器地址: ${NC}$SERVER_IP"
    echo -e "${GREEN}端口:       ${NC}$LISTEN_PORT"
    echo -e "${GREEN}密码:       ${NC}$OBFS_PASSWORD"
    echo -e "${GREEN}SNI/主机名: ${NC}${SNI_HOST}"
    echo -e "${GREEN}跳过证书验证: ${NC}true"

    print_message "$YELLOW" "您的客户端订阅链接 (hysteria2://):"
    echo "$SUBSCRIPTION_LINK"
}

main
