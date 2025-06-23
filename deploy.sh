#!/bin/bash
set -e
echo "================================================="
echo " Hysteria 2 自动化部署工具 (Spring Cloud 版) "
echo "================================================="
echo
echo "---[步骤 0/4]: 正在清理可能存在的旧进程..."
pkill -f "config-server-1.0.jar" > /dev/null 2>&1 || true
pkill -f "hy2-installer-client-1.0.jar" > /dev/null 2>&1 || true
echo "旧进程清理完毕。"
echo
echo "---[步骤 1/4]: 正在后台启动配置中心服务 (应用A)..."
java -jar spring-cloud-apps/config-server/target/config-server-1.0.jar > config-server.log 2>&1 &
CONFIG_SERVER_PID=$!
echo "配置中心已启动，进程ID: $CONFIG_SERVER_PID."
echo
echo "---[步骤 2/4]: 等待15秒，确保配置中心服务完全就绪..."
sleep 15
echo "等待完毕。"
echo
echo "---[步骤 3/4]: 启动部署工具 (应用B)，开始在当前服务器部署Hysteria 2..."
java -jar spring-cloud-apps/hy2-installer-client/target/hy2-installer-client-1.0.jar
echo "部署工具 (应用B) 执行完毕。"
echo
echo "---[步骤 4/4]: 部署任务完成，正在关闭临时的配置中心服务..."
kill $CONFIG_SERVER_PID
echo "配置中心服务已关闭。"
echo
echo "================================================="
echo "🎉 全部操作完成！请查看上方的节点配置信息。"
echo "================================================="