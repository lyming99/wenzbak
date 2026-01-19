# WebDAV 本地存储服务 - 快速开始

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

### 步骤 1: 启动 WebDAV 服务

**使用脚本启动（推荐）：**

**Windows:**
```powershell
.\scripts\start_webdav.ps1
```

**Linux/Mac:**
```bash
chmod +x scripts/start_webdav.sh
./scripts/start_webdav.sh
```

**或直接使用 docker-compose:**
```bash
docker-compose -f docker-compose.webdav.yml up -d
```

### 步骤 2: 验证服务

访问 WebDAV 服务：
- URL: http://localhost:8080
- 用户名: `webdav`
- 密码: `webdav`

你可以使用以下方式验证：
1. **浏览器访问**: 打开 http://localhost:8080，应该能看到文件列表（如果已创建文件）
2. **文件管理器挂载**: 
   - Windows: 在文件资源管理器中，右键"此电脑" → "映射网络驱动器" → 输入 `http://localhost:8080`
   - Mac: Finder → 前往 → 连接服务器 → 输入 `http://localhost:8080`
   - Linux: 使用 `davfs2` 或 `rclone`

### 步骤 3: 测试连接

运行示例代码（如果存在）：
```bash
dart run example/webdav_example.dart
```

## 📝 在代码中使用

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

void main() async {
  // WebDAV 配置
  var webdavConfig = {
    'url': 'http://localhost:8080',
    'username': 'webdav',
    'password': 'webdav',
  };

  // 创建配置
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './local_backup',
    remoteRootPath: '/',
    storageType: 'webdav',
    storageConfig: jsonEncode(webdavConfig),
  );

  // 获取存储客户端
  var storage = WenzbakStorageClientService.getInstance(config);
  
  // 使用存储客户端...
  await storage?.writeFile('test.txt', Uint8List.fromList([1, 2, 3]));
  
  // 读取文件
  var data = await storage?.readFile('test.txt');
  print('读取到的数据: $data');
  
  // 列出文件
  var files = await storage?.listFiles('/');
  print('文件列表: $files');
}
```

## 🔧 常用命令

### 启动服务
```bash
docker-compose -f docker-compose.webdav.yml up -d
```

### 停止服务
```bash
docker-compose -f docker-compose.webdav.yml down
```

### 查看日志
```bash
docker-compose -f docker-compose.webdav.yml logs -f
```

### 查看服务状态
```bash
docker ps | grep webdav
```

### 进入容器
```bash
docker exec -it wenzbak-webdav sh
```

## 🔐 修改用户名和密码

### 方法 1: 修改环境变量（推荐）

编辑 `docker-compose.webdav.yml` 文件：
```yaml
environment:
  USERNAME: your_username
  PASSWORD: your_password
```

然后重启服务：
```bash
docker-compose -f docker-compose.webdav.yml down
docker-compose -f docker-compose.webdav.yml up -d
```

### 方法 2: 使用密码文件

1. 创建密码文件（使用 htpasswd）：
```bash
htpasswd -c /path/to/passwd webdav
```

2. 修改 `docker-compose.webdav.yml`：
```yaml
environment:
  USERNAME: webdav
  PASSWORD_FILE: /etc/webdav/passwd
volumes:
  - webdav_data:/var/lib/dav
  - /path/to/passwd:/etc/webdav/passwd:ro
```

## 🆘 遇到问题？

### 端口被占用

如果 8080 端口被占用，可以修改 `docker-compose.webdav.yml` 中的端口映射：
```yaml
ports:
  - "8081:80"  # 改为其他端口，如 8081
```

### 镜像拉取失败

1. **首先配置 Docker 镜像加速器**（见步骤 0）
2. 手动拉取镜像：
```bash
docker pull bytemark/webdav:latest
```

### 无法访问服务

1. 检查容器是否运行：
```bash
docker ps | grep webdav
```

2. 查看容器日志：
```bash
docker-compose -f docker-compose.webdav.yml logs
```

3. 检查防火墙设置，确保端口 8080 已开放

### 权限问题

如果遇到文件权限问题，可以修改数据卷的权限：
```bash
docker exec -it wenzbak-webdav chown -R www-data:www-data /var/lib/dav
```

## 📚 更多信息

- WebDAV 协议说明: https://tools.ietf.org/html/rfc4918
- bytemark/webdav 镜像: https://hub.docker.com/r/bytemark/webdav

## ⚠️ 注意事项

1. **默认配置仅用于开发环境**，生产环境请修改密码
2. **数据存储在 Docker volume** 中，删除容器不会丢失数据
3. **如果无法拉取镜像，必须先配置 Docker 镜像加速器**
4. **生产环境建议使用 HTTPS**，可以通过反向代理（如 Nginx）配置 SSL
