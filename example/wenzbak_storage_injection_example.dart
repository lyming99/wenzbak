// Storage 直接注入示例
// 展示如何直接注入 Storage 实例到 WenzbakConfig

import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/models/index.dart';
import 'package:wenzbak/src/service/backup/impl/backup_impl.dart';
import 'package:wenzbak/src/service/storage/impl/s3_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/webdav_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/file_storage_client.dart';

void main() async {
  await s3StorageExample();
  await webdavStorageExample();
  await fileStorageExample();
  await customStorageExample();
}

/// S3/MinIO Storage 直接注入示例
Future<void> s3StorageExample() async {
  print("\n=== S3 Storage 直接注入示例 ===\n");

  // 先创建一个临时 config（仅用于创建 S3StorageClient）
  var tempConfig = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_s3',
    remoteRootPath: 'wenzbak',
  );

  // 直接创建 S3StorageClient 实例
  final s3Storage = S3StorageClient(
    tempConfig,
    'http://localhost:9000', // endpoint
    'minioadmin',            // accessKey
    'minioadmin',            // secretKey
    'wenzbak',               // bucket
    'us-east-1',             // region
  );

  // 在实际的 config 中注入 storage 实例
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_s3',
    remoteRootPath: 'wenzbak',
    storage: s3Storage, // 直接注入 Storage 实例
  );

  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();

  print("添加数据");
  await backupClient.addBackupData(
    WenzbakDataLine(createTime: DateTime.now(), content: "Hello from S3!"),
  );

  print("上传数据");
  await backupClient.uploadAllData(false);
  print("S3 示例完成\n");
}

/// WebDAV Storage 直接注入示例
Future<void> webdavStorageExample() async {
  print("\n=== WebDAV Storage 直接注入示例 ===\n");

  // 先创建一个临时 config
  var tempConfig = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_webdav',
    remoteRootPath: 'wenzbak',
  );

  // 直接创建 WebDAVStorageClient 实例
  final webdavStorage = WebDAVStorageClient(
    tempConfig,
    'http://localhost:8080', // url
    'webdav',                // username
    'webdav',                // password
  );

  // 在实际的 config 中注入 storage 实例
  var config = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_webdav',
    remoteRootPath: 'wenzbak',
    storage: webdavStorage, // 直接注入 Storage 实例
  );

  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();

  print("发送消息");
  var message = WenzbakMessage(
    uuid: Uuid().v4(),
    content: 'Hello from WebDAV with direct storage injection!',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  await backupClient.messageService.sendMessage(message);
  print("WebDAV 示例完成\n");
}

/// 本地文件 Storage 直接注入示例
Future<void> fileStorageExample() async {
  print("\n=== 本地文件 Storage 直接注入示例 ===\n");

  // 先创建一个临时 config
  var tempConfig = WenzbakConfig(
    deviceId: 'device-003',
    localRootPath: './temp/local_backup_file',
    remoteRootPath: 'wenzbak',
  );

  // 直接创建 FileStorageClient 实例
  final fileStorage = FileStorageClient(
    tempConfig,
    './temp/file_storage', // basePath
  );

  // 在实际的 config 中注入 storage 实例
  var config = WenzbakConfig(
    deviceId: 'device-003',
    localRootPath: './temp/local_backup_file',
    remoteRootPath: 'wenzbak',
    storage: fileStorage, // 直接注入 Storage 实例
  );

  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();

  print("添加数据");
  await backupClient.addBackupData(
    WenzbakDataLine(createTime: DateTime.now(), content: "Hello from File Storage!"),
  );

  print("上传数据");
  await backupClient.uploadAllData(false);
  print("本地文件 Storage 示例完成\n");
}

/// 自定义 Storage 实现示例
Future<void> customStorageExample() async {
  print("\n=== 自定义 Storage 实现示例 ===\n");

  // 先创建一个临时 config
  var tempConfig = WenzbakConfig(
    deviceId: 'device-004',
    localRootPath: './temp/local_backup_custom',
    remoteRootPath: 'wenzbak',
  );

  // 使用自定义的 Storage 实现
  final customStorage = _InMemoryStorageClient(tempConfig);

  // 在实际的 config 中注入自定义 storage 实例
  var config = WenzbakConfig(
    deviceId: 'device-004',
    localRootPath: './temp/local_backup_custom',
    remoteRootPath: 'wenzbak',
    storage: customStorage, // 注入自定义 Storage 实例
  );

  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();

  print("自定义 Storage 示例完成\n");
}

/// 自定义内存 Storage 实现示例
/// 这是一个简单的内存实现，用于演示如何自定义 Storage
class _InMemoryStorageClient extends S3StorageClient {
  _InMemoryStorageClient(WenzbakConfig config)
      : super(
    config,
    'memory://localhost',
    'memory',
    'memory',
    'memory',
    'us-memory-1',
  );

// 可以在这里覆盖特定方法来实现自定义逻辑
// 例如：添加缓存、日志、重试逻辑等
}
