import 'dart:convert';
import 'dart:io';

import 'package:wenzbak/src/config/backup.dart';
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

  // 创建 WenzbakConfig，配置使用 MinIO 存储和文件加密
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_device001',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用文件加密
    encryptFile: true,
    secretKey: 'my-secret-key-123', // 加密密钥
    secret: 'my-secret-password', // 加密密码
  );
  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();

  // 准备测试文件
  var testDir = Directory('./temp/test_encrypt_files');
  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }

  print("上传加密文件");
  // 1. 上传加密文件
  var testFile1 = File('${testDir.path}/secret_file1.txt');
  await testFile1.writeAsString('This is a secret file 1! Do not share!');
  var remotePath1 = await backupClient.uploadAssets(testFile1.path);
  print("加密文件1上传成功，远程路径: $remotePath1");
  if (remotePath1 != null && remotePath1.endsWith('.enc')) {
    print("  ✅ 远程路径包含 .enc 后缀（文件已加密）");
  }

  var testFile2 = File('${testDir.path}/secret_file2.txt');
  await testFile2.writeAsString('This is a secret file 2! Confidential data!');
  var remotePath2 = await backupClient.uploadAssets(testFile2.path);
  print("加密文件2上传成功，远程路径: $remotePath2");
  if (remotePath2 != null && remotePath2.endsWith('.enc')) {
    print("  ✅ 远程路径包含 .enc 后缀（文件已加密）");
  }

  print("上传加密临时文件");
  // 2. 上传加密临时文件
  var tempFile = File('${testDir.path}/temp_secret_file.txt');
  await tempFile.writeAsString('This is a temporary encrypted file!');
  var tempRemotePath = await backupClient.uploadTempAssets(tempFile.path);
  print("加密临时文件上传成功，远程路径: $tempRemotePath");
  if (tempRemotePath != null && tempRemotePath.endsWith('.enc')) {
    print("  ✅ 远程路径包含 .enc 后缀（文件已加密）");
  }
}

Future<void> device2() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000', // MinIO 服务器地址
    'accessKey': 'minioadmin', // MinIO 访问密钥
    'secretKey': 'minioadmin', // MinIO 秘密密钥
    'bucket': 'wenzbak', // 存储桶名称
    'region': 'us-east-1', // 区域（MinIO 可以使用任意值）
  };

  // 创建 WenzbakConfig，配置使用 MinIO 存储和文件加密
  // 注意：必须使用与 device1 相同的 secretKey 和 secret 才能解密文件
  var config = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_device002',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用文件加密，使用与 device1 相同的密钥
    encryptFile: true,
    secretKey: 'my-secret-key-123', // 必须与 device1 相同
    secret: 'my-secret-password', // 必须与 device1 相同
  );
  var backupClient = WenzbakClientServiceImpl(config);
  await backupClient.uploadDeviceInfo();

  print("下载并解密文件");
  // 下载文件（需要知道远程路径，这里使用示例路径）
  // 注意：实际使用时，远程路径应该从上传时返回的路径获取
  // 注意：远程路径包含 .enc 后缀，但下载时会自动解密
  var remoteAssetPath = config.getRemoteAssetPath();
  var remotePath1 = '$remoteAssetPath/secret_file1.txt.enc';
  var localPath1 = await backupClient.downloadFile(remotePath1);
  if (localPath1 != null) {
    print("加密文件1下载并解密成功，本地路径: $localPath1");
    var content = await File(localPath1).readAsString();
    print("文件1内容: $content");
    print("  ✅ 文件已成功解密");
  } else {
    print("文件1下载失败");
  }

  var remotePath2 = '$remoteAssetPath/secret_file2.txt.enc';
  var localPath2 = await backupClient.downloadFile(remotePath2);
  if (localPath2 != null) {
    print("加密文件2下载并解密成功，本地路径: $localPath2");
    var content = await File(localPath2).readAsString();
    print("文件2内容: $content");
    print("  ✅ 文件已成功解密");
  } else {
    print("文件2下载失败");
  }

  print("下载文件完毕");
  print("");
  print("注意：如果使用错误的 secretKey 或 secret，文件将无法正确解密！");
}
