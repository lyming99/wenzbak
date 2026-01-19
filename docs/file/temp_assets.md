# 临时文件上传与清除功能文档

## 概述

Wenzbak 临时文件上传功能提供了将本地文件上传到远程存储的临时目录的能力，支持加密和非加密两种模式。临时文件会在文件名前自动添加时间前缀（`yyyy-MM-dd-HH`），方便根据时间进行管理和自动清除。

## 功能特性

- ✅ 自动添加时间前缀（`yyyy-MM-dd-HH-{原文件名}`）
- ✅ 支持加密模式
- ✅ 自动上传 SHA256 校验文件
- ✅ 自动清除1天前的临时文件
- ✅ 支持多种存储后端（S3、WebDAV、File）
- ✅ 临时文件存储在独立的 `tempAssets` 目录

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

### 3. 上传临时文件

```dart
var localFilePath = './my_temp_file.txt';
var remotePath = await fileService.uploadTempFile(localFilePath);

if (remotePath != null) {
  print('临时文件上传成功，远程路径: $remotePath');
  // 输出示例: wenzbak/public/tempAssets/2026-01-16-14-my_temp_file.txt
} else {
  print('临时文件上传失败');
}
```

### 4. 清除过期临时文件

```dart
await fileService.deleteTempFile();
print('已清除1天前的临时文件');
```

## 详细说明

### 上传流程

1. **读取本地文件名，拼接远程文件路径**
   - 从本地文件路径中提取文件名
   - 获取当前时间，生成时间前缀（格式：`yyyy-MM-dd-HH`）
   - 生成远程文件名：`{时间前缀}-{原文件名}`
   - 使用 `config.getRemoteTempAssetPath()` 获取临时资源路径
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

4. **上传文件**
   - 调用 `storage.uploadFile()` 上传文件
   - 调用 `storage.writeFile()` 上传 SHA256 校验文件

5. **返回远程路径**
   - 上传完成后返回远程文件路径
   - 如果文件已加密，路径包含 `.enc` 后缀

### 清除流程

1. **获取临时文件目录**
   - 使用 `config.getRemoteTempAssetPath()` 获取临时资源路径

2. **列出所有文件**
   - 调用 `storage.listFiles()` 列出目录下的所有文件

3. **解析文件名中的时间信息**
   - 从文件名中提取时间前缀（格式：`yyyy-MM-dd-HH`）
   - 支持格式：
     - `yyyy-MM-dd-HH-{原文件名}`
     - `yyyy-MM-dd-HH-{原文件名}.enc`

4. **判断是否超过1天**
   - 计算1天前的时间
   - 比较文件时间与1天前的时间
   - 如果文件时间早于1天前，标记为需要删除

5. **删除过期文件**
   - 删除主文件
   - 同时删除对应的 SHA256 文件（`{文件路径}.sha256`）

### 加密模式

启用加密模式后，临时文件会在上传前进行加密：

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
var remotePath = await encryptFileService.uploadTempFile('./my_temp_file.txt');
// remotePath 会是类似: wenzbak/private/my-secret-key/tempAssets/2026-01-16-14-my_temp_file.txt.enc
```

**注意事项：**
- 加密文件的远程路径会自动添加 `.enc` 后缀
- 加密后的文件会临时保存在本地，上传完成后自动删除
- 文件名格式：`yyyy-MM-dd-HH-{原文件名}.enc`

### 时间前缀格式

临时文件的文件名会自动添加时间前缀，格式为：`yyyy-MM-dd-HH-{原文件名}`

**示例：**
- 原文件名：`test.txt`
- 上传时间：2026年1月16日 14时
- 远程文件名：`2026-01-16-14-test.txt`

**加密文件示例：**
- 原文件名：`test.txt`
- 上传时间：2026年1月16日 14时
- 远程文件名：`2026-01-16-14-test.txt.enc`

### 远程文件路径规则

- **非加密模式**：`{remoteRootPath}/public/tempAssets/{yyyy-MM-dd-HH-{原文件名}}`
- **加密模式**：`{remoteRootPath}/private/{secretKey}/tempAssets/{yyyy-MM-dd-HH-{原文件名}}.enc`

### 自动清除机制

`deleteTempFile()` 方法会自动清除1天前的临时文件：

- **清除条件**：文件时间早于当前时间减去1天
- **清除范围**：`tempAssets` 目录下的所有过期文件
- **同时清除**：主文件和对应的 SHA256 文件

**使用建议：**
- 可以定期调用 `deleteTempFile()` 方法清理过期文件
- 建议在应用启动时或定时任务中调用
- 清除操作是安全的，不会影响新上传的文件

## API 参考

### `uploadTempFile(String localPath)`

上传本地文件到远程存储的临时目录。

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
  var remotePath = await fileService.uploadTempFile('./my_temp_file.txt');
  if (remotePath != null) {
    print('上传成功: $remotePath');
  }
} catch (e) {
  print('上传失败: $e');
}
```

### `deleteTempFile()`

