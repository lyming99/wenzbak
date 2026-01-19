# 设备服务功能文档

## 概述

Wenzbak 设备服务提供了设备信息的上传和查询功能。设备信息包括设备ID、平台、设备型号、操作系统版本、设备名称和更新时间戳等。设备信息可以自动获取，也可以手动指定，并支持本地缓存以提高查询效率。

## 功能特性

- ✅ 自动获取当前设备信息
- ✅ 手动指定设备信息上传
- ✅ 查询所有设备信息
- ✅ 查询指定设备信息
- ✅ 本地缓存机制
- ✅ 支持私有密钥隔离
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

### 2. 创建设备服务实例

```dart
import 'package:wenzbak/src/service/device/device.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

var deviceService = WenzbakDeviceServiceImpl(config);
```

### 3. 获取当前设备信息

```dart
var deviceInfo = await deviceService.getDeviceSystemInfo();
print('设备 ID: ${deviceInfo.deviceId}');
print('平台: ${deviceInfo.platform}');
print('设备名称: ${deviceInfo.deviceName}');
```

### 4. 上传设备信息

```dart
// 方式 1: 自动获取设备信息并上传
var result = await deviceService.uploadDeviceInfo();

// 方式 2: 手动指定设备信息并上传
var customDeviceInfo = WenzbakDeviceInfo(
  deviceId: 'device-001',
  platform: 'windows',
  model: 'PC',
  osVersion: 'Windows 10',
  deviceName: 'My Computer',
  updateTimestamp: DateTime.now().millisecondsSinceEpoch,
);
var result = await deviceService.uploadDeviceInfo(customDeviceInfo);

if (result) {
  print('设备信息上传成功');
} else {
  print('设备信息上传失败');
}
```

### 5. 查询设备信息

```dart
// 查询所有设备信息
var allDevices = await deviceService.queryDeviceInfo();

// 查询指定设备信息
var specificDevice = await deviceService.queryDeviceInfo('device-001');
```

## 详细说明

### 设备信息模型

`WenzbakDeviceInfo` 包含以下字段：

- `deviceId` (String, 必需): 设备唯一标识符
- `platform` (String?, 可选): 平台类型（如：android, ios, windows, linux, macos）
- `model` (String?, 可选): 设备型号
- `osVersion` (String?, 可选): 操作系统版本
- `deviceName` (String?, 可选): 设备名称
- `updateTimestamp` (int?, 可选): 更新时间戳（毫秒）

### 上传流程

1. **获取设备信息**
   - 如果提供了 `deviceInfo` 参数，使用提供的设备信息
   - 如果未提供，调用 `getDeviceSystemInfo()` 自动获取
   - 如果提供了 `deviceInfo`，会确保设备ID与配置一致，并自动更新时间戳

2. **序列化设备信息**
   - 将设备信息序列化为 JSON 字符串

3. **写入临时文件**
   - 将 JSON 字符串写入本地临时文件（`temp_device_info.json`）

4. **上传到远程存储**
   - 使用 `config.getRemoteDeviceInfoPath(deviceId)` 获取远程路径
   - 调用 `storage.uploadFile()` 上传文件

5. **清理临时文件**
   - 删除本地临时文件

6. **更新本地缓存**
   - 将设备信息保存到本地缓存文件（`device_info.json`）

### 查询流程

1. **获取设备ID列表**
   - 从远程存储的设备根目录列出所有设备目录
   - 如果指定了 `deviceId`，只查询该设备

2. **读取设备信息**
   - 对于每个设备ID，从远程存储读取 `device_info.json` 文件
   - 解析 JSON 并创建 `WenzbakDeviceInfo` 对象

3. **更新本地缓存**
   - 将查询到的设备信息保存到本地缓存

4. **返回设备信息列表**
   - 返回所有查询到的设备信息

### 本地缓存机制

设备服务会自动维护本地缓存，缓存文件位于：
- **非私有模式**：`{localRootPath}/public/devices/device_info.json`
- **私有模式**：`{localRootPath}/private/{secretKey}/devices/device_info.json`

缓存文件格式为 JSON 对象，键为设备ID，值为设备信息的 JSON 对象。

