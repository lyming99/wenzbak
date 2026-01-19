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

  // 创建 WenzbakConfig，配置使用 MinIO 存储和数据加密
  // 注意：数据加密只需要设置 secretKey 和 secret，不需要设置 encryptFile
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_device001',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用数据加密（设置 secretKey 和 secret 即可）
    secretKey: 'my-secret-key-123', // 加密密钥
    secret: 'my-secret-password', // 加密密码
  );
  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();
  
  print("上传加密数据");
  // 1. 上传加密数据
  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now(),
      content: "This is encrypted secret data 1!",
    ),
  );
  await backupClient.uploadAllData(false);
  print("  ✅ 加密数据1已上传");

  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now(),
      content: "This is encrypted secret data 2!",
    ),
  );
  await backupClient.uploadAllData(false);
  print("  ✅ 加密数据2已上传");

  print("合并加密数据");
  // 2. 合并历史数据
  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now().subtract(Duration(days: 2)),
      content: "This is old encrypted data 1!",
    ),
  );
  await backupClient.addBackupData(
    WenzbakDataLine(
      createTime: DateTime.now().subtract(Duration(days: 2)),
      content: "This is old encrypted data 2!",
    ),
  );
  await backupClient.uploadAllData(false);
  await backupClient.mergeHistoryData();
  print("  ✅ 历史加密数据已合并");
  
  print("注意：加密数据存储在 private/{secretKey}/data/ 路径下");
}

Future<void> device2() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000', // MinIO 服务器地址
    'accessKey': 'minioadmin', // MinIO 访问密钥
    'secretKey': 'minioadmin', // MinIO 秘密密钥
    'bucket': 'wenzbak', // 存储桶名称
    'region': 'us-east-1', // 区域（MinIO 可以使用任意值）
  };

  // 创建 WenzbakConfig，配置使用 MinIO 存储和数据加密
  // 注意：必须使用与 device1 相同的 secretKey 和 secret 才能解密数据
  var config = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_device002',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用数据加密，使用与 device1 相同的密钥
    secretKey: 'my-secret-key-123', // 必须与 device1 相同
    secret: 'my-secret-password', // 必须与 device1 相同
  );
  var backupClient = WenzbakClientServiceImpl(config);
  await backupClient.uploadDeviceInfo();
  
  print("下载并解密数据");
  // 添加数据接收器
  backupClient.addDataReceiver(_WenzbakDataReceiver());
  
  // 下载所有数据（会自动解密）
  await backupClient.downloadAllData();
  
  print("下载数据完毕");
  print("");
  print("注意：");
  print("1. 如果使用错误的 secretKey 或 secret，数据将无法正确解密！");
  print("2. 加密数据存储在 private/{secretKey}/data/ 路径下");
  print("3. 未加密数据存储在 public/data/ 路径下");
}

class _WenzbakDataReceiver extends WenzbakDataReceiver {
  @override
  Future onReceive(WenzbakDataLine line) async {
    print("收到解密数据：${line.content}");
  }
}
