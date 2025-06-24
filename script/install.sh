#!/bin/bash

# ==============================================================================
# Hysteria2 h-ui 面板一键部署脚本 (v1 - Docker 终极版)
#
# 工作原理:
# - [核心] 本脚本将通过安装 Docker 来运行一个功能强大的 Hysteria 管理面板 (h-ui)。
# - [核心] 您之后可以通过这个网页面板来安装、配置和管理 Hysteria 2 服务。
# - [核心] 这种方式能完美兼容您这种低内存、无 Swap、非 Systemd 的特殊服务器环境。
# - 提供卸载功能，方便您清理环境。
# ==============================================================================

# --- 脚本设置 ---
# 如果任何命令失败，则立即退出
set -e

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    print_message "$YELLOW" "正在卸载 h-ui 面板和 Docker..."

    # 停止并删除 h-ui 容器
    if [ "$(docker ps -a -q -f name=h-ui)" ]; then
        print_message "$YELLOW" "正在停止并删除 h-ui 容器..."
        docker stop h-ui
        docker rm h-ui
        print_message "$GREEN" "h-ui 容器已删除。"
    else
        print_message "$YELLOW" "未发现 h-ui 容器。"
    fi

    # 删除 h-ui 镜像
    if [ "$(docker images -q jonssonyan/h-ui)" ]; then
        print_message "$YELLOW" "正在删除 h-ui 镜像..."
        docker rmi jonssonyan/h-ui
        print_message "$GREEN" "h-ui 镜像已删除。"
    else
        print_message "$YELLOW" "未发现 h-ui 镜像。"
    fi
    
    # 删除 h-ui 数据目录
    if [ -d "/h-ui/" ]; then
        print_message "$YELLOW" "正在删除 h-ui 数据目录..."
        rm -rf /h-ui/
        print_message "$GREEN" "h-ui 数据目录已删除。"
    fi

    print_message "$GREEN" "h-ui 面板卸载完成。"
    echo -e "${YELLOW}注意：本脚本不会自动卸载 Docker，如果您需要，请手动卸载。${NC}"
    exit 0
}

# --- 主执行流程 ---

# 处理命令行参数 (uninstall)
if [ "$#" -gt 0 ]; then
    if [ "$1" == "uninstall" ]; then
        uninstall
    else
        print_message "$RED" "未知参数: $1. 可用参数: uninstall"
        exit 1
    fi
fi

print_message "$YELLOW" "开始 Hysteria2 h-ui 面板部署 (Docker 终极版)..."

# 1. 检查环境
print_message "$YELLOW" "步骤 1: 检查环境..."
if [ "$(id -u)" -ne 0 ]; then
    print_message "$RED" "错误：此脚本必须以 root 权限运行。"
    exit 1
fi
print_message "$GREEN" "环境检查通过。"

# 2. 安装 Docker
print_message "$YELLOW" "步骤 2: 检查并安装 Docker..."
if command -v docker &>/dev/null; then
    print_message "$GREEN" "Docker 已安装，跳过安装步骤。"
else
    print_message "$YELLOW" "正在使用官方脚本安装 Docker..."
    # 使用官方脚本安装，它能兼容绝大多数系统
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # 检查 Docker 是否安装成功
    if ! command -v docker &>/dev/null; then
        print_message "$RED" "Docker 安装失败，请检查上面的错误信息。脚本无法继续。"
        exit 1
    fi
    print_message "$GREEN" "Docker 安装成功！"
fi

# 确保 Docker 服务正在运行 (适用于非 systemd 环境的检查)
# 在非 systemd 系统，Docker 通常由其他 init 系统（如 sysvinit）管理
if ! docker info > /dev/null 2>&1; then
    print_message "$RED" "Docker 服务未能启动。请尝试重启服务器或手动启动 Docker 服务。"
    exit 1
fi
print_message "$GREEN" "Docker 服务正在运行。"

# 3. 安装并运行 h-ui 面板
print_message "$YELLOW" "步骤 3: 安装并运行 h-ui 管理面板..."
# 检查容器是否已存在
if [ "$(docker ps -a -q -f name=h-ui)" ]; then
    print_message "$YELLOW" "h-ui 容器已存在，正在尝试重启..."
    docker restart h-ui
else
    print_message "$YELLOW" "正在创建 h-ui 数据目录..."
    mkdir -p /h-ui/bin /h-ui/data /h-ui/export /h-ui/logs

    print_message "$YELLOW" "正在拉取并启动 h-ui 容器..."
    # 使用 --network=host 模式，让容器直接使用主机的网络，简化端口配置
    docker run -d \
        --name h-ui \
        --restart always \
        --network=host \
        -e TZ=Asia/Shanghai \
        -v /h-ui/bin:/h-ui/bin \
        -v /h-ui/data:/h-ui/data \
        -v /h-ui/export:/h-ui/export \
        -v /h-ui/logs:/h-ui/logs \
        jonssonyan/h-ui:latest
fi

# 等待容器启动
sleep 5

# 4. 最终检查和输出
print_message "$YELLOW" "步骤 4: 最终检查和输出信息..."
# 检查容器是否成功运行
if [ "$(docker ps -q -f name=h-ui)" ]; then
    print_message "$GREEN" "🎉 h-ui 面板容器已成功启动！"
    
    # 获取面板访问地址和初始密码
    IP_ADDR=$(curl -s http://checkip.amazonaws.com || curl -s https://api.ipify.org)
    PANEL_URL="http://${IP_ADDR}:54321"
    
    # h-ui 新版本会生成随机密码，这里我们直接提示用户查看日志
    print_message "$YELLOW" "您的管理面板信息:"
    echo -e "${GREEN}面板访问地址: ${NC}${PANEL_URL}"
    echo -e "${YELLOW}首次登录的用户名和密码，请查看容器日志获取。${NC}"
    echo -e "${YELLOW}运行以下命令查看初始密码:${NC}"
    echo -e "docker logs h-ui"

    print_message "$GREEN" "部署完成！"
    echo -e "现在，请用浏览器访问上面的面板地址，然后在网页上配置您的 Hysteria 2 服务。"
    echo -e "您可以使用以下命令管理面板:"
    echo -e "${YELLOW}查看日志和初始密码: docker logs h-ui${NC}"
    echo -e "${YELLOW}重启面板:           docker restart h-ui${NC}"
    echo -e "${YELLOW}停止面板:           docker stop h-ui${NC}"
    echo -e "${YELLOW}卸载面板:           bash $0 uninstall${NC}"

else
    print_message "$RED" "h-ui 面板容器启动失败！"
    echo -e "请运行以下命令查看详细错误日志:"
    echo -e "docker logs h-ui"
    exit 1
fi
