# 文件上传功能文档

## 概述

Wenzbak 文件上传功能提供了将本地文件上传到远程存储的能力，支持加密和非加密两种模式。上传功能会自动比较本地和远程文件的 SHA256 哈希值，只有在不一致时才会执行实际上传，从而节省带宽和时间。

## 功能特性

- ✅ 自动文件路径拼接
- ✅ 支持加密模式
- ✅ SHA256 哈希值比较（避免重复上传）
- ✅ 自动上传 SHA256 校验文件
- ✅ 支持多种存储后端（S3、WebDAV、File）

## 快速开始

### 1. 创建配置

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';

var minioConfig = {
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
  storageConfig: jsonEncode(minioConfig),
);
```

### 2. 创建文件服务实例

```dart
import 'package:wenzbak/src/service/file/file.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';

var fileService = WenzbakFileServiceImpl(config);
```

### 3. 上传文件

```dart
var localFilePath = './my_file.txt';
var remotePath = await fileService.uploadFile(localFilePath);

if (remotePath != null) {
  print('文件上传成功，远程路径: $remotePath');
} else {
  print('文件上传失败');
}
```

## 详细说明

### 上传流程

1. **读取本地文件名，拼接远程文件路径**
   - 从本地文件路径中提取文件名
   - 使用 `config.getRemoteAssetPath()` 获取远程资源路径
   - 拼接为完整的远程文件路径

2. **加密处理（如果启用）**
   - 检查 `config.encryptFile` 是否为 `true`
   - 检查 `config.secretKey` 和 `config.secret` 是否不为空
   - 如果启用加密，使用 `WenzbakCryptUtil` 对文件进行加密
   - 加密后的文件保存到临时位置（`config.getLocalSecretAssetPath()`）
   - 远程路径会添加 `.enc` 后缀

3. **计算本地文件 SHA256**
   - 如果文件已加密，计算加密后文件的 SHA256
   - 如果文件未加密，计算原始文件的 SHA256

4. **读取远程文件 SHA256**
   - 尝试从远程存储读取 `$remotePath.sha256` 文件
   - 如果文件不存在，`remoteSha256` 为 `null`

5. **比较 SHA256 并上传**
   - 如果 `remoteSha256` 为 `null` 或与 `localSha256` 不一致，执行上传
   - 调用 `storage.uploadFile()` 上传文件
   - 调用 `storage.writeFile()` 上传 SHA256 校验文件

6. **返回远程路径**
   - 上传完成后返回远程文件路径
   - 如果文件已加密，路径包含 `.enc` 后缀

### 加密模式

启用加密模式后，文件会在上传前进行加密：

```dart
var encryptConfig = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 's3',
  storageConfig: jsonEncode(minioConfig),
  encryptFile: true,        // 启用加密
  secretKey: 'my-secret-key',  // 加密密钥
  secret: 'my-secret',      // 加密密码
);

var encryptFileService = WenzbakFileServiceImpl(encryptConfig);
var remotePath = await encryptFileService.uploadFile('./my_file.txt');
// remotePath 会是类似: wenzbak/public/assets/my_file.txt.enc
```

**注意事项：**
- 加密文件的远程路径会自动添加 `.enc` 后缀
- 加密后的文件会临时保存在本地，上传完成后自动删除
- 下载时需要相同的 `secretKey` 和 `secret` 才能解密

### SHA256 比较机制

上传功能会自动比较本地和远程文件的 SHA256 哈希值：

- **如果 SHA256 一致**：跳过上传，直接返回远程路径
- **如果 SHA256 不一致或远程文件不存在**：执行上传

这样可以避免重复上传相同的文件，节省带宽和时间。

### 远程文件路径规则

- **非加密模式**：`{remoteRootPath}/public/assets/{filename}`
- **加密模式**：`{remoteRootPath}/private/{secretKey}/assets/{filename}.enc`

## API 参考

### `uploadFile(String localPath)`

上传本地文件到远程存储。

**参数：**
- `localPath` (String): 本地文件路径

**返回值：**
- `Future<String?>`: 远程文件路径，如果上传失败返回 `null`

**异常：**
- `Exception`: 如果本地文件不存在
- `Exception`: 如果未配置存储服务
- 其他存储相关的异常

**示例：**

```dart
try {
  var remotePath = await fileService.uploadFile('./my_file.txt');
  if (remotePath != null) {
    print('上传成功: $remotePath');
  }
} catch (e) {
  print('上传失败: $e');
}
```

## 完整示例

### 示例 1: 上传普通文件

```dart
import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';

