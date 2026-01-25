# 🔐 Wenzbak - 温知第三方数据同步系统

<div align="center">

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Dart](https://img.shields.io/badge/Dart-3.8%2B-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-Compatible-green.svg)](https://flutter.dev)

**帮助笔记类工具快速建立自己的数据备份功能，为用户数据提供安全保障**

[特性](#-核心特性) • [快速开始](#-快速开始) • [文档](#-文档) • [示例](#-使用示例) • [视频](#-视频介绍) • [贡献](#-贡献)

</div>

---

## 📖 项目简介

Wenzbak 是一个专为笔记类应用设计的数据备份系统，提供完整的数据备份、同步和加密解决方案。通过简单的 API 集成，让你的应用快速拥有企业级的数据备份能力。

### 🎥 视频介绍

📺 [B站视频介绍](https://www.bilibili.com/video/BV11rkLBZELG/)

### 🎯 为什么选择 Wenzbak？

- ✅ **开箱即用** - 几行代码即可集成完整的备份功能
- ✅ **多存储支持** - 支持 S3、WebDAV、本地文件系统等多种存储后端
- ✅ **数据安全** - 内置加密功能，保护用户隐私
- ✅ **增量同步** - 智能增量备份，节省带宽和时间
- ✅ **跨设备同步** - 支持多设备间的数据同步和消息推送
- ✅ **轻量级** - 纯 Dart 实现，无额外依赖

---

## ✨ 核心特性

### 📦 数据备份
- **增量备份** - 只同步变更的数据，大幅减少传输量
- **数据合并** - 自动合并历史数据，优化存储结构
- **断点续传** - 支持上传失败后自动重试

### 🔒 数据加密
- **端到端加密** - 支持 AES 加密，数据在传输和存储时都受到保护
- **密钥隔离** - 支持多密钥管理，不同密钥的数据完全隔离
- **可选加密** - 可选择启用或禁用加密功能

### 📁 文件管理
- **文件上传** - 支持任意文件类型的上传和下载
- **SHA256 校验** - 自动校验文件完整性，避免重复上传
- **临时文件** - 支持临时文件的自动清理机制

### 💬 消息同步
- **实时消息** - 支持跨设备的消息推送（轮询机制）
- **消息队列** - 可靠的消息队列，确保消息不丢失
- **自动重试** - 消息发送失败自动重试

### 🌐 多存储后端
- **S3 兼容** - 支持 AWS S3、MinIO 等 S3 兼容存储
- **WebDAV** - 支持 WebDAV 协议，兼容 Nextcloud、OwnCloud 等
- **本地文件** - 支持本地文件系统存储（用于测试）

### 📱 设备管理
- **设备信息** - 自动获取和管理设备信息
- **多设备支持** - 支持同一账户下的多设备管理
- **设备查询** - 快速查询所有设备信息

---

## 🚀 快速开始

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  wenzbak:
    git:
      url: https://github.com/lyming99/wenzbak.git
      ref: main
```

或者使用本地路径：

```yaml
dependencies:
  wenzbak:
    path: ../wenzbak
```

### 基本使用

#### 1. 配置存储后端

**方式一：直接注入 Storage 实例（推荐）**

```dart
import 'package:wenzbak/wenzbak.dart';
import 'package:wenzbak/src/service/storage/impl/s3_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/webdav_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/file_storage_client.dart';

// S3/MinIO
final s3Storage = S3StorageClient(
  config,
  'http://localhost:9000',
  'minioadmin',
  'minioadmin',
  'wenzbak',
  'us-east-1',
);
var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storage: s3Storage,  // 直接注入
);

// WebDAV
final webdavStorage = WebDAVStorageClient(
  config,
  'http://localhost:8080',
  'webdav',
  'webdav',
);
var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storage: webdavStorage,  // 直接注入
);

// 本地文件
final fileStorage = FileStorageClient(config, '/path/to/storage');
var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storage: fileStorage,  // 直接注入
);
```

**方式二：使用配置字符串（兼容旧方式）**

```dart
import 'dart:convert';
import 'package:wenzbak/wenzbak.dart';

// S3/MinIO
var s3Config = {
  'endpoint': 'http://localhost:9000',
  'accessKey': 'minioadmin',
  'secretKey': 'minioadmin',
  'bucket': 'wenzbak',
  'region': 'us-east-1',
};

var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 's3',
  storageConfig: jsonEncode(s3Config),
);

// WebDAV
var webdavConfig = {
  'url': 'http://localhost:8080',
  'username': 'webdav',
  'password': 'webdav',
};

