#!/bin/bash

# ==============================================================================
# Hysteria 2 专业部署脚本
# 特点:
# - [修正] 修正了环境检查逻辑，不再错误地检查 'coreutils' 包名。
# - [重构] 全新代码结构，模块化、功能化，清晰易懂。
# - [健壮] 采用严格的错误处理机制 (set -euo pipefail) 和详细的步骤检查。
# - [标准] 专为标准 Linux 环境 (>=512MB 内存, systemd) 设计，稳定可靠。
# - [安全] 使用随机端口，自动生成强密码。
# - [易用] 提供完整的安装、卸载、日志查看和状态管理功能。
# ==============================================================================

# --- 严格模式 ---
# set -e: 如果任何命令失败（返回非零退出状态），则立即退出。
# set -u: 如果引用了未定义的变量，则视为错误并立即退出。
# set -o pipefail: 如果管道中的任何命令失败，则整个管道的退出状态为失败。
set -euo pipefail

# --- 全局变量和常量 ---
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly INSTALL_DIR="/etc/hysteria"
readonly CONFIG_PATH="${INSTALL_DIR}/config.yaml"
readonly CERT_PATH="${INSTALL_DIR}/cert.pem"
readonly KEY_PATH="${INSTALL_DIR}/private.key"
readonly HYSTERIA_BIN="/usr/local/bin/hysteria"
readonly SERVICE_PATH="/etc/systemd/system/hysteria.service"
readonly SCRIPT_NAME="$0"

# --- 辅助函数 ---

# 打印带有颜色和边框的消息
print_message() {
    local color="$1"
    local message="$2"
    echo -e "\n${color}==================================================================${NC}"
    echo -e "${color}  ${message}${NC}"
    echo -e "${color}==================================================================${NC}\n"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &>/dev/null
}

# --- 核心功能函数 ---

# 1. 检查运行环境
check_environment() {
    print_message "$YELLOW" "步骤 1/8: 检查运行环境"
    
    # 检查是否为 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
    
    # 检查 systemd 是否存在
    if ! command_exists systemctl; then
        print_message "$RED" "错误：未检测到 systemd。此脚本专为使用 systemd 的现代 Linux 系统设计。"
        exit 1
    fi

    # [修正] 检查所需的核心工具，移除对 'coreutils' 包名的检查
    local dependencies=("curl" "openssl" "gawk" "shuf" "tr" "head")
    for cmd in "${dependencies[@]}"; do
        if ! command_exists "$cmd"; then
            print_message "$RED" "错误：核心命令 '$cmd' 不存在。请先手动安装它。"
            exit 1
        fi
    done
    
    print_message "$GREEN" "环境检查通过。"
}

# 2. 安装依赖项
install_dependencies() {
    print_message "$YELLOW" "步骤 2/8: 安装依赖项"
    
    local pkg_manager
    if command_exists apt-get; then
        pkg_manager="apt-get"
        print_message "$YELLOW" "检测到 apt 包管理器，正在更新..."
        if ! apt-get update -y; then
            print_message "$RED" "apt 更新失败，请检查您的软件源设置。"
            exit 1
        fi
        print_message "$YELLOW" "正在安装核心依赖..."
        if ! apt-get install -y curl coreutils openssl gawk; then
            print_message "$RED" "使用 apt 安装依赖失败。"
            exit 1
        fi
    elif command_exists dnf; then
        pkg_manager="dnf"
        print_message "$YELLOW" "检测到 dnf 包管理器，正在安装核心依赖..."
        if ! dnf install -y curl coreutils openssl gawk; then
            print_message "$RED" "使用 dnf 安装依赖失败。"
            exit 1
        fi
    elif command_exists yum; then
        pkg_manager="yum"
        print_message "$YELLOW" "检测到 yum 包管理器，正在安装核心依赖..."
        if ! yum install -y curl coreutils openssl gawk; then
            print_message "$RED" "使用 yum 安装依赖失败。"
            exit 1
        fi
    else
        print_message "$RED" "错误：未找到支持的包管理器 (apt/dnf/yum)。"
        exit 1
    fi
    
    print_message "$GREEN" "依赖项安装成功。"
}

