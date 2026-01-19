#!/bin/bash

# MinIO 启动脚本
# 用于快速启动 MinIO 本地存储服务

echo "正在启动 MinIO 服务..."

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "错误: Docker 未运行，请先启动 Docker"
    exit 1
fi

# 检查 docker-compose 文件是否存在
if [ ! -f "docker-compose.minio.yml" ]; then
    echo "错误: 找不到 docker-compose.minio.yml 文件"
    exit 1
fi

# 启动 MinIO
docker-compose -f docker-compose.minio.yml up -d

# 等待服务启动
echo "等待 MinIO 服务启动..."
sleep 5

# 检查服务状态
if docker ps | grep -q wenzbak-minio; then
    echo ""
    echo "✅ MinIO 服务启动成功！"
    echo ""
    echo "📋 服务信息："
    echo "   - API 端点: http://localhost:9000"
    echo "   - 控制台: http://localhost:9001"
    echo "   - 用户名: minioadmin"
    echo "   - 密码: minioadmin"
    echo ""
    echo "💡 提示："
    echo "   1. 打开浏览器访问 http://localhost:9001 登录控制台"
    echo "   2. 在控制台中创建存储桶（Bucket）"
    echo "   3. 使用 example/minio_example.dart 测试连接"
    echo ""
    echo "🛑 停止服务: docker-compose -f docker-compose.minio.yml down"
else
    echo "❌ MinIO 服务启动失败，请检查日志："
    docker-compose -f docker-compose.minio.yml logs
    exit 1
fi
