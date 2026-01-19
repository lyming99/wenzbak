# WebDAV 服务详细配置指南

## 概述

WebDAV (Web Distributed Authoring and Versioning) 是一个基于 HTTP 的协议，允许客户端进行远程 Web 内容创作。本项目使用 Docker 容器化的 WebDAV 服务器，方便本地开发和测试。

## 架构说明

```
┌─────────────────┐
│  Dart 应用      │
│  (wenzbak)      │
└────────┬────────┘
         │ HTTP/WebDAV
         │ (PUT, GET, DELETE, MKCOL, PROPFIND)
         ▼
┌─────────────────┐
│  WebDAV 服务器  │
│  (bytemark)     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Docker Volume  │
│  (webdav_data)  │
└─────────────────┘
```

## 服务配置

### 基本配置

服务使用 `bytemark/webdav` Docker 镜像，这是一个基于 Apache 的轻量级 WebDAV 服务器。

**默认配置：**
- 端口: 8080 (映射到容器内的 80)
- 用户名: webdav
- 密码: webdav
- 数据目录: /var/lib/dav (容器内)

### 环境变量

| 变量名 | 说明 | 默认值 | 必需 |
|--------|------|--------|------|
| USERNAME | WebDAV 用户名 | webdav | 否 |
| PASSWORD | WebDAV 密码 | webdav | 否 |
| PASSWORD_FILE | 密码文件路径 | - | 否 |

**注意**: `PASSWORD` 和 `PASSWORD_FILE` 只能使用其中一个。

## 高级配置

### 1. 多用户配置

使用密码文件支持多用户：

```yaml
services:
  webdav:
    image: bytemark/webdav:latest
    environment:
      PASSWORD_FILE: /etc/webdav/passwd
    volumes:
      - webdav_data:/var/lib/dav
      - ./passwd:/etc/webdav/passwd:ro
```

创建密码文件：
```bash
# 安装 htpasswd (Apache 工具)
# Ubuntu/Debian: apt-get install apache2-utils
# CentOS/RHEL: yum install httpd-tools
# Mac: brew install httpd

# 创建密码文件
htpasswd -c passwd user1
htpasswd passwd user2
```

### 2. 自定义端口

修改 `docker-compose.webdav.yml`：
```yaml
ports:
  - "9000:80"  # 外部端口:容器端口
```

### 3. 数据持久化

数据默认存储在 Docker volume `webdav_data` 中。如果需要指定本地目录：

```yaml
volumes:
  - ./webdav_storage:/var/lib/dav
```

### 4. HTTPS 配置

生产环境建议使用 HTTPS。可以通过 Nginx 反向代理实现：

```yaml
# docker-compose.webdav-https.yml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "8443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - webdav

  webdav:
    image: bytemark/webdav:latest
    expose:
      - "80"
    environment:
      USERNAME: webdav
      PASSWORD: webdav
    volumes:
      - webdav_data:/var/lib/dav
```

## 性能优化

### 1. 资源限制

```yaml
services:
  webdav:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
```

### 2. 日志配置

```yaml
services:
  webdav:
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

## 安全建议

1. **修改默认密码**: 生产环境必须修改默认用户名和密码
2. **使用 HTTPS**: 通过反向代理配置 SSL/TLS
3. **限制访问**: 使用防火墙规则限制访问来源
4. **定期备份**: 定期备份 `webdav_data` volume
5. **监控日志**: 定期检查访问日志，发现异常行为

## 故障排除

### 问题 1: 容器无法启动

**症状**: `docker-compose up` 失败

**解决方案**:
1. 检查端口是否被占用: `netstat -an | grep 8080`
2. 查看详细日志: `docker-compose logs webdav`
3. 检查 Docker 资源: `docker system df`

### 问题 2: 无法上传文件

**症状**: PUT 请求返回 403 或 500

**解决方案**:
1. 检查数据目录权限: `docker exec wenzbak-webdav ls -la /var/lib/dav`
2. 修复权限: `docker exec wenzbak-webdav chown -R www-data:www-data /var/lib/dav`
3. 检查磁盘空间: `docker exec wenzbak-webdav df -h`

### 问题 3: 连接超时

**症状**: 客户端连接超时

**解决方案**:
1. 检查容器状态: `docker ps | grep webdav`
2. 检查网络连接: `docker exec wenzbak-webdav ping -c 3 8.8.8.8`
3. 检查防火墙规则

### 问题 4: 认证失败

**症状**: 返回 401 Unauthorized

**解决方案**:
1. 验证用户名密码是否正确
2. 检查环境变量是否正确设置
3. 查看容器日志: `docker-compose logs webdav`

## 备份和恢复

### 备份数据

```bash
# 备份 volume
docker run --rm -v wenzbak_webdav_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/webdav_backup_$(date +%Y%m%d).tar.gz -C /data .
```

### 恢复数据

```bash
# 恢复 volume
docker run --rm -v wenzbak_webdav_data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/webdav_backup_YYYYMMDD.tar.gz -C /data
```

## 监控和维护

### 健康检查

服务已配置健康检查，可以通过以下命令查看：
```bash
docker inspect wenzbak-webdav | grep -A 10 Health
```

### 查看访问日志

```bash
docker exec wenzbak-webdav tail -f /var/log/apache2/access.log
```

### 查看错误日志

```bash
docker exec wenzbak-webdav tail -f /var/log/apache2/error.log
```

## 与其他存储方案对比

| 特性 | WebDAV | MinIO (S3) | 本地文件系统 |
|------|--------|------------|--------------|
| 协议 | HTTP/WebDAV | S3 API | 文件系统 |
| 网络访问 | ✅ | ✅ | ❌ |
| 标准兼容 | ✅ (RFC 4918) | ✅ (S3) | N/A |
| 客户端支持 | 广泛 | 广泛 | 本地 |
| 性能 | 中等 | 高 | 最高 |
| 配置复杂度 | 低 | 中 | 最低 |

## 参考资源

- [WebDAV RFC 4918](https://tools.ietf.org/html/rfc4918)
- [bytemark/webdav Docker Hub](https://hub.docker.com/r/bytemark/webdav)
- [Apache WebDAV 文档](https://httpd.apache.org/docs/current/mod/mod_dav.html)
