#!/bin/bash

# ==============================================================================
# Hysteria 2 (hy2) All-in-One Deployment Script (v4 - Final & Corrected)
#
# 更新日志:
# - 修正了版本检查命令，从 `hysteria --version` 改为 `hysteria version`
#   以兼容最新版的 Hysteria 2。
# - 修复了下载逻辑，确保精确下载 Hysteria v2 版本。
# - 增加了 'set -e'，任何命令出错时脚本将立即停止。
# ==============================================================================

# --- 脚本设置 ---
set -e

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

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_message "$RED" "错误：此脚本必须以 root 权限运行。"
        exit 1
    fi
}

install_dependencies() {
    print_message "$YELLOW" "正在检查并安装依赖 (curl, jq, iproute2)..."
    if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null || ! command -v ss &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y curl jq iproute2
        elif command -v yum &>/dev/null; then
            yum install -y curl jq iproute
        elif command -v dnf &>/dev/null; then
            dnf install -y curl jq iproute
        else
            print_message "$RED" "无法确定包管理器。请手动安装 'curl', 'jq' 和 'iproute2'。"
            exit 1
        fi
    fi
}

get_server_ip() {
    SERVER_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    if [ -z "$SERVER_IP" ]; then
        print_message "$RED" "无法自动获取服务器公网 IP 地址。"; exit 1
    fi
}

install_hysteria() {
    print_message "$YELLOW" "正在查找并安装 Hysteria 2 最新版本..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *)
            print_message "$RED" "不支持的架构: $ARCH"; exit 1 ;;
    esac

    LATEST_V2_TAG=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases" | \
        jq -r '[.[] | select(.tag_name
