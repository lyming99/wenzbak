#!/bin/bash
# WebDAV 启动脚本 (Bash)
# 用于快速启动 WebDAV 存储服务

echo "正在启动 WebDAV 服务..."

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "错误: Docker 未运行，请先启动 Docker"
    exit 1
fi

# 检查 docker-compose 文件是否存在
if [ ! -f "docker-compose.webdav.yml" ]; then
    echo "错误: 找不到 docker-compose.webdav.yml 文件"
    exit 1
fi

# 启动 WebDAV
docker-compose -f docker-compose.webdav.yml up -d

# 等待服务启动
echo "等待 WebDAV 服务启动..."
sleep 5

# 检查服务状态
if docker ps | grep -q "wenzbak-webdav"; then
    echo ""
    echo "✅ WebDAV 服务启动成功！"
    echo ""
    echo "📋 连接信息："
    echo "   - WebDAV URL: http://localhost:8080"
    echo "   - 用户名: webdav"
    echo "   - 密码: webdav"
    echo ""
    echo "💡 提示："
    echo "   1. 使用 http://localhost:8080 访问 WebDAV 服务"
    echo "   2. 在代码中使用 WebDAV 存储客户端连接"
    echo "   3. 可以使用文件管理器挂载为网络驱动器"
    echo ""
    echo "🛑 停止服务: docker-compose -f docker-compose.webdav.yml down"
else
    echo "❌ WebDAV 服务启动失败，请查看日志："
    docker-compose -f docker-compose.webdav.yml logs
    exit 1
fi
