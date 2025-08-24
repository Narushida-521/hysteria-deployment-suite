#!/bin/bash

# ==============================================================================
# Hysteria 2 一键安装脚本 (v13 - 支持自定义端口和密码)
# 作者: Grok, based on original by Gemini & Narushida-521
#
# 特点:
# - [新增] 支持在安装时自定义端口和密码。
# - [新增] 如果不提供密码，则自动生成16位强随机密码。
# - 移除 obfs 配置，保留 auth 和 masquerade，伪装为 https://www.bing.com。
# - 启用 BBR 拥塞控制算法，优化网络性能。
# - 增强证书验证、端口检查和服务启动鲁棒性。
# - 详细错误日志，便于调试。
# - 支持卸载和日志查看功能。
# ==============================================================================

# --- 严格模式 ---
set -euo pipefail

# --- 全局变量 ---
readonly GREEN='\033[32m'
readonly RED='\033[31m'
readonly YELLOW='\033[33m'
readonly NC='\033[0m'

readonly INSTALL_DIR="/etc/hysteria"
readonly CONFIG_PATH="${INSTALL_DIR}/config.yaml"
readonly CERT_PATH="${INSTALL_DIR}/cert.pem"
readonly KEY_PATH="${INSTALL_DIR}/private.key"
readonly HYSTERIA_BIN="/usr/local/bin/hysteria"
readonly SERVICE_PATH="/etc/systemd/system/hysteria.service"
readonly CERT_URL="https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/main/script/hy2.crt"
readonly KEY_URL="https://raw.githubusercontent.com/Narushida-521/hysteria-deployment-suite/main/script/hy2.key"
readonly SCRIPT_NAME="$0"

# --- 辅助函数 ---

