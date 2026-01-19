# MinIO 本地存储服务 - 快速开始

## 🚀 5 分钟快速搭建

### 步骤 0: 配置 Docker 镜像加速器（重要！）

**如果遇到镜像拉取失败，必须先配置镜像加速器！**

**Windows (推荐使用脚本):**
```powershell
.\scripts\setup_docker_mirror.ps1
```

**或手动配置:**
1. 打开 Docker Desktop
2. Settings → Docker Engine
3. 添加以下配置：
```json
{
  "registry-mirrors": [
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```
4. 点击 "Apply & Restart"

### 步骤 1: 启动 MinIO 服务

**注意：MinIO 官方已停止提供预编译 Docker 镜像，我们使用第三方构建的镜像**

**直接启动（推荐使用 coollabsio/minio）：**
```bash
docker-compose -f docker-compose.minio.yml up -d
```

**如果无法拉取，尝试 Bitnami 镜像：**
```bash
docker-compose -f docker-compose.minio.bitnami.yml up -d
```

**如果仍然失败，先配置镜像加速器（见步骤 0），然后使用脚本拉取：**
```powershell
.\scripts\pull_minio_image.ps1
```

### 步骤 2: 访问控制台并创建存储桶

1. 打开浏览器访问：http://localhost:9001
2. 使用以下凭据登录：
   - 用户名：`minioadmin`
   - 密码：`minioadmin`
3. 点击左侧菜单 "Buckets" → "Create Bucket"
4. 输入存储桶名称：`wenzbak`
5. 点击 "Create Bucket"

### 步骤 3: 测试连接

运行示例代码：

```bash
dart run example/minio_example.dart
```

## 📝 在代码中使用

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

void main() async {
  // MinIO 配置
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建配置
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './local_backup',
    remoteRootPath: '/',
    storageType: 's3',  // MinIO 使用 s3 类型
    storageConfig: jsonEncode(minioConfig),
  );

  // 获取存储客户端
  var storage = WenzbakStorageClientService.getInstance(config);
  
  // 使用存储客户端...
  await storage?.writeFile('test.txt', Uint8List.fromList([1, 2, 3]));
}
```

## 🔧 常用命令

### 启动服务
```bash
docker-compose -f docker-compose.minio.yml up -d
```

### 停止服务
```bash
docker-compose -f docker-compose.minio.yml down
```

### 查看日志
```bash
docker-compose -f docker-compose.minio.yml logs -f
```

### 查看服务状态
```bash
docker ps | grep minio
```

## 🆘 遇到问题？

### 镜像拉取失败
1. **首先配置 Docker 镜像加速器**（见步骤 0）
2. 使用拉取脚本：`.\scripts\pull_minio_image.ps1`
3. 查看详细故障排除指南：[docs/MINIO_TROUBLESHOOTING.md](docs/MINIO_TROUBLESHOOTING.md)

### 其他问题
查看完整故障排除指南：[docs/MINIO_TROUBLESHOOTING.md](docs/MINIO_TROUBLESHOOTING.md)

## 📚 更多信息

详细文档请查看：[docs/MINIO_SETUP.md](docs/MINIO_SETUP.md)

## ⚠️ 注意事项

1. **默认配置仅用于开发环境**，生产环境请修改密码
2. **确保已创建存储桶**，否则会报错
3. **数据存储在 Docker volume** 中，删除容器不会丢失数据
4. **如果无法拉取镜像，必须先配置 Docker 镜像加速器**
