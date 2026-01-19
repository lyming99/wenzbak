# WebDAV 启动脚本 (PowerShell)
# 用于快速启动 WebDAV 存储服务

Write-Host "正在启动 WebDAV 服务..." -ForegroundColor Cyan

# 检查 Docker 是否运行
try {
    docker info | Out-Null
} catch {
    Write-Host "错误: Docker 未运行，请先启动 Docker" -ForegroundColor Red
    exit 1
}

# 检查 docker-compose 文件是否存在
if (-not (Test-Path "docker-compose.webdav.yml")) {
    Write-Host "错误: 找不到 docker-compose.webdav.yml 文件" -ForegroundColor Red
    exit 1
}

# 启动 WebDAV
docker-compose -f docker-compose.webdav.yml up -d

# 等待服务启动
Write-Host "等待 WebDAV 服务启动..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# 检查服务状态
$containerRunning = docker ps | Select-String "wenzbak-webdav"

if ($containerRunning) {
    Write-Host ""
    Write-Host "✅ WebDAV 服务启动成功！" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 连接信息：" -ForegroundColor Cyan
    Write-Host "   - WebDAV URL: http://localhost:8080"
    Write-Host "   - 用户名: webdav"
    Write-Host "   - 密码: webdav"
    Write-Host ""
    Write-Host "💡 提示：" -ForegroundColor Yellow
    Write-Host "   1. 使用 http://localhost:8080 访问 WebDAV 服务"
    Write-Host "   2. 在代码中使用 WebDAV 存储客户端连接"
    Write-Host "   3. 可以使用文件管理器挂载为网络驱动器"
    Write-Host ""
    Write-Host "🛑 停止服务: docker-compose -f docker-compose.webdav.yml down" -ForegroundColor Gray
} else {
    Write-Host "❌ WebDAV 服务启动失败，请查看日志：" -ForegroundColor Red
    docker-compose -f docker-compose.webdav.yml logs
    exit 1
}