# 打印消息
print_message() {
    local color="$1"
    local message="$2"
    echo -e "\n${color}=== ${message} ===${NC}\n"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# 检查文件是否有效
file_valid() {
    local file="$1"
    [ -f "$file" ] && [ -s "$file" ]
}

# --- 核心功能 ---

# 1. 检查环境
check_environment() {
    print_message "$YELLOW" "步骤 1/8: 检查系统环境"
    [ "$(id -u)" -eq 0 ] || { print_message "$RED" "错误：必须以 root 权限运行"; exit 1; }
    command_exists systemctl || { print_message "$RED" "错误：未检测到 systemd"; exit 1; }
    [ -r /dev/urandom ] || { print_message "$RED" "错误：/dev/urandom 不可用"; exit 1; }
    local kernel_version=$(uname -r | cut -d'-' -f1)
    local kernel_major=$(echo "$kernel_version" | cut -d'.' -f1)
    local kernel_minor=$(echo "$kernel_version" | cut -d'.' -f2)
    if [ "$kernel_major" -lt 4 ] || { [ "$kernel_major" -eq 4 ] && [ "$kernel_minor" -lt 9 ]; }; then
        print_message "$RED" "错误：内核版本 $kernel_version 不支持 BBR（需 4.9 或以上）"
        exit 1
    fi
    print_message "$GREEN" "环境检查通过，内核版本: $kernel_version"
}

# 2. 启用 BBR
enable_bbr() {
    print_message "$YELLOW" "步骤 2/8: 启用 BBR 拥塞控制"
    modprobe tcp_bbr 2>/dev/null || true
    if ! lsmod | grep -q bbr; then
        print_message "$RED" "错误：无法加载 tcp_bbr 模块"
        exit 1
    fi
    sysctl -w net.core.default_qdisc=fq >/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null
    # 避免重复写入
    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null
    if sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        print_message "$GREEN" "BBR 已启用"
    else
        print_message "$RED" "错误：BBR 启用失败"
        exit 1
    fi
}

# 3. 安装依赖
install_dependencies() {
    print_message "$YELLOW" "步骤 3/8: 安装依赖"
    local pkg_manager=""
    if command_exists apt-get; then
        pkg_manager="apt-get"
        $pkg_manager update -y || { print_message "$RED" "错误：$pkg_manager 更新失败"; exit 1; }
    elif command_exists dnf; then
        pkg_manager="dnf"
    elif command_exists yum; then
        pkg_manager="yum"
    else
        print_message "$RED" "错误：未找到支持的包管理器"
        exit 1
    fi
    $pkg_manager install -y curl gawk coreutils net-tools openssl || { print_message "$RED" "错误：依赖安装失败"; exit 1; }
    for cmd in curl gawk tr head netstat openssl; do
        command_exists "$cmd" || { print_message "$RED" "错误：依赖 $cmd 未安装"; exit 1; }
    done
    print_message "$GREEN" "依赖安装完成"
}

# 4. 清理旧安装
cleanup_old_install() {
    print_message "$YELLOW" "步骤 4/8: 清理旧安装"
    systemctl stop hysteria.service 2>/dev/null || true
    systemctl disable hysteria.service 2>/dev/null || true
    rm -f "$HYSTERIA_BIN" "$SERVICE_PATH"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload 2>/dev/null || true
    print_message "$GREEN" "旧安装清理完成"
}

# 5. 下载 Hysteria
download_hysteria() {
    print_message "$YELLOW" "步骤 5/8: 下载 Hysteria 2"
    local arch=""
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *) print_message "$RED" "错误：不支持的架构 $(uname -m)"; exit 1 ;;
    esac
    local url=$(curl -s --retry 3 --retry-delay 2 "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep "browser_download_url.*hysteria-linux-${arch}" | awk -F '"' '{print $4}' | head -n 1)
    [ -n "$url" ] || { print_message "$RED" "错误：无法获取下载链接"; exit 1; }
    print_message "$YELLOW" "下载 $url ..."
    curl -Lso "$HYSTERIA_BIN" --retry 3 --retry-delay 2 "$url" || { print_message "$RED" "错误：下载失败"; exit 1; }
    chmod +x "$HYSTERIA_BIN"
    "$HYSTERIA_BIN" -h &>/dev/null || { print_message "$RED" "错误：二进制文件无效"; exit 1; }
    print_message "$GREEN" "Hysteria 下载完成，版本信息："
    "$HYSTERIA_BIN" version
}

# 6. 配置 Hysteria
configure_hysteria() {
    print_message "$YELLOW" "步骤 6/8: 创建配置文件"
    mkdir -p "$INSTALL_DIR" || { print_message "$RED" "错误：无法创建目录 $INSTALL_DIR"; exit 1; }
    chmod 755 "$INSTALL_DIR"
    [ -w "$INSTALL_DIR" ] || { print_message "$RED" "错误：目录 $INSTALL_DIR 不可写"; exit 1; }

    # --- [修改] 交互式输入端口和密码 ---
    local port
    local password

    # 获取端口
    read -p "请输入您要使用的端口号 [1-65535] (默认: 443): " custom_port
    port=${custom_port:-443}
    # 验证端口
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_message "$RED" "错误：无效的端口号。请输入 1-65535 之间的数字。"
        exit 1
    fi

    # 获取密码
    read -p "请输入您的连接密码 (留空将自动生成一个16位强密码): " custom_password
    if [ -z "$custom_password" ]; then
        password=$(head -c 12 /dev/urandom | base64 | tr -d '/+=')
        print_message "$YELLOW" "已为您生成随机密码: ${password}"
    else
        password="$custom_password"
    fi
    # --- [修改结束] ---

    print_message "$YELLOW" "检查端口 $port ..."
    if netstat -tulnp | grep -q ":${port}\\>"; then
        print_message "$RED" "错误：端口 $port 已被占用，请重新运行脚本并选择其他端口"
        exit 1
    fi

    print_message "$YELLOW" "下载证书和密钥..."
    curl -Lso "$CERT_PATH" --retry 5 --retry-delay 3 --connect-timeout 10 "$CERT_URL" || { print_message "$RED" "错误：下载证书失败，退出码: $?"; exit 1; }
    curl -Lso "$KEY_PATH" --retry 5 --retry-delay 3 --connect-timeout 10 "$KEY_URL" || { print_message "$RED" "错误：下载密钥失败，退出码: $?"; exit 1; }
    
    file_valid "$CERT_PATH" && file_valid "$KEY_PATH" || { print_message "$RED" "错误：下载的文件无效，请检查网络或URL。"; exit 1; }
    
    print_message "$YELLOW" "验证证书和密钥..."
    openssl x509 -in "$CERT_PATH" -text -noout >/dev/null 2>&1 || { print_message "$RED" "错误：证书无效"; exit 1; }
    openssl rsa -in "$KEY_PATH" -check >/dev/null 2>&1 || { print_message "$RED" "错误：密钥无效"; exit 1; }
    print_message "$GREEN" "证书和密钥验证通过"

    print_message "$YELLOW" "生成配置文件..."
    cat > "$CONFIG_PATH" <<EOF
listen: :${port}
protocol: udp
tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}
auth:
  type: password
  password: ${password}
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com/
    rewriteHost: true
EOF
    chmod 644 "$CONFIG_PATH"
    file_valid "$CONFIG_PATH" || { print_message "$RED" "错误：配置文件 $CONFIG_PATH 创建失败"; exit 1; }

    # 导出变量给后续函数使用
    export LISTEN_PORT="$port"
    export AUTH_PASSWORD="$password"
    print_message "$GREEN" "配置文件生成完成"
}

