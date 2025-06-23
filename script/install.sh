#!/bin/bash
# Hysteria 2 All-in-One Installation Script
#
# 功能:
# - 自动检测系统架构
# - 自动安装依赖
# - 下载最新或指定版本的 Hysteria 2
# - 生成自签名证书和配置文件
# - 自动创建并启动 Systemd 服务
# - 配置防火墙
# - 最终输出清晰的客户端连接信息

# 使用 set -e 保证脚本中任何命令执行失败时，脚本会立即退出
set -e

# --- 颜色定义，用于美化输出 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# --- 全局变量 ---
INSTALL_DIR="/etc/hysteria"
# 您可以在这里修改为您希望安装的Hysteria 2版本
HY2_VERSION="2.4.0" 

# --- 函数定义 ---

# 检查当前用户是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以root用户身份运行。请尝试使用 'sudo -i' 命令切换到root用户后再执行。${NC}"
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
    echo -e "${GREEN}--- 步骤 1/7: 正在检查并安装依赖 (curl, tar, openssl) ---${NC}"
    # 使用 command -v 检查命令是否存在，比 which更可靠
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl tar openssl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y curl tar openssl
    else
        echo -e "${RED}错误: 无法确定包管理器 (apt/yum)。请手动安装 curl, tar, openssl。${NC}"
        exit 1
    fi
}

# 设置并安装Hysteria 2的核心逻辑
setup_hysteria() {
    echo -e "${GREEN}--- 步骤 2/7: 正在下载并安装 Hysteria 2 (版本: ${HY2_VERSION}) ---${NC}"
    mkdir -p $INSTALL_DIR
    DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/v${HY2_VERSION}/hysteria-linux-${ARCH}.tar.gz"
    
    echo "正在从 $DOWNLOAD_URL 下载..."
    # 使用 curl -L 来自动处理重定向，-f 在服务器错误时不显示内容，-s静默模式，-o指定输出文件
    curl -Lfs -o /tmp/hysteria.tar.gz "$DOWNLOAD_URL"
    
    echo "正在解压文件..."
    # 从压缩包中只解压出我们需要的那个可执行文件
    tar -xzf /tmp/hysteria.tar.gz -C $INSTALL_DIR "hysteria-linux-${ARCH}"
    mv "${INSTALL_DIR}/hysteria-linux-${ARCH}" "${INSTALL_DIR}/hysteria"
    chmod +x "${INSTALL_DIR}/hysteria"
    # 清理下载的临时文件
    rm /tmp/hysteria.tar.gz
    
    echo -e "${GREEN}--- 步骤 3/7: 正在生成自签名证书 ---${NC}"
    # 使用openssl一句话生成自签名ECC证书和私钥，-subj参数避免了交互式问答
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "${INSTALL_DIR}/server.key" -out "${INSTALL_DIR}/server.crt" -subj "/CN=bing.com" -days 3650

    echo -e "${GREEN}--- 步骤 4/7: 正在生成配置文件 ---${NC}"
    # 提示用户输入密码，如果直接回车，则用openssl生成一个16位的随机密码
    read -rp "请输入您的连接密码 (建议复杂一些，留空将随机生成): " USER_PASSWORD
    [ -z "${USER_PASSWORD}" ] && USER_PASSWORD=$(openssl rand -base64 16)

    # 使用cat和Here Document (<<EOF) 的方式，将多行文本写入配置文件
    cat > "${INSTALL_DIR}/config.yaml" <<EOF
# Hysteria 2 Server Configuration
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

    echo -e "${GREEN}--- 步骤 5/7: 正在设置Systemd服务 ---${NC}"
    # 创建一个systemd服务单元文件，用于管理hysteria进程
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

    echo "正在重载、启用并启动服务..."
    systemctl daemon-reload
    systemctl enable hysteria.service
    systemctl restart hysteria.service

    echo -e "${GREEN}--- 步骤 6/7: 正在配置防火墙 ---${NC}"
    # 兼容ufw和firewalld两种常见的防火墙
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 443/udp >/dev/null 2>&1 || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port=443/udp --permanent >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    
    echo -e "${GREEN}--- 步骤 7/7: 生成最终连接信息 ---${NC}"
    # 使用外部API获取公网IP
    PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com)
    
    # 清屏并输出最终的、美观的配置信息
    clear
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
    echo -e "提示: 因为我们使用的是自签名证书，请务必在客户端开启“允许不安全连接”或“跳过证书验证”选项。"
    echo -e "您可以使用 'systemctl status hysteria' 命令查看服务状态。"
    echo -e "========================================================================"
}

# --- 脚本主逻辑 ---
# 依次执行所有函数
clear
echo -e "${YELLOW}欢迎使用Hysteria 2一键安装脚本。此过程将全自动完成。${NC}"
check_root
get_arch
install_dependencies
setup_hysteria