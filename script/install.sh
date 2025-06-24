#!/bin/bash

# ==============================================================================
# Hysteria 2 标准一键部署脚本 (v25 - 依赖项确认)
#
# 特点:
# - [修正] 修正了 Debian/Ubuntu 系统下 awk 依赖包的名称为 gawk。
# - [新] 专为标准服务器环境 (>=512MB 内存) 设计，性能更稳定。
# - [新] 使用 systemd 管理服务，更专业、更可靠。
# - [核心] 当本地证书生成失败时，会自动下载预制证书作为后备方案。
# - [保留] 使用随机端口，增强安全性。
# - [保留] 提供卸载和日志查看功能，方便管理。
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
INSTALL_DIR="/etc/hysteria"
CONFIG_PATH="${INSTALL_DIR}/config.yaml"
CERT_PATH="${INSTALL_DIR}/cert.pem"
KEY_PATH="${INSTALL_DIR}/private.key"
HYSTERIA_BIN="/usr/local/bin/hysteria"
SERVICE_PATH="/etc/systemd/system/hysteria.service"

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
    systemctl stop hysteria || true
    systemctl disable hysteria || true
    rm -f "$HYSTERIA_BIN" "$SERVICE_PATH"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    print_message "$GREEN" "Hysteria 2 卸载完成。"
    exit 0
}

# --- 日志函数 ---
show_logs() {
    print_message "$YELLOW" "正在显示 Hysteria 2 日志..."
    journalctl -u hysteria -n 50 --no-pager
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

print_message "$YELLOW" "开始 Hysteria 2 标准部署脚本 (含备用证书)..."

# 1. 检查环境
print_message "$YELLOW" "步骤 1: 检查环境..."
if [ "$(id -u)" -ne 0 ]; then
    print_message "$RED" "错误：此脚本必须以 root 权限运行。"
    exit 1
fi

# 2. 安装依赖
print_message "$YELLOW" "步骤 2: 安装依赖..."
if command -v apt-get &>/dev/null; then
    apt-get update
    # FIX: On Debian/Ubuntu, 'awk' is a virtual package, 'gawk' is the provider.
    apt-get install -y curl coreutils openssl gawk
elif command -v yum &>/dev/null; then
    yum install -y curl coreutils openssl gawk
elif command -v dnf &>/dev/null; then
    dnf install -y curl coreutils openssl gawk
else
    print_message "$RED" "无法确定包管理器。请手动安装 'curl', 'coreutils', 'openssl', 'gawk'。"
    exit 1
fi
print_message "$GREEN" "依赖安装成功。"

# 3. 清理旧的安装
print_message "$YELLOW" "步骤 3: 清理旧的 Hysteria 2 安装..."
systemctl stop hysteria || true
rm -f "$HYSTERIA_BIN" "$SERVICE_PATH"
rm -rf "$INSTALL_DIR"
print_message "$GREEN" "旧文件和进程清理完毕。"

# 4. 获取服务器IP
print_message "$YELLOW" "步骤 4: 获取公网 IP..."
SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
if [ -z "$SERVER_IP" ]; then
    print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
fi
print_message "$GREEN" "获取到公网 IP: $SERVER_IP"

# 5. 安装 Hysteria
print_message "$YELLOW" "步骤 5: 安装 Hysteria 2..."
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;; aarch64) ARCH="arm64" ;; *) print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
esac
DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep "browser_download_url.*hysteria-linux-${ARCH}" | awk -F '"' '{print $4}' | head -n 1)
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

# 6. 配置 Hysteria
print_message "$YELLOW" "步骤 6: 配置 Hysteria 2..."
mkdir -p "$INSTALL_DIR"
LISTEN_PORT=$(shuf -i 10000-65535 -n 1)
OBFS_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)

# [核心] 尝试生成证书，如果失败则下载预制证书
print_message "$YELLOW" "正在生成证书 (如果失败将自动使用备用方案)..."
if command -v openssl &>/dev/null && openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=bing.com" -days 3650; then
    print_message "$GREEN" "成功使用 openssl 生成了新证书。"
else
    print_message "$YELLOW" "本地证书生成失败！正在启动备用方案：下载您指定的预制证书..."
    KEY_URL="https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/main/script/hy2.key"
    CERT_URL="https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/main/script/hy2.crt"
    if ! curl -Lso "$KEY_PATH" "$KEY_URL" || ! curl -Lso "$CERT_PATH" "$CERT_URL"; then
        print_message "$RED" "致命错误：备用证书下载失败，安装无法继续。"; exit 1
    fi
    print_message "$GREEN" "备用证书下载成功。"
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
print_message "$GREEN" "配置文件创建成功。"

# 7. 创建 Systemd 服务
print_message "$YELLOW" "步骤 7: 创建 Systemd 服务..."
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria 2 Service
After=network.target

[Service]
Type=simple
ExecStart=$HYSTERIA_BIN server -c $CONFIG_PATH
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
print_message "$GREEN" "Systemd 服务文件创建成功。"

# 8. 启动服务并配置防火墙
print_message "$YELLOW" "步骤 8: 启动服务并配置防火墙..."
systemctl daemon-reload
systemctl enable --now hysteria

# 配置防火墙
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --permanent --add-port="${LISTEN_PORT}/udp"
    firewall-cmd --reload
elif command -v ufw &>/dev/null; then
    ufw allow "${LISTEN_PORT}/udp"
else
    print_message "$YELLOW" "警告: 未检测到 firewalld 或 ufw，请手动开放 UDP 端口 ${LISTEN_PORT}。"
fi
print_message "$GREEN" "服务启动并配置防火墙完毕。"

# 9. 最终诊断和输出
print_message "$YELLOW" "步骤 9: 最终诊断和输出配置..."
sleep 3
set +e # 临时禁用 "exit on error"
if systemctl is-active --quiet hysteria; then
    print_message "$GREEN" "诊断成功: Hysteria 服务正在运行。"
else
    print_message "$RED" "诊断失败: Hysteria 服务未能成功启动。"
    print_message "$YELLOW" "请查看日志获取错误信息: bash $0 logs"
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
echo -e "${YELLOW}查看状态:   systemctl status hysteria${NC}"
echo -e "${YELLOW}查看日志:   bash $0 logs${NC}"
echo -e "${YELLOW}重启服务:   systemctl restart hysteria${NC}"
echo -e "${YELLOW}停止服务:   systemctl stop hysteria${NC}"
echo -e "${YELLOW}卸载服务:   bash $0 uninstall${NC}"
