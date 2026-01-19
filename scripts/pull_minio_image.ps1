# 拉取 MinIO 镜像脚本 (PowerShell)
# 提供多种方式拉取 MinIO 镜像

Write-Host "MinIO 镜像拉取工具" -ForegroundColor Cyan
Write-Host ""

# 检查 Docker 是否运行
try {
    docker info | Out-Null
} catch {
    Write-Host "错误: Docker 未运行，请先启动 Docker" -ForegroundColor Red
    exit 1
}

Write-Host "⚠️  注意: MinIO 官方已停止提供预编译镜像" -ForegroundColor Yellow
Write-Host "我们将使用第三方构建的镜像" -ForegroundColor Yellow
Write-Host ""
Write-Host "请选择拉取方式：" -ForegroundColor Yellow
Write-Host "1. 拉取 coollabsio/minio (推荐，自动从源码构建)" -ForegroundColor White
Write-Host "2. 拉取 bitnami/minio (备选方案)" -ForegroundColor White
Write-Host "3. 使用代理拉取（如果有代理）" -ForegroundColor White
Write-Host "4. 查看已安装的镜像" -ForegroundColor White
Write-Host ""

$choice = Read-Host "请输入选项 (1-4)"

switch ($choice) {
    "1" {
        Write-Host "正在拉取 coollabsio/minio 镜像..." -ForegroundColor Yellow
        Write-Host "提示: 如果失败，请先配置 Docker 镜像加速器" -ForegroundColor Gray
        docker pull coollabsio/minio:latest
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 镜像拉取成功！" -ForegroundColor Green
            Write-Host "现在可以运行: docker-compose -f docker-compose.minio.yml up -d" -ForegroundColor Cyan
        } else {
            Write-Host "❌ 镜像拉取失败" -ForegroundColor Red
            Write-Host "请尝试配置 Docker 镜像加速器或使用代理" -ForegroundColor Yellow
        }
    }
    "2" {
        Write-Host "正在拉取 bitnami/minio 镜像..." -ForegroundColor Yellow
        docker pull bitnami/minio:latest
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ 镜像拉取成功！" -ForegroundColor Green
            Write-Host "现在可以运行: docker-compose -f docker-compose.minio.bitnami.yml up -d" -ForegroundColor Cyan
        } else {
            Write-Host "❌ 镜像拉取失败" -ForegroundColor Red
        }
    }
    "3" {
        $proxy = Read-Host "请输入代理地址 (例如: http://127.0.0.1:7890)"
        if ($proxy) {
            Write-Host "使用代理拉取镜像..." -ForegroundColor Yellow
            $env:HTTP_PROXY = $proxy
            $env:HTTPS_PROXY = $proxy
            Write-Host "选择要拉取的镜像：" -ForegroundColor Yellow
            Write-Host "1. coollabsio/minio" -ForegroundColor White
            Write-Host "2. bitnami/minio" -ForegroundColor White
            $imgChoice = Read-Host "请输入选项 (1-2)"
            if ($imgChoice -eq "1") {
                docker pull coollabsio/minio:latest
            } else {
                docker pull bitnami/minio:latest
            }
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ 镜像拉取成功！" -ForegroundColor Green
            }
        }
    }
    "4" {
        Write-Host "已安装的 MinIO 相关镜像：" -ForegroundColor Cyan
        docker images | Select-String -Pattern "minio|coollabsio"
    }
    default {
        Write-Host "无效选项" -ForegroundColor Red
    }
}
