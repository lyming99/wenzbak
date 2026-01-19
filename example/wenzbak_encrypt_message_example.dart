import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
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

  // 创建 WenzbakConfig，配置使用 MinIO 存储和消息加密
  // 注意：消息加密只需要设置 secretKey 和 secret，不需要设置 encryptFile
  var config = WenzbakConfig(
    deviceId: 'device-001',
    localRootPath: './temp/local_backup_device001',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用消息加密（设置 secretKey 和 secret 即可）
    secretKey: 'my-secret-key-123',
    // 加密密钥
    secret: 'my-secret-password', // 加密密码
  );
  var backupClient = WenzbakClientServiceImpl(config);

  print("更新设备信息");
  await backupClient.uploadDeviceInfo();
  backupClient.addMessageReceiver((msg) async {
    print("收到加密消息：${msg.content}");
  });
  print("设备1启动消息定时器...");
  backupClient.startMessageTimer();
  print("发送加密消息");
  // 1. 发送加密消息
  var uuid1 = Uuid().v4();
  var message1 = WenzbakMessage(
    uuid: uuid1,
    content: 'This is an encrypted secret message 1! Do not share!',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  await backupClient.messageService.sendMessage(message1);
  print("加密消息1发送成功，UUID: $uuid1");

  var uuid2 = Uuid().v4();
  var message2 = WenzbakMessage(
    uuid: uuid2,
    content: 'This is an encrypted secret message 2! Confidential!',
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
  await backupClient.messageService.sendMessage(message2);
  print("加密消息2发送成功，UUID: $uuid2");

  // 等待消息上传完成
  print("等待消息上传完成...");
  await Future.delayed(Duration(seconds: 3));

  print("注意：加密消息存储在 private/{secretKey}/messages/ 路径下");
  print("注意：消息文件会被压缩并加密为 .gz.enc 格式");
}

Future<void> device2() async {
  var minioConfig = {
    'endpoint': 'http://localhost:9000', // MinIO 服务器地址
    'accessKey': 'minioadmin', // MinIO 访问密钥
    'secretKey': 'minioadmin', // MinIO 秘密密钥
    'bucket': 'wenzbak', // 存储桶名称
    'region': 'us-east-1', // 区域（MinIO 可以使用任意值）
  };

  // 创建 WenzbakConfig，配置使用 MinIO 存储和消息加密
  // 注意：必须使用与 device1 相同的 secretKey 和 secret 才能解密消息
  var config = WenzbakConfig(
    deviceId: 'device-002',
    localRootPath: './temp/local_backup_device002',
    remoteRootPath: 'wenzbak',
    // MinIO 中的路径前缀
    storageType: 's3',
    // 使用 s3 类型（MinIO 兼容 S3 API）
    storageConfig: jsonEncode(minioConfig),
    // 启用消息加密，使用与 device1 相同的密钥
    secretKey: 'my-secret-key-123',
    // 必须与 device1 相同
    secret: 'my-secret-password', // 必须与 device1 相同
  );
  var backupClient = WenzbakClientServiceImpl(config);
  await backupClient.uploadDeviceInfo();

  print("接收并解密消息");
  // 添加消息接收器
  backupClient.addMessageReceiver((message) async {
    print("收到解密消息：");
    print("  UUID: ${message.uuid}");
    print("  内容: ${message.content}");
    print("  时间戳: ${message.timestamp}");
    print("  ✅ 消息已成功解密");
  });

  // 方式1: 手动读取消息（多次尝试以确保能收到消息）
  print("设备2: 手动读取消息...");
  await backupClient.messageService.readMessage();
  for (var i = 0; i < 1000; i++) {
    // 1. 发送加密消息
    var uuid1 = Uuid().v4();
    var message1 = WenzbakMessage(
      uuid: uuid1,
      content:
          'This is an encrypted secret message $i from device2! Do not share!',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await backupClient.messageService.sendMessage(message1);
    print("设备2：加密消息$i发送成功，UUID: $uuid1");
    await Future.delayed(Duration(seconds: 1));
  }
  await Future.delayed(Duration(seconds: 10));
  print("测试完毕，请查看控制台输出");
  print("");
  print("注意：");
  print("1. 如果使用错误的 secretKey 或 secret，消息将无法正确解密！");
  print("2. 加密消息存储在 private/{secretKey}/messages/ 路径下");
  print("3. 未加密消息存储在 public/messages/ 路径下");
  print("4. 消息文件会被压缩并加密为 .gz.enc 格式");
}