**缓存更新时机：**
- 上传设备信息后
- 查询设备信息后

**缓存加载时机：**
- 创建设备服务实例时自动加载

### 自动获取设备信息

`getDeviceSystemInfo()` 方法会自动检测当前运行环境并获取设备信息：

- **平台检测**：自动识别 Android、iOS、Windows、Linux、macOS
- **操作系统版本**：使用 `Platform.operatingSystemVersion`
- **设备名称**：
  - Windows: 使用 `COMPUTERNAME` 或 `USERNAME` 环境变量
  - Linux/macOS: 使用 `HOSTNAME` 或 `USER` 环境变量
  - 其他平台: 使用默认值 "Device"
- **设备型号**：当前使用平台名称作为型号（移动平台需要额外配置）

### 私有密钥隔离

使用 `secretKey` 配置可以创建私有的设备信息存储空间：

```dart
var privateConfig = WenzbakConfig(
  deviceId: 'device-001',
  localRootPath: './local_backup',
  remoteRootPath: 'wenzbak',
  storageType: 's3',
  storageConfig: jsonEncode(minioConfig),
  secretKey: 'my-secret-key',  // 使用私有密钥
);

var privateDeviceService = WenzbakDeviceServiceImpl(privateConfig);
```

**路径规则：**
- **非私有模式**：`{remoteRootPath}/public/devices/{deviceId}/device_info.json`
- **私有模式**：`{remoteRootPath}/private/{secretKey}/devices/{deviceId}/device_info.json`

## API 参考

### `getDeviceSystemInfo()`

获取当前设备的设备信息。

**返回值：**
- `Future<WenzbakDeviceInfo>`: 当前设备的设备信息

**示例：**

```dart
var deviceInfo = await deviceService.getDeviceSystemInfo();
print('设备 ID: ${deviceInfo.deviceId}');
print('平台: ${deviceInfo.platform}');
```

### `uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo])`

上传设备信息到远程存储。

**参数：**
- `deviceInfo` (WenzbakDeviceInfo?, 可选): 要上传的设备信息。如果为 `null`，则自动获取当前设备信息。

**返回值：**
- `Future<bool>`: 上传是否成功

**异常：**
- `Exception`: 如果未配置存储服务
- 其他存储相关的异常

**示例：**

```dart
// 自动获取并上传
var result = await deviceService.uploadDeviceInfo();

// 手动指定并上传
var customInfo = WenzbakDeviceInfo(
  deviceId: 'device-001',
  platform: 'windows',
  deviceName: 'My PC',
  updateTimestamp: DateTime.now().millisecondsSinceEpoch,
);
var result = await deviceService.uploadDeviceInfo(customInfo);
```

### `queryDeviceInfo([String? deviceId])`

查询设备信息。

**参数：**
- `deviceId` (String?, 可选): 设备ID。如果为 `null`，则查询所有设备。

**返回值：**
- `Future<List<WenzbakDeviceInfo>>`: 设备信息列表

**异常：**
- `Exception`: 如果未配置存储服务
- 其他存储相关的异常

**示例：**

```dart
// 查询所有设备
var allDevices = await deviceService.queryDeviceInfo();

// 查询指定设备
var device = await deviceService.queryDeviceInfo('device-001');
```

## 完整示例

### 示例 1: 基本使用

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

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

  var deviceService = WenzbakDeviceServiceImpl(config);
  
  // 获取当前设备信息
  var deviceInfo = await deviceService.getDeviceSystemInfo();
  print('当前设备: ${deviceInfo.deviceName}');
  
  // 上传设备信息
  var result = await deviceService.uploadDeviceInfo();
  print('上传结果: $result');
  
  // 查询所有设备
  var allDevices = await deviceService.queryDeviceInfo();
  print('设备数量: ${allDevices.length}');
}
```

### 示例 2: 自定义设备信息

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/device.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

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

  var deviceService = WenzbakDeviceServiceImpl(config);
  
  // 创建自定义设备信息
  var customDeviceInfo = WenzbakDeviceInfo(
    deviceId: config.deviceId,
    platform: 'custom-platform',
    model: 'Custom Model',
    osVersion: 'Custom OS 1.0.0',
    deviceName: 'My Custom Device',
    updateTimestamp: DateTime.now().millisecondsSinceEpoch,
  );
  
  // 上传自定义设备信息
  var result = await deviceService.uploadDeviceInfo(customDeviceInfo);
  if (result) {
    print('自定义设备信息上传成功');
  }
}
```

