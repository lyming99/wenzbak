import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/service/backup/impl/backup_impl.dart';

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

  print("发送消息");
  // 1. 发送消息
  var uuid1 = Uuid().v4();
  var message1 = WenzbakMessage(
    uuid: uuid1,
    content: 'Hello from device-001! This is message 1.',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  await backupClient.messageService.sendMessage(message1);
  print("消息1发送成功，UUID: $uuid1");

  var uuid2 = Uuid().v4();
  var message2 = WenzbakMessage(
    uuid: uuid2,
    content: 'Hello from device-001! This is message 2.',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  await backupClient.messageService.sendMessage(message2);
  print("消息2发送成功，UUID: $uuid2");

  // 等待消息上传完成
  print("等待消息上传完成...");
  await Future.delayed(Duration(seconds: 3));
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

  print("接收消息");
  // 添加消息接收器
  backupClient.addMessageReceiver((message) async {
    print("收到消息：");
    print("  UUID: ${message.uuid}");
    print("  内容: ${message.content}");
    print("  时间戳: ${message.timestamp}");
  });

  // 方式1: 手动读取消息（多次尝试以确保能收到消息）
  // print("方式1: 手动读取消息...");
  // for (var i = 0; i < 3; i++) {
  //   print("尝试 ${i + 1}/3...");
  //   await backupClient.messageService.readMessage();
  //   await Future.delayed(Duration(seconds: 2));
  // }

  // 方式2: 使用定时器自动读取消息（每5秒读取一次）
  print("方式2: 启动消息定时器...");
  backupClient.startMessageTimer();
  print("定时器已启动，等待接收消息（10秒）...");
  await Future.delayed(Duration(seconds: 10));
  backupClient.stopMessageTimer();
  print("定时器已停止");

  print("接收消息完毕");
}