# 7. 设置服务
setup_service() {
    print_message "$YELLOW" "步骤 7/8: 设置服务"
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria 2 Service
After=network.target
[Service]
Type=simple
ExecStart=${HYSTERIA_BIN} server -c ${CONFIG_PATH}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
RestartSec=10
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now hysteria.service || { print_message "$RED" "错误：服务启动失败，请运行 'bash ${SCRIPT_NAME} logs' 查看日志"; exit 1; }
    print_message "$GREEN" "服务设置完成"
}

# 8. 总结输出
print_summary() {
    print_message "$YELLOW" "步骤 8/8: 部署总结"
    sleep 2 # 等待服务稳定
    systemctl is-active --quiet hysteria.service || { print_message "$RED" "错误：服务未运行，请运行 'bash ${SCRIPT_NAME} logs' 查看日志"; exit 1; }
    
    local ip=$(curl -s --retry 3 --retry-delay 2 http://checkip.amazonaws.com || curl -s --retry 3 --retry-delay 2 https://api.ipify.org)
    [ -n "$ip" ] || ip="<你的服务器IP>"
    
    local sni="www.bing.com"
    local tag="Hysteria-Node"
    local link="hysteria2://${AUTH_PASSWORD}@${ip}:${LISTEN_PORT}?sni=${sni}&insecure=1#${tag}"
    
    print_message "$GREEN" "🎉 部署成功！配置信息："
    echo -e "服务器地址: ${GREEN}${ip}${NC}"
    echo -e "端口: ${GREEN}${LISTEN_PORT}${NC}"
    echo -e "密码: ${GREEN}${AUTH_PASSWORD}${NC}"
    echo -e "SNI: ${sni}"
    echo -e "跳过证书验证: true"
    echo -e "\n${YELLOW}订阅链接:${NC}\n${link}"
    
    print_message "$GREEN" "管理命令："
    echo "状态: systemctl status hysteria.service"
    echo "重启: systemctl restart hysteria.service"
    echo "停止: systemctl stop hysteria.service"
    echo "日志: bash ${SCRIPT_NAME} logs"
    echo "卸载: bash ${SCRIPT_NAME} uninstall"
}

# --- 其他功能 ---

# 处理参数
handle_args() {
    [ $# -eq 0 ] && return 0
    case "$1" in
        uninstall|del|remove)
            print_message "$YELLOW" "卸载 Hysteria 2..."
            systemctl stop hysteria.service 2>/dev/null || true
            systemctl disable hysteria.service 2>/dev/null || true
            rm -f "$SERVICE_PATH" "$HYSTERIA_BIN"
            rm -rf "$INSTALL_DIR"
            systemctl daemon-reload 2>/dev/null || true
            print_message "$GREEN" "卸载完成"
            exit 0
            ;;
        log|logs)
            print_message "$YELLOW" "查看最近50条日志..."
            command_exists journalctl && journalctl -u hysteria.service -n 50 --no-pager || print_message "$RED" "错误：未找到 journalctl"
            exit 0
            ;;
        *)
            print_message "$RED" "错误：未知参数 $1 (支持: uninstall, logs)"
            exit 1
            ;;
    esac
}

# --- 主函数 ---
main() {
    handle_args "$@"
    trap 'print_message "$RED" "脚本中断或错误退出，请检查日志: journalctl -xe"' ERR INT
    check_environment
    enable_bbr
    install_dependencies
    cleanup_old_install
    download_hysteria
    configure_hysteria
    setup_service
    print_summary
}

main "$@"