### 示例 3: 查询和管理多个设备

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

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

  var deviceService = WenzbakDeviceServiceImpl(config);
  
  // 上传当前设备信息
  await deviceService.uploadDeviceInfo();
  
  // 查询所有设备
  var allDevices = await deviceService.queryDeviceInfo();
  print('所有设备:');
  for (var device in allDevices) {
    print('  - ${device.deviceName} (${device.deviceId})');
    print('    平台: ${device.platform}');
    print('    更新时间: ${device.updateTimestamp}');
  }
  
  // 查询特定设备
  var specificDevice = await deviceService.queryDeviceInfo('device-001');
  if (specificDevice.isNotEmpty) {
    print('找到设备: ${specificDevice.first.deviceName}');
  }
}
```

### 示例 4: 使用私有密钥

```dart
import 'dart:convert';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';

void main() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 使用私有密钥的配置
  var privateConfig = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './local_backup',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
    secretKey: 'my-secret-key',  // 使用私有密钥
  );

  var privateDeviceService = WenzbakDeviceServiceImpl(privateConfig);
  
  // 上传设备信息（会存储在私有路径下）
  var result = await privateDeviceService.uploadDeviceInfo();
  print('私有设备信息上传结果: $result');
  
  // 查询私有设备信息
  var privateDevices = await privateDeviceService.queryDeviceInfo();
  print('私有设备数量: ${privateDevices.length}');
}
```

## 运行测试

运行测试文件以验证功能：

```bash
dart run test/device_test.dart
```

## 运行示例

运行示例程序：

```bash
dart run example/device_example.dart
```

## 注意事项

1. **存储服务配置**：确保已正确配置存储服务（MinIO、WebDAV 或 File）
2. **存储桶/目录**：确保远程存储中已创建相应的存储桶或目录
3. **设备ID一致性**：手动指定设备信息时，设备ID必须与配置中的 `deviceId` 一致
4. **时间戳更新**：手动指定设备信息时，`updateTimestamp` 会自动更新为当前时间
5. **本地缓存**：设备信息会缓存在本地，查询时会优先使用缓存（如果存在）
6. **网络连接**：确保能够访问远程存储服务
7. **平台检测限制**：移动平台的设备型号检测可能需要额外的平台特定代码

## 故障排除

### 问题 1: 设备信息上传失败

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

### 问题 2: 查询设备信息返回空列表

**可能原因：**
- 远程存储中没有设备信息文件
- 设备ID不匹配
- 路径配置错误

**解决方法：**
1. 确认已上传设备信息
2. 检查远程存储路径是否正确
3. 验证设备ID是否匹配
4. 检查私有密钥配置（如果使用）

### 问题 3: 自动获取的设备信息不准确

**可能原因：**
- 平台检测失败
- 环境变量不可用
- 操作系统版本获取失败

**解决方法：**
1. 使用手动指定的设备信息
2. 检查平台检测逻辑
3. 验证环境变量是否可用

### 问题 4: 本地缓存不更新

**可能原因：**
- 文件写入权限不足
- 缓存文件路径错误
- 缓存文件损坏

**解决方法：**
1. 检查本地目录写入权限
2. 验证缓存文件路径
3. 删除损坏的缓存文件，重新查询

## 相关文档

- [MinIO 快速开始](../minio/QUICKSTART_MINIO.md)
- [MinIO 故障排除](../minio/MINIO_TROUBLESHOOTING.md)
- [文件上传功能](../file/upload.md)

## 更新日志

- **v1.0.0** (2026-01-16): 初始版本，支持设备信息上传和查询功能
  - 支持自动获取设备信息
  - 支持手动指定设备信息
  - 支持查询所有设备和指定设备
  - 支持本地缓存机制
  - 支持私有密钥隔离
