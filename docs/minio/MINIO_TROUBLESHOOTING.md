# MinIO 故障排除指南

## ⚠️ 重要提示

**MinIO 官方已停止提供预编译的 Docker 镜像！**

我们使用第三方构建的镜像：
- **coollabsio/minio** (推荐) - 自动从源码构建
- **bitnami/minio** (备选) - Bitnami 提供的安全镜像

## 镜像拉取失败

### 问题：无法从 Docker Hub 拉取镜像

错误信息：
```
failed to resolve reference "docker.io/minio/minio:latest": failed to do request
```
或
```
pull access denied for registry.cn-hangzhou.aliyuncs.com/minio/minio
```

### 解决方案

#### 方案 1: 使用第三方镜像（推荐）

MinIO 官方镜像已不可用，使用第三方构建的镜像：

**使用 coollabsio/minio (推荐):**
```bash
docker-compose -f docker-compose.minio.yml up -d
```

**如果 coollabsio/minio 无法拉取，使用 Bitnami 镜像:**
```bash
docker-compose -f docker-compose.minio.bitnami.yml up -d
```

#### 方案 2: 配置 Docker 镜像加速器

**Windows (Docker Desktop):**
1. 运行配置脚本：
```powershell
.\scripts\setup_docker_mirror.ps1
```
2. 或手动配置：
   - 打开 Docker Desktop
   - Settings → Docker Engine
   - 添加以下配置：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```
3. 点击 "Apply & Restart"
4. 然后运行：`docker-compose -f docker-compose.minio.yml up -d`

**Linux:**
编辑 `/etc/docker/daemon.json`：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```
然后重启 Docker：
```bash
sudo systemctl restart docker
```

#### 方案 2: 使用脚本拉取镜像

运行提供的拉取脚本：

**Windows:**
```powershell
.\scripts\pull_minio_image.ps1
```

脚本会提供多种拉取方式供选择。

**手动拉取:**
```bash
# 使用特定版本（推荐，避免 latest 标签问题）
docker pull minio/minio:RELEASE.2024-12-13T19-30-20Z

# 如果配置了镜像加速器，可以直接拉取
docker pull minio/minio:latest
```

#### 方案 3: 配置 Docker 镜像加速器

**Windows (Docker Desktop):**
1. 打开 Docker Desktop
2. 进入 Settings → Docker Engine
3. 添加以下配置：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ]
}
```
4. 点击 "Apply & Restart"

**Linux:**
编辑 `/etc/docker/daemon.json`：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com",
    "https://registry.cn-hangzhou.aliyuncs.com"
  ]
}
```
然后重启 Docker：
```bash
sudo systemctl restart docker
```

#### 方案 4: 使用代理

如果有代理，可以配置 Docker 使用代理：

**Windows (Docker Desktop):**
Settings → Resources → Proxies → 配置代理

**Linux:**
创建 `/etc/systemd/system/docker.service.d/http-proxy.conf`：
```ini
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
```
然后：
```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

#### 方案 5: 使用特定版本标签

修改 `docker-compose.minio.yml`，使用特定版本而不是 `latest`：

```yaml
image: minio/minio:RELEASE.2024-12-13T19-30-20Z
```

## 其他常见问题

### 问题：端口被占用

**错误信息：**
```
Bind for 0.0.0.0:9000 failed: port is already allocated
```

**解决方案：**
1. 修改 `docker-compose.minio.yml` 中的端口映射
2. 或停止占用端口的服务

### 问题：无法访问控制台

**检查项：**
1. 确认容器正在运行：`docker ps | grep minio`
2. 查看容器日志：`docker logs wenzbak-minio`
3. 检查防火墙设置
4. 确认端口映射正确

### 问题：存储桶不存在

**错误信息：**
```
The specified bucket does not exist
```

**解决方案：**
1. 访问 MinIO 控制台：http://localhost:9001
2. 登录后创建存储桶
3. 确保存储桶名称与配置中的 `bucket` 字段一致

### 问题：认证失败

**错误信息：**
```
Access Denied
```

**解决方案：**
1. 检查 `accessKey` 和 `secretKey` 是否正确
2. 确认使用的是管理员账户或已创建的用户账户
3. 检查 IAM 策略设置

### 问题：数据丢失

**检查项：**
1. 确认 Docker volume 存在：`docker volume ls | grep minio`
2. 检查 volume 数据：`docker volume inspect wenzbak_minio_data`
3. 确认容器使用的是正确的 volume

## 获取帮助

如果以上方案都无法解决问题：

1. 查看 MinIO 官方文档：https://min.io/docs
2. 查看 Docker 日志：`docker-compose -f docker-compose.minio.yml logs`
3. 检查网络连接和防火墙设置
