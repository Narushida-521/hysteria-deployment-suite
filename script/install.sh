#!/bin/bash

# ==============================================================================
# Hysteria 2 Ultimate All-in-One Deployment Script (v17 - Final Compatibility)
#
# 特点:
# - [终极] 专为极低内存 (64MB)、无 Swap、非 Systemd (OpenVZ/LXC) 等特殊环境设计。
# - [核心] 绝不尝试安装任何依赖，只检查核心工具是否存在，从根源避免内存耗尽。
# - [核心] 所有文件均安装在 /root/.hysteria2 目录，不触碰任何系统目录，兼容性最强。
# - [核心] 使用 nohup 和 pkill 管理后台进程，不依赖任何特定 init 系统。
# - [核心] 提供卸载和日志查看功能，方便管理。
# ==============================================================================

# --- 脚本设置 ---
# 如果任何命令失败，则立即退出 (e)
# 如果变量未定义，则视为错误 (u)
# 打印所有执行的命令到终端 (x)
set -eux

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- 静态变量 ---
INSTALL_DIR="/root/.hysteria2"
CONFIG_PATH="${INSTALL_DIR}/config.yaml"
CERT_PATH="${INSTALL_DIR}/server.crt"
KEY_PATH="${INSTALL_DIR}/server.key"
HYSTERIA_BIN="${INSTALL_DIR}/hysteria"
HYSTERIA_LOG="${INSTALL_DIR}/hysteria.log"

# --- 辅助函数 ---
print_message() {
    local color=$1
    local message=$2
    echo -e "\n${color}==================================================================${NC}"
    echo -e "${color}${message}${NC}"
    echo -e "${color}==================================================================${NC}\n"
}

# --- 卸载函数 ---
uninstall() {
    print_message "$YELLOW" "正在卸载 Hysteria 2..."
    # 停止进程
    pkill -f "$HYSTERIA_BIN" || true
    # 删除安装目录
    rm -rf "$INSTALL_DIR"
    print_message "$GREEN" "Hysteria 2 卸载完成。"
    exit 0
}

# --- 日志函数 ---
show_logs() {
    print_message "$YELLOW" "正在显示 Hysteria 2 日志..."
    if [ -f "$HYSTERIA_LOG" ]; then
        tail -n 50 "$HYSTERIA_LOG"
    else
        print_message "$RED" "错误：日志文件不存在。"
    fi
    exit 0
}

# --- 主执行流程 ---

# 处理命令行参数 (uninstall, logs)
if [ "$#" -gt 0 ]; then
    case "$1" in
        uninstall|del|remove)
            uninstall
            ;;
        log|logs)
            show_logs
            ;;
        *)
            print_message "$RED" "未知参数: $1. 可用参数: uninstall, logs"
            exit 1
            ;;
    esac
fi

print_message "$YELLOW" "开始 Hysteria 2 终极部署脚本..."

# 1. 检查环境
print_message "$YELLOW" "步骤 1: 检查环境..."
if [ "$(id -u)" -ne 0 ]; then
    print_message "$RED" "错误：此脚本必须以 root 权限运行。"
    exit 1
fi

for cmd in curl openssl tr head; do
    if ! command -v "$cmd" &>/dev/null; then
        print_message "$RED" "致命错误：核心命令 '$cmd' 不存在。您的系统过于精简，无法继续安装。"
        exit 1
    fi
done
print_message "$GREEN" "环境检查通过。"

# 2. 清理旧的安装
print_message "$YELLOW" "步骤 2: 清理旧的 Hysteria 2 安装..."
pkill -f "$HYSTERIA_BIN" || true
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
print_message "$GREEN" "旧文件和进程清理完毕。"

# 3. 获取服务器IP
print_message "$YELLOW" "步骤 3: 获取公网 IP..."
SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
fi
print_message "$GREEN" "获取到公网 IP: $SERVER_IP"

# 4. 安装 Hysteria
print_message "$YELLOW" "步骤 4: 安装 Hysteria 2..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
esac
# 直接从 GitHub 下载最新版本
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep "browser_download_url.*hysteria-linux-${ARCH}" | cut -d : -f 2,3 | tr -d \" | head -n 1)
if [ -z "$DOWNLOAD_URL" ]; then
    print_message "$RED" "无法找到最新的 Hysteria 2 下载链接。"; exit 1
fi
print_message "$YELLOW" "正在从 $DOWNLOAD_URL 下载..."
if ! curl -L -o "$HYSTERIA_BIN" "$DOWNLOAD_URL"; then
    print_message "$RED" "下载失败，请检查网络连接或 GitHub 访问。"; exit 1
fi
chmod +x "$HYSTERIA_BIN"
"$HYSTERIA_BIN" version
print_message "$GREEN" "Hysteria 2 安装和验证成功。"

# 5. 配置 Hysteria
print_message "$YELLOW" "步骤 5: 配置 Hysteria 2..."
LISTEN_PORT=35888
OBFS_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
print_message "$YELLOW" "正在生成自签名证书..."
if ! openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=bing.com" -days 3650; then
    print_message "$RED" "生成证书失败。"; exit 1
fi
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

# 6. 启动 Hysteria
print_message "$YELLOW" "步骤 6: 启动 Hysteria 2 服务..."
# 使用 nohup 在后台启动
nohup "$HYSTERIA_BIN" server -c "$CONFIG_PATH" > "$HYSTERIA_LOG" 2>&1 &
sleep 3
print_message "$GREEN" "启动命令已发送。"

# 7. 最终诊断和输出
print_message "$YELLOW" "步骤 7: 最终诊断和输出配置..."
set +e # 临时禁用 "exit on error"
if pgrep -f "$HYSTERIA_BIN"; then
    print_message "$GREEN" "诊断成功: Hysteria 进程正在运行。"
else
    print_message "$RED" "诊断失败: 未发现 Hysteria 进程在运行。"
    print_message "$YELLOW" "请查看日志获取错误信息: tail -n 50 $HYSTERIA_LOG"
fi

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

print_message "$GREEN" "部署完成！"
echo -e "您可以使用以下命令管理服务:"
echo -e "${YELLOW}查看日志:   bash $0 logs${NC}"
echo -e "${YELLOW}卸载服务:   bash $0 uninstall${NC}"
