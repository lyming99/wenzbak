# MinIO 启动脚本 (PowerShell)
# 用于快速启动 MinIO 本地存储服务

Write-Host "正在启动 MinIO 服务..." -ForegroundColor Cyan

# 检查 Docker 是否运行
try {
    docker info | Out-Null
} catch {
    Write-Host "错误: Docker 未运行，请先启动 Docker" -ForegroundColor Red
    exit 1
}

# 检查 docker-compose 文件是否存在
if (-not (Test-Path "docker-compose.minio.yml")) {
    Write-Host "错误: 找不到 docker-compose.minio.yml 文件" -ForegroundColor Red
    exit 1
}

# 启动 MinIO
docker-compose -f docker-compose.minio.yml up -d

# 等待服务启动
Write-Host "等待 MinIO 服务启动..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# 检查服务状态
$containerRunning = docker ps | Select-String "wenzbak-minio"

if ($containerRunning) {
    Write-Host ""
    Write-Host "? MinIO 服务启动成功！" -ForegroundColor Green
    Write-Host ""
    Write-Host "? 服务信息：" -ForegroundColor Cyan
    Write-Host "   - API 端点: http://localhost:9000"
    Write-Host "   - 控制台: http://localhost:9001"
    Write-Host "   - 用户名: minioadmin"
    Write-Host "   - 密码: minioadmin"
    Write-Host ""
    Write-Host "? 提示：" -ForegroundColor Yellow
    Write-Host "   1. 打开浏览器访问 http://localhost:9001 登录控制台"
    Write-Host "   2. 在控制台中创建存储桶（Bucket）"
    Write-Host "   3. 使用 example/minio_example.dart 测试连接"
    Write-Host ""
    Write-Host "? 停止服务: docker-compose -f docker-compose.minio.yml down" -ForegroundColor Gray
} else {
    Write-Host "? MinIO 服务启动失败，请检查日志：" -ForegroundColor Red
    docker-compose -f docker-compose.minio.yml logs
    exit 1
}