void main() async {
  var minioConfig = {
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
    storageConfig: jsonEncode(minioConfig),
  );

  var fileService = WenzbakFileServiceImpl(config);
  
  var testFile = File('./test.txt');
  await testFile.writeAsString('Hello, Wenzbak!');
  
  var remotePath = await fileService.uploadFile(testFile.path);
  print('上传成功: $remotePath');
}
```

### 示例 2: 上传加密文件

```dart
import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';

void main() async {
  var minioConfig = {
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
    storageConfig: jsonEncode(minioConfig),
    encryptFile: true,
    secretKey: 'my-secret-key',
    secret: 'my-secret',
  );

  var fileService = WenzbakFileServiceImpl(config);
  
  var testFile = File('./test.txt');
  await testFile.writeAsString('Secret content');
  
  var remotePath = await fileService.uploadFile(testFile.path);
  print('加密文件上传成功: $remotePath');
  // 输出: wenzbak/private/my-secret-key/assets/test.txt.enc
}
```

### 示例 3: 上传后下载验证

```dart
import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';

void main() async {
  var minioConfig = {
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
    storageConfig: jsonEncode(minioConfig),
  );

  var fileService = WenzbakFileServiceImpl(config);
  
  // 上传文件
  var testFile = File('./test.txt');
  await testFile.writeAsString('Test content');
  var remotePath = await fileService.uploadFile(testFile.path);
  
  if (remotePath != null) {
    // 下载文件
    var downloadedPath = await fileService.downloadFile(remotePath);
    
    if (downloadedPath != null) {
      var content = await File(downloadedPath).readAsString();
      print('下载的文件内容: $content');
    }
  }
}
```

## 运行测试

运行测试文件以验证功能：

```bash
dart run test/file_upload_test.dart
```

## 运行示例

运行示例程序：

```bash
dart run example/file_upload_example.dart
```

## 注意事项

1. **存储服务配置**：确保已正确配置存储服务（MinIO、WebDAV 或 File）
2. **存储桶/目录**：确保远程存储中已创建相应的存储桶或目录
3. **文件权限**：确保有权限读取本地文件和写入远程存储
4. **加密密钥**：如果使用加密模式，请妥善保管 `secretKey` 和 `secret`，丢失后将无法解密文件
5. **网络连接**：确保能够访问远程存储服务
6. **SHA256 文件**：上传时会自动创建 `$remotePath.sha256` 文件，用于后续的哈希值比较

## 故障排除

### 问题 1: 文件上传失败

**可能原因：**
- 存储服务未启动或配置错误
- 网络连接问题
- 存储桶/目录不存在
- 权限不足

**解决方法：**
1. 检查存储服务是否正常运行
2. 验证配置信息是否正确
3. 确保已创建存储桶/目录
4. 检查访问权限

### 问题 2: 加密文件上传失败

**可能原因：**
- `secretKey` 或 `secret` 为空
- 加密过程中出现错误

**解决方法：**
1. 确保 `encryptFile` 为 `true` 时，`secretKey` 和 `secret` 都不为空
2. 检查本地临时目录是否有写入权限

### 问题 3: SHA256 比较失败

**可能原因：**
- 远程 SHA256 文件格式不正确
- 文件在传输过程中损坏

**解决方法：**
1. 检查远程 SHA256 文件内容
2. 重新上传文件

## 相关文档

- [MinIO 快速开始](QUICKSTART_MINIO.md)
- [MinIO 故障排除](MINIO_TROUBLESHOOTING.md)
- [文件下载功能](../file/download.md)（待实现）

## 更新日志

- **v1.0.0** (2026-01-16): 初始版本，支持文件上传功能