清除1天前的临时文件。

**返回值：**
- `Future<void>`

**异常：**
- `Exception`: 如果未配置存储服务
- 其他存储相关的异常

**示例：**

```dart
try {
  await fileService.deleteTempFile();
  print('清除操作完成');
} catch (e) {
  print('清除失败: $e');
}
```

## 完整示例

### 示例 1: 上传临时文件

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
  
  var testFile = File('./temp_test.txt');
  await testFile.writeAsString('Hello, Wenzbak!');
  
  var remotePath = await fileService.uploadTempFile(testFile.path);
  print('上传成功: $remotePath');
  // 输出: wenzbak/public/tempAssets/2026-01-16-14-temp_test.txt
}
```

### 示例 2: 上传加密临时文件

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
  
  var testFile = File('./temp_secret.txt');
  await testFile.writeAsString('Secret content');
  
  var remotePath = await fileService.uploadTempFile(testFile.path);
  print('加密临时文件上传成功: $remotePath');
  // 输出: wenzbak/private/my-secret-key/tempAssets/2026-01-16-14-temp_secret.txt.enc
}
```

### 示例 3: 清除过期临时文件

```dart
import 'dart:convert';
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
  
  // 清除1天前的临时文件
  await fileService.deleteTempFile();
  print('已清除1天前的临时文件');
}
```

### 示例 4: 定期清除临时文件

```dart
import 'dart:async';
import 'dart:convert';
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
  
  // 每24小时清除一次过期临时文件
  Timer.periodic(Duration(hours: 24), (timer) async {
    try {
      await fileService.deleteTempFile();
      print('定期清除完成: ${DateTime.now()}');
    } catch (e) {
      print('定期清除失败: $e');
    }
  });
  
  print('定期清除任务已启动');
}
```

## 运行测试

运行测试文件以验证功能：

```bash
dart run test/temp_file_upload_test.dart
```

## 运行示例

运行示例程序：

```bash
dart run example/temp_file_upload_example.dart
```

## 注意事项

1. **存储服务配置**：确保已正确配置存储服务（MinIO、WebDAV 或 File）
2. **存储桶/目录**：确保远程存储中已创建相应的存储桶或目录
3. **文件权限**：确保有权限读取本地文件和写入远程存储
4. **加密密钥**：如果使用加密模式，请妥善保管 `secretKey` 和 `secret`，丢失后将无法解密文件
5. **网络连接**：确保能够访问远程存储服务
6. **SHA256 文件**：上传时会自动创建 `$remotePath.sha256` 文件，用于文件完整性校验
7. **时间前缀**：文件名会自动添加时间前缀，格式为 `yyyy-MM-dd-HH-{原文件名}`
8. **自动清除**：`deleteTempFile()` 方法会清除1天前的临时文件，新上传的文件不会被清除
9. **清除时机**：建议定期调用 `deleteTempFile()` 方法，可以在应用启动时或使用定时任务

## 故障排除

### 问题 1: 临时文件上传失败

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

### 问题 2: 加密临时文件上传失败

**可能原因：**
- `secretKey` 或 `secret` 为空
- 加密过程中出现错误

**解决方法：**
1. 确保 `encryptFile` 为 `true` 时，`secretKey` 和 `secret` 都不为空
2. 检查本地临时目录是否有写入权限

### 问题 3: 清除操作没有删除文件

**可能原因：**
- 文件时间前缀格式不正确
- 文件时间未超过1天
- 文件路径解析失败

**解决方法：**
1. 检查文件名格式是否正确（`yyyy-MM-dd-HH-{原文件名}`）
2. 确认文件确实是1天前上传的
3. 查看错误日志了解具体原因

### 问题 4: 时间前缀格式不正确

**可能原因：**
- 系统时间不正确
- 文件名生成逻辑错误

**解决方法：**
1. 检查系统时间是否正确
2. 验证时间前缀格式是否符合 `yyyy-MM-dd-HH` 格式

## 与普通文件上传的区别

| 特性 | 普通文件上传 (`uploadFile`) | 临时文件上传 (`uploadTempFile`) |
|------|---------------------------|-------------------------------|
| 文件路径 | `{remoteRootPath}/public/assets/` | `{remoteRootPath}/public/tempAssets/` |
| 文件名 | 保持原文件名 | 添加时间前缀 `yyyy-MM-dd-HH-{原文件名}` |
| SHA256 比较 | 会检查远程文件，相同则跳过上传 | 直接上传，不检查远程文件 |
| 自动清除 | 不支持 | 支持清除1天前的文件 |
| 使用场景 | 永久存储的文件 | 临时文件，需要定期清理 |

## 相关文档

- [文件上传功能](upload.md) - 普通文件上传功能
- [MinIO 快速开始](../minio/QUICKSTART_MINIO.md)
- [MinIO 故障排除](../minio/MINIO_TROUBLESHOOTING.md)

## 更新日志

- **v1.0.0** (2026-01-16): 初始版本，支持临时文件上传和自动清除功能
