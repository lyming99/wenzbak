# 🔐 Wenzbak：为笔记应用打造的企业级数据备份解决方案

## 前言

在移动互联网时代，数据备份和同步已成为应用的核心功能之一。无论是笔记应用、待办事项工具，还是个人知识管理系统，都需要可靠的数据备份机制来保障用户数据安全。然而，从零开始构建一套完整的数据备份系统，需要处理加密、增量同步、多设备协调等诸多复杂问题，开发成本极高。

今天，我们为大家介绍一个专为笔记类应用设计的数据备份系统——**Wenzbak**，它可以帮助开发者快速集成企业级的数据备份能力，让应用在几分钟内拥有完整的数据同步功能。

## 什么是 Wenzbak？

Wenzbak（温知第三方数据同步系统）是一个专为笔记类应用设计的数据备份系统，提供完整的数据备份、同步和加密解决方案。通过简单的 API 集成，让你的应用快速拥有企业级的数据备份能力。

### 核心优势

- ✅ **开箱即用** - 几行代码即可集成完整的备份功能
- ✅ **多存储支持** - 支持 S3、WebDAV、本地文件系统等多种存储后端
- ✅ **数据安全** - 内置 AES-256 加密功能，保护用户隐私
- ✅ **增量同步** - 智能增量备份，节省带宽和时间
- ✅ **跨设备同步** - 支持多设备间的数据同步和消息推送
- ✅ **轻量级** - 纯 Dart 实现，无额外依赖

## 核心功能特性

### 📦 数据备份

**增量备份机制**

Wenzbak 采用基于时间块的数据组织方式，实现了高效的增量备份：

- 数据按小时为单位进行组织，避免文件数量过多
- 只同步变更的数据，大幅减少传输量
- 自动合并历史数据，优化存储结构
- 支持断点续传，上传失败后自动重试

**数据组织架构**

```
wenzbak/
  └── public/
      └── data/
          └── 2026-01-20/
              └── 00/
                  ├── 2026-01-20-00-[uuid].gz      # 压缩后的数据块
                  └── 2026-01-20-00-[uuid].gz.sha256 # SHA256 校验文件
```

### 🔒 数据加密

**端到端加密保护**

Wenzbak 内置了强大的加密功能，确保数据在传输和存储时都受到保护：

- **AES-256-CBC 加密算法**：采用业界标准的 AES-256 加密
- **PBKDF2 密钥派生**：使用 PBKDF2 增强密钥强度，防止暴力破解
- **密钥隔离**：支持多密钥管理，不同密钥的数据完全隔离
- **可选加密**：可根据需求选择启用或禁用加密功能

**加密流程**

```dart
// 启用加密的配置
var config = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 's3',
  storageConfig: jsonEncode(s3Config),
  secretKey: 'my-secret-key',  // 加密密钥
  secret: 'my-secret',          // 加密密码
  encryptFile: true,            // 启用文件加密
);
```

### 📁 文件管理

**智能文件上传**

- 支持任意文件类型的上传和下载
- **SHA256 校验机制**：自动校验文件完整性，避免重复上传
- 临时文件自动清理，节省存储空间
- 支持加密文件上传，保护敏感文件

**文件去重机制**

Wenzbak 通过 SHA256 哈希值比较，实现智能去重：

1. 上传前计算本地文件的 SHA256
2. 读取远程文件的 SHA256（如果存在）
3. 只有当哈希值不一致时才上传
4. 大幅减少不必要的网络传输

### 💬 消息同步

**跨设备实时同步**

- 支持跨设备的消息推送（基于轮询机制）
- 可靠的消息队列，确保消息不丢失
- 自动重试机制，提高消息送达率
- 支持多设备管理，统一账户下的设备协调

### 🌐 多存储后端

**灵活的存储方案**

Wenzbak 支持多种存储后端，可根据实际需求选择：

| 存储类型 | 状态 | 说明 |
|---------|------|------|
| **S3** | ✅ 支持 | 支持 AWS S3、MinIO 等 S3 兼容存储 |
| **WebDAV** | ✅ 支持 | 支持 Nextcloud、OwnCloud 等 WebDAV 服务器 |
| **本地文件** | ✅ 支持 | 用于开发和测试 |
| **FTP/SFTP** | 🚧 计划中 | 即将支持 |

## 快速开始

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  wenzbak:
    git:
      url: https://github.com/lyming99/wenzbak.git
      ref: main
```

### 基本使用

#### 1. 配置存储后端

**使用 S3/MinIO：**

```dart
import 'dart:convert';
import 'package:wenzbak/wenzbak.dart';

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
```

**使用 WebDAV：**

```dart
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

#### 2. 创建客户端并备份数据

```dart
// 创建客户端
var backupClient = WenzbakClientServiceImpl(config);

// 上传设备信息
await backupClient.uploadDeviceInfo();

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

#### 3. 下载数据

```dart
// 添加数据接收器
backupClient.addDataReceiver((line) async {
  print('收到数据: ${line.content}');
});

// 下载所有数据（增量下载）
await backupClient.downloadAllData();
```

## 技术架构亮点

### 📊 数据组织

- **基于时间块的数据组织方式**：便于增量同步和快速定位
- **自动索引管理**：快速定位数据位置，提高查询效率
- **Gzip 压缩优化**：减少存储空间和传输带宽

### 🔐 安全机制

- **AES-256 加密算法**：保障数据安全
- **PBKDF2 密钥派生函数**：增强密钥强度
- **文件和数据双重加密支持**：多层次安全保护

### ⚡ 性能优化

- **增量同步算法**：只传输变更数据，节省带宽
- **并发上传控制**：优化网络资源使用
- **本地缓存机制**：减少重复下载，提高响应速度

### 🛠️ 开发体验

- **纯 Dart 实现**：跨平台支持，无额外依赖
- **简洁的 API 设计**：易于集成和使用
- **完善的错误处理**：提供详细的错误信息和日志记录
- **丰富的示例代码**：快速上手，降低学习成本

## 使用场景

### 1. 笔记应用

为笔记应用快速集成数据备份功能，支持多设备同步，确保用户数据安全。

### 2. 待办事项工具

实现待办事项的跨设备同步，用户可以在任何设备上查看和编辑任务。

### 3. 个人知识管理系统

为知识管理工具提供可靠的数据备份，支持加密存储，保护用户隐私。

### 4. 日记应用

为日记应用提供端到端加密备份，确保用户隐私数据安全。

## 项目特色

### 1. 轻量级设计

Wenzbak 采用纯 Dart 实现，无额外依赖，体积小，性能高。

### 2. 灵活配置

支持多种存储后端，可根据实际需求选择最适合的方案。

### 3. 安全可靠

内置加密功能，支持端到端加密，确保数据安全。

### 4. 易于集成

简洁的 API 设计，几行代码即可集成完整的备份功能。

## 开源地址

**GitHub 仓库：** https://github.com/lyming99/wenzbak

**许可证：** Apache 2.0

**贡献：** 欢迎提交 Issue 和 Pull Request，共同完善项目！

如果这个项目对你有帮助，请给一个 ⭐ Star！

## 总结

Wenzbak 为笔记类应用提供了一个完整、可靠、安全的数据备份解决方案。通过简单的 API 集成，开发者可以在几分钟内为应用添加企业级的数据备份功能，大大降低了开发成本和时间。

无论是个人开发者还是团队项目，Wenzbak 都能帮助你快速实现数据备份和同步功能，让用户数据得到更好的保护。

---

**Made with ❤️ by lyming99**

更多技术细节和使用文档，请访问 GitHub 仓库：https://github.com/lyming99/wenzbak
