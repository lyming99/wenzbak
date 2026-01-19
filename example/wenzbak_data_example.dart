import 'dart:convert';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/index.dart';
import 'package:wenzbak/src/service/backup/impl/backup_impl.dart';
import 'package:wenzbak/wenzbak.dart';

void main() async {
  await device1();
  await device2();
}

Future<void> device1() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000', // MinIO 服务器地址
    'accessKey': 'minioadmin', // MinIO 访问密钥
    'secretKey': 'minioadmin', // MinIO 秘密密钥
    'bucket': 'wenzbak', // 存储桶名称
    'region': 'us-east-1', // 区域（MinIO 可以使用任意值）
  };

  // 创建 WenzbakConfig，配置使用 MinIO 存储
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_device001',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
  );
  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();
  print("上传数据");
  // 1.上传数据
  await backupClient.addBackupData(
    WenzbakDataLine(createTime: DateTime.now(), content: "hello data1!"),
  );
  await backupClient.uploadAllData(false);

  print("合并数据");
  // 2.合并数据
  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now().subtract(Duration(days: 2)),
      content: "hello data2!",
    ),
  );
  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now().subtract(Duration(days: 2)),
      content: "hello data3!",
    ),
  );
  await backupClient.uploadAllData(false);
  await backupClient.mergeHistoryData();
}

Future<void> device2() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000', // MinIO 服务器地址
    'accessKey': 'minioadmin', // MinIO 访问密钥
    'secretKey': 'minioadmin', // MinIO 秘密密钥
    'bucket': 'wenzbak', // 存储桶名称
    'region': 'us-east-1', // 区域（MinIO 可以使用任意值）
  };

  // 创建 WenzbakConfig，配置使用 MinIO 存储
  var config = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_device002',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
  );
  var backupClient = WenzbakClientServiceImpl(config);
  await backupClient.uploadDeviceInfo();
  print("下载数据");
  backupClient.addDataReceiver(_WenzbakDataReceiver());
  await backupClient.downloadAllData();
  print("下载数据完毕");
}

class _WenzbakDataReceiver extends WenzbakDataReceiver {
  @override
  Future onReceive(WenzbakDataLine line) async {
    print("收到数据：${line.content}");
  }
}
