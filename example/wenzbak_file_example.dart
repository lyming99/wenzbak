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

  // 准备测试文件
  var testDir = Directory('./temp/test_files');
  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }

  print("上传文件");
  // 1. 上传普通文件
  var testFile1 = File('${testDir.path}/test_file1.txt');
  await testFile1.writeAsString('Hello, this is test file 1!');
  var remotePath1 = await backupClient.uploadAssets(testFile1.path);
  print("文件1上传成功，远程路径: $remotePath1");

  var testFile2 = File('${testDir.path}/test_file2.txt');
  await testFile2.writeAsString('Hello, this is test file 2!');
  var remotePath2 = await backupClient.uploadAssets(testFile2.path);
  print("文件2上传成功，远程路径: $remotePath2");

  print("上传临时文件");
  // 2. 上传临时文件
  var tempFile = File('${testDir.path}/temp_file.txt');
  await tempFile.writeAsString('This is a temporary file!');
  var tempRemotePath = await backupClient.uploadTempAssets(tempFile.path);
  print("临时文件上传成功，远程路径: $tempRemotePath");
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

  print("下载文件");
  // 下载文件（需要知道远程路径，这里使用示例路径）
  // 注意：实际使用时，远程路径应该从上传时返回的路径获取
  var remoteAssetPath = config.getRemoteAssetPath();
  var remotePath1 = '$remoteAssetPath/test_file1.txt';
  var localPath1 = await backupClient.downloadFile(remotePath1);
  if (localPath1 != null) {
    print("文件1下载成功，本地路径: $localPath1");
    var content = await File(localPath1).readAsString();
    print("文件1内容: $content");
  } else {
    print("文件1下载失败");
  }

  var remotePath2 = '$remoteAssetPath/test_file2.txt';
  var localPath2 = await backupClient.downloadFile(remotePath2);
  if (localPath2 != null) {
    print("文件2下载成功，本地路径: $localPath2");
    var content = await File(localPath2).readAsString();
    print("文件2内容: $content");
  } else {
    print("文件2下载失败");
  }

  print("下载文件完毕");
}
