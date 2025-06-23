#!/bin/bash
# Hysteria 2 All-in-One Installation Script
#
# v2.0: 重构下载逻辑，直接下载二进制文件而非tar.gz压缩包，适配v2.6.2+版本。
# v1.3: 升级 Hysteria 2 版本至 2.6.2。

set -e

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# --- 全局变量 ---
INSTALL_DIR="/etc/hysteria"
HY2_VERSION_TAG="app/v2.6.2" # 使用官方的复合版本标签

# --- 函数定义 ---
# (check_root, get_arch, install_dependencies 函数与之前版本相同)
check_root() { if [ "$(id -u)" -ne 0 ]; then echo -e "${RED}错误: 此脚本必须以root用户身份运行。${NC}"; exit 1; fi; }
get_arch() { ARCH=$(uname -m); case $ARCH in x86_64|amd64) ARCH="amd64";; aarch64|arm64) ARCH="arm64";; *) echo -e "${RED}错误: 不支持的系统架构: $ARCH${NC}"; exit 1;; esac; echo "检测到系统架构: $ARCH"; }
install_dependencies() { echo -e "${GREEN}--- 步骤 1/7: 正在检查并安装依赖...${NC}"; if command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y curl tar openssl; elif command -v yum >/dev/null 2>&1; then yum install -y curl tar openssl; else echo -e "${RED}错误: 无法确定包管理器。${NC}"; exit 1; fi; }

# 设置并安装Hysteria 2的核心逻辑
setup_hysteria() {
    echo -e "${GREEN}--- 步骤 2/7: 正在下载并安装 Hysteria 2 (版本: ${HY2_VERSION_TAG}) ---${NC}"
    mkdir -p $INSTALL_DIR

    # 【【【 核心重构 Start 】】】
    # 将版本标签中的 / 编码为 %2F
    local URL_ENCODED_VERSION_TAG="${HY2_VERSION_TAG//\//%2F}"
    local ASSET_NAME="hysteria-linux-${ARCH}"
    local DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${URL_ENCODED_VERSION_TAG}/${ASSET_NAME}"
    
    echo "正在从 $DOWNLOAD_URL 下载..."
    # 直接下载二进制文件到目标位置，并命名为hysteria
    curl -Lf -o "${INSTALL_DIR}/hysteria" "$DOWNLOAD_URL"
    echo "下载完成。"
    
    echo "正在设置文件权限..."
    # 直接为下载的二进制文件赋予执行权限
    chmod +x "${INSTALL_DIR}/hysteria"
    echo "安装成功。"
    # 【【【 核心重构 End 】】】

    # ... 后续步骤 3/7 到 7/7 与之前版本完全相同 ...
    echo -e "${GREEN}--- 步骤 3/7: 正在生成自签名证书 ---${NC}"; openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${INSTALL_DIR}/server.key" -out "${INSTALL_DIR}/server.crt" -subj "/CN=bing.com" -days 3650
    echo -e "${GREEN}--- 步骤 4/7: 正在生成配置文件 ---${NC}"; read -rp "请输入您的连接密码 (留空将随机生成): " USER_PASSWORD; [ -z "${USER_PASSWORD}" ] && USER_PASSWORD=$(openssl rand -base64 16); cat > "${INSTALL_DIR}/config.yaml" <<EOF
listen: :443
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
    echo -e "${GREEN}--- 步骤 5/7: 正在设置Systemd服务 ---${NC}"; cat > /etc/systemd/system/hysteria.service <<EOF
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
    echo -e "${GREEN}--- 步骤 6/7: 正在配置防火墙 ---${NC}"; if command -v ufw >/dev/null 2>&1; then ufw allow 443/udp >/dev/null 2>&1 || true; fi; if command -v firewall-cmd >/dev/null 2>&1; then firewall-cmd --add-port=443/udp --permanent >/dev/null 2>&1 || true && firewall-cmd --reload >/dev/null 2>&1 || true; fi
    echo -e "${GREEN}--- 步骤 7/7: 生成最终连接信息 ---${NC}"; PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com); clear
    echo -e "========================================================================"
    echo -e "${GREEN}✅ Hysteria 2 安装并启动成功！${NC}"
    echo -e "------------------------------------------------------------------------"
    echo -e "   您的客户端连接信息如下:"
    echo -e "   ${YELLOW}地址 (Address):      ${PUBLIC_IP}${NC}"
    echo -e "   ${YELLOW}端口 (Port):         443${NC}"
    echo -e "   ${YELLOW}密码 (Auth):         ${USER_PASSWORD}${NC}"
    echo -e "   ${YELLOW}服务器名称/SNI:       bing.com${NC}"
    echo -e "   ${YELLOW}跳过证书验证 (insecure): true${NC}"
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