var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 'webdav',
  storageConfig: jsonEncode(webdavConfig),
);
```

> **注意**：推荐使用方式一直接注入 Storage 实例，这样可以更好地支持自定义 Storage 实现和单元测试。

#### 2. 创建客户端

```dart
var backupClient = WenzbakClientServiceImpl(config);
```

#### 3. 上传设备信息

```dart
await backupClient.uploadDeviceInfo();
```

#### 4. 备份数据

```dart
// 添加数据到备份队列
await backupClient.addBackupData(
  WenzbakDataLine(
    createTime: DateTime.now(),
    content: "你的数据内容",
  ),
);

// 上传所有待备份的数据
await backupClient.uploadAllData(false);
```

#### 5. 下载数据

```dart
// 添加数据接收器
backupClient.addDataReceiver((line) async {
  print('收到数据: ${line.content}');
});

// 下载所有数据（增量下载）
await backupClient.downloadAllData();
```

---

## 📚 使用示例

### 数据备份示例

```dart
// 添加数据
await backupClient.addBackupData(
  WenzbakDataLine(
    createTime: DateTime.now(),
    content: "笔记内容",
  ),
);

// 上传数据
await backupClient.uploadAllData(false);

// 合并历史数据
await backupClient.mergeHistoryData();
```

### 文件上传示例

```dart
// 上传文件
var remotePath = await backupClient.uploadAssets('./local_file.txt');
if (remotePath != null) {
  print('文件上传成功: $remotePath');
}
```

### 消息同步示例

```dart
// 发送消息
var message = WenzbakMessage(
  uuid: Uuid().v4(),
  content: 'Hello from device-001!',
  timestamp: DateTime.now().millisecondsSinceEpoch,
);
await backupClient.messageService.sendMessage(message);

// 接收消息
backupClient.addMessageReceiver((message) async {
  print('收到消息: ${message.content}');
});

// 启动自动轮询
backupClient.startMessageTimer();
```

### 加密数据示例

```dart
var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 's3',
  storageConfig: jsonEncode(s3Config),
  secretKey: 'my-secret-key', // 启用加密
  encryptFile: true,           // 加密文件
);
```

更多示例请查看 [example](./example) 目录。

---

## 📖 文档

- [设备服务文档](./docs/device/DEVICE_SERVICE.md) - 设备信息管理
- [文件上传文档](./docs/file/upload.md) - 文件上传功能
- [MinIO 快速开始](./docs/minio/QUICKSTART_MINIO.md) - MinIO 存储配置
- [WebDAV 快速开始](./docs/webdav/QUICKSTART_WEBDAV.md) - WebDAV 存储配置
- [WebDAV 设置指南](./docs/webdav/WEBDAV_SETUP.md) - WebDAV 详细配置

---

## 🛠️ 支持的存储后端

| 存储类型 | 状态 | 说明 |
|---------|------|------|
| **S3** | ✅ 支持 | 支持 AWS S3、MinIO 等 S3 兼容存储 |
| **WebDAV** | ✅ 支持 | 支持 Nextcloud、OwnCloud 等 WebDAV 服务器 |
| **本地文件** | ✅ 支持 | 用于开发和测试 |
| **FTP/SFTP** | 🚧 计划中 | 即将支持 |

---

## 📋 功能路线图

- [x] 文件备份
- [x] 数据备份
- [x] 数据加密
- [x] 数据压缩优化
- [x] 增量同步
- [x] 实时消息（轮询）
- [x] WebDAV 支持
- [x] S3 支持
- [ ] FTP/SFTP 支持
- [ ] 更多存储后端支持

---

## 🤝 贡献

欢迎贡献代码！请遵循以下步骤：

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 开发指南

1. 克隆仓库
```bash
git clone https://github.com/lyming99/wenzbak.git
cd wenzbak
```

2. 安装依赖
```bash
dart pub get
```

3. 运行测试
```bash
dart test
```

---

## 📝 许可证

本项目采用 [Apache 2.0](LICENSE) 许可证。

---

## 🙏 致谢

感谢所有为这个项目做出贡献的开发者！

---

## 📮 联系方式

- 提交 Issue: [GitHub Issues](https://github.com/lyming99/wenzbak/issues)
- 讨论区: [GitHub Discussions](https://github.com/lyming99/wenzbak/discussions)

---

<div align="center">

**如果这个项目对你有帮助，请给一个 ⭐ Star！**

Made with ❤️ by the lyming99

</div>