# 3. 清理旧版本
cleanup_previous_installation() {
    print_message "$YELLOW" "步骤 3/8: 清理旧版本安装"
    
    if systemctl is-active --quiet hysteria; then
        print_message "$YELLOW" "检测到正在运行的旧版本，正在停止..."
        systemctl stop hysteria
    fi
    
    rm -f "$HYSTERIA_BIN" "$SERVICE_PATH"
    rm -rf "$INSTALL_DIR"
    
    # 重新加载 systemd 配置，确保旧的服务文件被清除
    systemctl daemon-reload
    
    print_message "$GREEN" "旧版本清理完毕。"
}

# 4. 下载并安装 Hysteria
download_and_install_hysteria() {
    print_message "$YELLOW" "步骤 4/8: 下载并安装 Hysteria 2"
    
    local arch
    case $(uname -m) in
        x86_64) arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)
            print_message "$RED" "错误：不支持的 CPU 架构: $(uname -m)"
            exit 1
            ;;
    esac
    
    # 使用更健壮的方式获取下载链接
    local download_url
    download_url=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep "browser_download_url.*hysteria-linux-${arch}" | awk -F '"' '{print $4}' | head -n 1)
    
    if [ -z "$download_url" ]; then
        print_message "$RED" "错误：无法从 GitHub API 获取最新的 Hysteria 2 下载链接。"
        exit 1
    fi
    
    print_message "$YELLOW" "正在从 $download_url 下载..."
    if ! curl -L -o "$HYSTERIA_BIN" "$download_url"; then
        print_message "$RED" "错误：下载 Hysteria 2 失败。请检查网络连接或 GitHub API 访问。"
        exit 1
    fi
    
    chmod +x "$HYSTERIA_BIN"
    
    # 验证下载的文件
    if ! "$HYSTERIA_BIN" -h &>/dev/null; then
        print_message "$RED" "错误：下载的文件似乎已损坏或无法执行。"
        exit 1
    fi
    
    print_message "$GREEN" "Hysteria 2 下载并验证成功。版本信息:"
    "$HYSTERIA_BIN" version
}

# 5. 创建配置文件
configure_hysteria() {
    print_message "$YELLOW" "步骤 5/8: 创建配置文件"
    
    mkdir -p "$INSTALL_DIR"
    
    local listen_port
    listen_port=$(shuf -i 10000-65535 -n 1)
    
    local obfs_password
    obfs_password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    
    print_message "$YELLOW" "正在生成自签名 TLS 证书..."
    if ! openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$KEY_PATH" -out "$CERT_PATH" -subj "/CN=bing.com" -days 3650; then
        print_message "$RED" "错误：使用 openssl 生成证书失败。"
        exit 1
    fi
    
    print_message "$YELLOW" "正在写入配置文件..."
    cat > "$CONFIG_PATH" <<EOF
listen: :${listen_port}
tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}
obfs:
  type: password
  password: ${obfs_password}
EOF
    
    # 将配置信息保存为全局变量，以便后续函数使用
    export LISTEN_PORT="$listen_port"
    export OBFS_PASSWORD="$obfs_password"
    
    print_message "$GREEN" "配置文件创建成功。"
}

# 6. 设置 Systemd 服务
setup_systemd_service() {
    print_message "$YELLOW" "步骤 6/8: 设置 Systemd 服务"
    
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Hysteria 2 Service (Managed by script)
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
    print_message "$GREEN" "Systemd 服务文件创建成功。"
}

# 7. 启动服务并配置防火墙
start_service_and_configure_firewall() {
    print_message "$YELLOW" "步骤 7/8: 启动服务并配置防火墙"
    
    print_message "$YELLOW" "正在启动 Hysteria 2 服务..."
    if ! systemctl enable --now hysteria; then
        print_message "$RED" "错误：启动 Hysteria 服务失败。请运行 'journalctl -u hysteria -n 50' 查看详细日志。"
        exit 1
    fi
    
    print_message "$YELLOW" "正在配置防火墙..."
    if command_exists firewall-cmd; then
        firewall-cmd --permanent --add-port="${LISTEN_PORT}/udp"
        firewall-cmd --reload
    elif command_exists ufw; then
        ufw allow "${LISTEN_PORT}/udp"
    else
        print_message "$YELLOW" "警告: 未检测到 firewalld 或 ufw，请手动开放 UDP 端口 ${LISTEN_PORT}。"
    fi
    
    print_message "$GREEN" "服务启动并配置防火墙完毕。"
}

