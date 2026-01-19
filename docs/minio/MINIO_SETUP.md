# MinIO 本地存储服务搭建指南

MinIO 是一个高性能的对象存储服务，完全兼容 Amazon S3 API。本指南将帮助您快速搭建一个本地 MinIO 存储服务用于 wenzbak 备份系统。

## 方式一：使用 Docker Compose（推荐）

### 1. 启动 MinIO 服务

```bash
# 使用提供的 docker-compose 文件启动 MinIO
docker-compose -f docker-compose.minio.yml up -d
```

### 2. 访问 MinIO 控制台

打开浏览器访问：http://localhost:9001

- 用户名：`minioadmin`
- 密码：`minioadmin`

### 3. 创建存储桶（Bucket）

1. 登录 MinIO 控制台
2. 点击左侧菜单的 "Buckets"
3. 点击 "Create Bucket"
4. 输入存储桶名称（例如：`wenzbak`）
5. 点击 "Create Bucket" 完成创建

### 4. 配置 wenzbak

在您的 Dart 代码中配置 MinIO：

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';

var minioConfig = {
  'endpoint': 'http://localhost:9000',
  'accessKey': 'minioadmin',
  'secretKey': 'minioadmin',
  'bucket': 'wenzbak',
  'region': 'us-east-1',  // MinIO 可以使用任意区域值
};

var config = WenzbakConfig(
  deviceId: 'your-device-id',
  localRootPath: './local_backup',
  remoteRootPath: '/',
  storageType: 's3',
  storageConfig: jsonEncode(minioConfig),
);
```

## 方式二：直接使用 Docker

### 1. 启动 MinIO 容器

```bash
docker run -d \
  -p 9000:9000 \
  -p 9001:9001 \
  --name wenzbak-minio \
  -e "MINIO_ROOT_USER=minioadmin" \
  -e "MINIO_ROOT_PASSWORD=minioadmin" \
  -v minio_data:/data \
  minio/minio server /data --console-address ":9001"
```

### 2. 后续步骤

按照方式一的步骤 2-4 继续操作。

## 方式三：本地安装（Windows）

### 1. 下载 MinIO

访问 https://min.io/download 下载 Windows 版本的 MinIO。

### 2. 启动 MinIO

```powershell
# 设置环境变量
$env:MINIO_ROOT_USER="minioadmin"
$env:MINIO_ROOT_PASSWORD="minioadmin"

# 启动 MinIO（API 端口 9000，控制台端口 9001）
.\minio.exe server D:\minio-data --console-address ":9001"
```

### 3. 后续步骤

按照方式一的步骤 2-4 继续操作。

## 配置说明

### 默认配置

使用 `docker-compose.minio.yml` 启动的 MinIO 默认配置：

- **API 端点**: `http://localhost:9000`
- **控制台地址**: `http://localhost:9001`
- **管理员用户名**: `minioadmin`
- **管理员密码**: `minioadmin`

### 安全建议

⚠️ **重要**：默认配置仅用于开发环境！

生产环境请：

1. 修改默认密码：
   ```bash
   # 在 docker-compose.minio.yml 中修改
   MINIO_ROOT_USER: your-username
   MINIO_ROOT_PASSWORD: your-strong-password
   ```

2. 使用环境变量文件（`.env`）存储敏感信息

3. 配置 HTTPS

4. 设置访问策略和 IAM 用户

## 测试连接

运行示例代码测试 MinIO 连接：

```bash
dart run example/minio_example.dart
```

## 常见问题

### 1. 端口被占用

如果 9000 或 9001 端口被占用，可以修改 `docker-compose.minio.yml` 中的端口映射：

```yaml
ports:
  - "9002:9000"  # 将 API 端口改为 9002
  - "9003:9001"  # 将控制台端口改为 9003
```

然后在配置中使用新的端口：
```dart
'endpoint': 'http://localhost:9002',
```

### 2. 无法访问控制台

- 检查防火墙设置
- 确认容器正在运行：`docker ps`
- 查看容器日志：`docker logs wenzbak-minio`

### 3. 存储桶不存在

确保在使用前已在 MinIO 控制台创建了存储桶。

### 4. 认证失败

- 检查 accessKey 和 secretKey 是否正确
- 确认使用的是管理员账户或已创建的用户账户

## 数据持久化

使用 Docker Compose 启动时，数据会保存在 Docker volume `minio_data` 中。要查看数据位置：

```bash
docker volume inspect wenzbak_minio_data
```

要备份数据，可以导出 volume：

```bash
docker run --rm -v wenzbak_minio_data:/data -v $(pwd):/backup alpine tar czf /backup/minio-backup.tar.gz -C /data .
```

## 更多信息

- MinIO 官方文档：https://min.io/docs
- MinIO Docker 镜像：https://hub.docker.com/r/minio/minio
