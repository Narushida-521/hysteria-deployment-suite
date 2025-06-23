#!/bin/bash
# Hysteria 2 All-in-One Installation Script
#
# v2.5: 将单行函数定义改为标准多行格式，解决语法解析错误。
# v2.4: 采用先下载到临时文件再移动的模式，解决“文本文件忙”错误。
# v2.3: 新增自动生成标准hy2://订阅链接的功能。
# v2.2: 增加对旧服务的预先停止逻辑。
# v2.1: 增加了交互式端口选择功能。
# v2.0: 重构下载逻辑，直接下载二进制文件。

set -e

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- 全局变量 ---
INSTALL_DIR="/etc/hysteria"
HY2_VERSION_TAG="app/v2.6.2"

# --- 函数定义 ---

# 检查当前用户是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以root用户身份运行。${NC}"
        exit 1
    fi
}

# 获取并规范化系统架构
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
            echo -e "${RED}错误: 不支持的系统架构: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo "检测到系统架构: $ARCH"
}

# 自动安装脚本所需的依赖工具
install_dependencies() {
    echo -e "${GREEN}--- 步骤 1/8: 正在检查并安装依赖...${NC}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl tar openssl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl tar openssl
    else
        echo -e "${RED}错误: 无法确定包管理器。${NC}"
        exit 1
    fi
}

# URL编码函数，用于处理密码中的特殊字符
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

# 设置并安装Hysteria 2的核心逻辑
setup_hysteria() {
    echo -e "${GREEN}--- 步骤 2/8: 端口配置 ---${NC}"
    read -rp "请输入您希望使用的端口 (推荐443, 若失败请选1024-65535) [默认: 443]: " USER_PORT
    USER_PORT=${USER_PORT:-443}
    if ! [[ "$USER_PORT" =~ ^[0-9]+$ ]] || [ "$USER_PORT" -lt 1 ] || [ "$USER_PORT" -gt 65535 ]; then
        echo -e "${RED}错误: 无效的端口号。${NC}"; exit 1
    fi
    echo "将使用端口: ${USER_PORT}"

    echo -e "${GREEN}--- 步骤 3/8: 下载 Hysteria 2 (版本: ${HY2_VERSION_TAG}) ---${NC}"
    mkdir -p $INSTALL_DIR
    URL_ENCODED_VERSION_TAG="${HY2_VERSION_TAG//\//%2F}"
    ASSET_NAME="hysteria-linux-${ARCH}"
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${URL_ENCODED_VERSION_TAG}/${ASSET_NAME}"
    
    HYSTERIA_TMP_PATH="/tmp/hysteria.new"
    echo "正在从 $DOWNLOAD_URL 下载到临时文件 ${HYSTERIA_TMP_PATH}..."
    curl -Lf -o "${HYSTERIA_TMP_PATH}" "$DOWNLOAD_URL"
    echo "下载完成。"
    
    echo -e "${GREEN}--- 步骤 4/8: 停止旧服务并替换文件 ---${NC}"
    systemctl stop hysteria.service >/dev/null 2>&1 || true
    pkill -f "hysteria server" >/dev/null 2>&1 || true
    sleep 1
    
    echo "正在将新文件移动到安装目录..."
    mv "${HYSTERIA_TMP_PATH}" "${INSTALL_DIR}/hysteria"
    chmod +x "${INSTALL_DIR}/hysteria"
    echo "文件替换并安装成功。"

    echo -e "${GREEN}--- 步骤 5/8: 正在生成自签名证书和配置文件 ---${NC}"
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${INSTALL_DIR}/server.key" -out "${INSTALL_DIR}/server.crt" -subj "/CN=bing.com" -days 3650
    read -rp "请输入您的连接密码 (留空将随机生成): " USER_PASSWORD; [ -z "${USER_PASSWORD}" ] && USER_PASSWORD=$(openssl rand -base64 16);
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

    echo -e "${GREEN}--- 步骤 6/8: 正在设置Systemd服务 ---${NC}"
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
    echo "正在重载、启用并启动服务..."; systemctl daemon-reload; systemctl enable hysteria.service; systemctl restart hysteria.service

    echo -e "${GREEN}--- 步骤 7/8: 正在配置防火墙 ---${NC}"
    if command -v ufw >/dev/null 2>&1; then ufw allow ${USER_PORT}/udp >/dev/null 2>&1 || true; fi
    if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=${USER_PORT}/udp --permanent >/dev/null 2>&1 || true && firewall-cmd --reload >/dev/null 2>&1 || true; fi

    echo -e "${GREEN}--- 步骤 8/8: 生成最终连接信息 ---${NC}"; PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com); clear
    ENCODED_PASSWORD=$(url_encode "${USER_PASSWORD}")
    NODE_NAME="Hysteria-Node-$(date +%s)"
    HY2_URI="hy2://${ENCODED_PASSWORD}@${PUBLIC_IP}:${USER_PORT}/?insecure=1&sni=bing.com#${NODE_NAME}"

    echo -e "========================================================================"
    echo -e "${GREEN}✅ Hysteria 2 安装并启动成功！${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "   您的客户端连接信息如下:"
    echo -e "   ${YELLOW}地址 (Address):      ${PUBLIC_IP}${NC}"
    echo -e "   ${YELLOW}端口 (Port):         ${USER_PORT}${NC}"
    echo -e "   ${YELLOW}密码 (Auth):         ${USER_PASSWORD}${NC}"
    echo -e "   ${YELLOW}服务器名称/SNI:       bing.com${NC}"
    echo -e "   ${YELLOW}跳过证书验证 (insecure): true${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "   ${GREEN}>>> 单行订阅链接 (可直接复制导入) <<<${NC}"
    echo -e "   ${YELLOW}${HY2_URI}${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "提示: 您可以使用 'systemctl status hysteria' 命令查看服务状态。"
    echo -e "========================================================================"
}

# --- 脚本主逻辑 ---
clear
echo -e "${YELLOW}欢迎使用Hysteria 2一键安装脚本。此过程将全自动完成。${NC}"
check_root
get_arch
install_dependencies
setup_hysteria