# 8. 最终诊断和输出
final_diagnostics_and_summary() {
    print_message "$YELLOW" "步骤 8/8: 最终诊断和输出总结"
    
    sleep 2 # 等待服务稳定
    
    # 临时禁用 exit on error 以便打印所有信息
    set +e
    
    if systemctl is-active --quiet hysteria; then
        print_message "$GREEN" "诊断成功: Hysteria 服务正在稳定运行。"
    else
        print_message "$RED" "诊断失败: Hysteria 服务未能成功启动或已退出。"
        print_message "$YELLOW" "请使用 'bash $SCRIPT_NAME logs' 命令查看详细错误日志。"
    fi
    
    local server_ip
    server_ip=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    
    local sni_host="bing.com"
    local node_tag="Hysteria-Node"
    local subscription_link="hysteria2://${OBFS_PASSWORD}@${server_ip}:${LISTEN_PORT}?sni=${sni_host}&insecure=1#${node_tag}"

    print_message "$YELLOW" "🎉 部署完成！您的 Hysteria 2 配置信息:"
    echo -e "${GREEN}服务器地址: ${NC}${server_ip}"
    echo -e "${GREEN}端口:       ${NC}${LISTEN_PORT}"
    echo -e "${GREEN}密码:       ${NC}${OBFS_PASSWORD}"
    echo -e "${GREEN}SNI/主机名: ${NC}${sni_host}"
    echo -e "${GREEN}跳过证书验证: ${NC}true"

    print_message "$YELLOW" "您的客户端订阅链接 (hysteria2://):"
    echo "${subscription_link}"

    print_message "$GREEN" "您现在可以使用以下命令来管理 Hysteria 2 服务:"
    echo -e "${YELLOW}查看状态:   systemctl status hysteria${NC}"
    echo -e "${YELLOW}重启服务:   systemctl restart hysteria${NC}"
    echo -e "${YELLOW}停止服务:   systemctl stop hysteria${NC}"
    echo -e "${YELLOW}查看日志:   bash ${SCRIPT_NAME} logs${NC}"
    echo -e "${YELLOW}卸载服务:   bash ${SCRIPT_NAME} uninstall${NC}"
}

# --- 卸载和日志的独立入口 ---
handle_arguments() {
    if [ "$#" -gt 0 ]; then
        case "$1" in
            uninstall|del|remove)
                print_message "$YELLOW" "正在卸载 Hysteria 2..."
                if ! command_exists systemctl; then
                    pkill -f "$HYSTERIA_BIN" || true
                else
                    systemctl stop hysteria || true
                    systemctl disable hysteria || true
                    rm -f "$SERVICE_PATH"
                    systemctl daemon-reload
                fi
                rm -f "$HYSTERIA_BIN"
                rm -rf "$INSTALL_DIR"
                print_message "$GREEN" "Hysteria 2 卸载完成。"
                exit 0
                ;;
            log|logs)
                print_message "$YELLOW" "正在显示 Hysteria 2 日志 (最近50行)..."
                if ! command_exists journalctl; then
                    if [ -f "/tmp/hysteria.log" ]; then
                         tail -n 50 /tmp/hysteria.log
                    else
                         print_message "$RED" "错误：未找到 systemd 日志工具 (journalctl)，也未找到旧版日志文件。"
                    fi
                else
                    journalctl -u hysteria -n 50 --no-pager
                fi
                exit 0
                ;;
            *)
                print_message "$RED" "未知参数: $1. 可用参数: uninstall, logs"
                exit 1
                ;;
        esac
    fi
}

# --- 主函数 ---
main() {
    handle_arguments "$@"
    
    # 捕获退出信号，用于清理
    trap 'echo -e "\n${RED}脚本因错误或用户中断而退出。${NC}\n"' ERR INT
    
    check_environment
    install_dependencies
    cleanup_previous_installation
    download_and_install_hysteria
    configure_hysteria
    setup_systemd_service
    start_service_and_configure_firewall
    final_diagnostics_and_summary
}

# --- 脚本启动 ---
main "$@"
