import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/service/message/message.dart';
import 'package:wenzbak/src/service/message/impl/message_impl.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

/// Wenzbak 消息发送与接收测试类
/// 用于测试消息的发送和接收功能
void main() async {
  print('=== Wenzbak 消息发送与接收测试 ===\n');

  // MinIO 配置信息（参考 minio_storage_test.dart）
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建两个设备的配置（模拟两个设备之间的消息通信）
  var device1Id = 'test-device-001';
  var device2Id = 'test-device-002';

  var device1Config = WenzbakConfig(
    deviceId: device1Id,
    localRootPath: './test_local_device1',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  var device2Config = WenzbakConfig(
    deviceId: device2Id,
    localRootPath: './test_local_device2',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  // 创建消息服务实例
  WenzbakMessageService? device1MessageService;
  WenzbakMessageService? device2MessageService;

  device1MessageService = WenzbakMessageServiceImpl(device1Config);
  print('   设备1 ID: $device1Id');

  // await Future.delayed(Duration(seconds: 3));
  // 测试用例
  var testResults = <String, bool>{};

  // 测试 1: 设备1发送消息
  print('--- 测试 1: 设备1发送消息 ---');
  try {
    for(var i=0;i<1000;i++) {
      var uuid = Uuid().v4();
      var testMessage = WenzbakMessage(
        uuid: uuid,
        content: 'Hello from device$i! This is a test message...',
        timestamp: DateTime
            .now()
            .millisecondsSinceEpoch,
      );
      await device1MessageService.sendMessage(testMessage);
      print('✅ 消息发送成功');
      print('   消息 UUID: $uuid');
      print('   消息内容: ${testMessage.content}');
      print('   消息时间戳: ${testMessage.timestamp}');
      testResults['sendMessage'] = true;
    }

    // 等待消息上传完成（包括文件上传和锁文件上传）
    print('   等待消息上传完成（包括文件上传和锁文件）...');
    await Future.delayed(Duration(seconds: 5));

    // 验证消息文件是否已上传
    try {
      var storage = WenzbakStorageClientService.getInstance(device1Config);
      if (storage != null) {
        var remoteMsgRootPath = device1Config.getRemoteCurrentMessagePath();
        var files = await storage.listFiles(remoteMsgRootPath);
        print('   设备1远程消息目录文件数量: ${files.length}');
        for (var file in files.take(5)) {
          print('     - ${file.path} (${file.isDir == true ? "目录" : "文件"})');
        }
      }
    } catch (e) {
      print('   ⚠️  无法验证远程文件: $e');
    }
  } catch (e, stackTrace) {
    print('❌ 消息发送失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['sendMessage'] = false;
  }
  print('');
  // 测试 2: 设备2接收消息
  device2MessageService = WenzbakMessageServiceImpl(device2Config);
  print('   设备2 ID: $device2Id\n');

  print('--- 测试 2: 设备2接收消息 ---');
  try {
    var receivedMessages = <WenzbakMessage>[];
    var messageReceived = false;

    // 添加消息接收器
    device2MessageService.addMessageReceiver((message) async{
      receivedMessages.add(message);
      messageReceived = true;
      print('   📨 收到消息:');
      print('      UUID: ${message.uuid}');
      print('      内容: ${message.content}');
      print('      时间戳: ${message.timestamp}');
    });

    // 先检查远程存储中是否有设备1的消息
    try {
      var storage = WenzbakStorageClientService.getInstance(device2Config);
      if (storage != null) {
        var remoteMsgRootPath = device2Config.getRemoteMessageRootPath();
        print('   检查远程消息根目录: $remoteMsgRootPath');
        var files = await storage.listFiles(remoteMsgRootPath);
        print('   找到设备/文件夹数量: ${files.length}');
        for (var file in files) {
          if (file.isDir == true && file.path != null) {
            var deviceId = file.path!.split('/').last;
            print('     设备: $deviceId');
            if (deviceId == device1Id) {
              var devicePath = [remoteMsgRootPath, deviceId].join("/");
              var deviceFiles = await storage.listFiles(devicePath);
              print('     设备1消息文件数量: ${deviceFiles.length}');
              for (var df in deviceFiles.take(5)) {
                print('       - ${df.path}');
              }
            }
          }
        }
      }
    } catch (e) {
      print('   ⚠️  检查远程存储时出错: $e');
    }

    // 多次尝试读取消息（因为上传可能需要时间）
    print('   开始读取消息（最多尝试3次）...');
    for (var attempt = 1; attempt <= 3; attempt++) {
      print('   尝试 $attempt/3...');
      var startTime = DateTime.now();
      await device2MessageService.readMessage();
      var elapsedTime = DateTime.now().difference(startTime);
      print('   消息读取完成，耗时: ${elapsedTime.inMilliseconds}ms');
      await Future.delayed(Duration(seconds: 2));

      if (messageReceived && receivedMessages.isNotEmpty) {
        break;
      }

      if (attempt < 3) {
        print('   未收到消息，等待3秒后重试...');
        await Future.delayed(Duration(seconds: 3));
      }
    }

    if (messageReceived && receivedMessages.isNotEmpty) {
      print('✅ 消息接收成功');
      print('   收到消息数量: ${receivedMessages.length}');
      testResults['receiveMessage'] = true;
    } else {
      print('⚠️  未收到消息');
      print('   可能的原因:');
      print('   1. 消息尚未上传完成（需要更多等待时间）');
      print('   2. 设备2无法访问设备1的消息');
      print('   3. 消息文件格式不正确');
      print('   4. msg.lock 文件尚未上传');
      testResults['receiveMessage'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 消息接收失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['receiveMessage'] = false;
  }
  print('');

  // 测试 3: 设备2发送多条消息
  print('--- 测试 3: 设备2发送多条消息 ---');
  try {
    var messageCount = 3;
    var sentUuids = <String>[];

    for (var i = 0; i < messageCount; i++) {
      var uuid = Uuid().v4();
      var testMessage = WenzbakMessage(
        uuid: uuid,
        content: 'Message $i from device2: Test content ${i + 1}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await device2MessageService.sendMessage(testMessage);
      sentUuids.add(uuid);
      print('   发送消息 $i: $uuid');
    }

    print('✅ 多条消息发送成功');
    print('   发送消息数量: $messageCount');
    testResults['sendMultipleMessages'] = true;

    // 等待消息上传完成（包括文件上传和锁文件上传）
    print('   等待消息上传完成（包括文件上传和锁文件）...');
    await Future.delayed(Duration(seconds: 5));
  } catch (e, stackTrace) {
    print('❌ 多条消息发送失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['sendMultipleMessages'] = false;
  }
  print('');

  // 测试 4: 设备1接收多条消息
  print('--- 测试 4: 设备1接收多条消息 ---');
  try {
    var receivedMessages = <WenzbakMessage>[];

    // 添加消息接收器
    device1MessageService.addMessageReceiver((message) async{
      receivedMessages.add(message);
      print('   📨 收到消息:');
      print('      UUID: ${message.uuid}');
      print('      内容: ${message.content}');
    });

    // 多次尝试读取消息
    print('   开始读取消息（最多尝试3次）...');
    for (var attempt = 1; attempt <= 3; attempt++) {
      print('   尝试 $attempt/3...');
      await device1MessageService.readMessage();
      await Future.delayed(Duration(seconds: 2));

      if (receivedMessages.isNotEmpty) {
        break;
      }

      if (attempt < 3) {
        print('   未收到消息，等待3秒后重试...');
        await Future.delayed(Duration(seconds: 3));
      }
    }

    if (receivedMessages.isNotEmpty) {
      print('✅ 多条消息接收成功');
      print('   收到消息数量: ${receivedMessages.length}');
      testResults['receiveMultipleMessages'] = true;
    } else {
      print('⚠️  未收到消息');
      testResults['receiveMultipleMessages'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 多条消息接收失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['receiveMultipleMessages'] = false;
  }
  print('');

  // 测试 5: 测试消息定时器
  print('--- 测试 5: 测试消息定时器 ---');
  try {
    var receivedCount = 0;

    // 添加消息接收器
    device2MessageService.addMessageReceiver((message) async{
      receivedCount++;
      print('   📨 定时器收到消息: ${message.content}');
    });

    // 启动定时器（每5秒读取一次消息）
    device2MessageService.startTimer();
    print('✅ 消息定时器启动成功');
    print('   定时器间隔: 5秒');

    // 设备1发送一条新消息
    var uuid = Uuid().v4();
    var testMessage = WenzbakMessage(
      uuid: uuid,
      content: 'Timer test message from device1',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    await device1MessageService.sendMessage(testMessage);
    print('   设备1发送测试消息: $uuid');

    // 等待消息上传完成
    await Future.delayed(Duration(seconds: 5));

    // 等待定时器触发（等待8秒，确保至少触发一次）
    print('   等待定时器触发（8秒）...');
    await Future.delayed(Duration(seconds: 8));

    // 停止定时器
    device2MessageService.stopTimer();
    print('✅ 消息定时器停止成功');

    if (receivedCount > 0) {
      print('✅ 定时器测试成功');
      print('   通过定时器收到消息数量: $receivedCount');
      testResults['messageTimer'] = true;
    } else {
      print('⚠️  定时器未收到消息');
      testResults['messageTimer'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 定时器测试失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['messageTimer'] = false;
  }
  print('');

  // 测试总结
  print('=== 测试总结 ===');
  var totalTests = testResults.length;
  var passedTests = testResults.values.where((v) => v).length;
  var failedTests = totalTests - passedTests;

  print('总测试数: $totalTests');
  print('通过: $passedTests');
  print('失败: $failedTests');
  print('');

  if (failedTests > 0) {
    print('失败的测试:');
    testResults.forEach((test, result) {
      if (!result) {
        print('  ❌ $test');
      }
    });
  } else {
    print('🎉 所有测试通过！');
  }

  // // 清理测试数据（可选）
  // print('\n--- 清理测试数据 ---');
  // try {
  //   var device1Dir = Directory('./test_local_device1');
  //   var device2Dir = Directory('./test_local_device2');
  //
  //   if (await device1Dir.exists()) {
  //     await device1Dir.delete(recursive: true);
  //     print('✅ 设备1测试数据已清理');
  //   }
  //   if (await device2Dir.exists()) {
  //     await device2Dir.delete(recursive: true);
  //     print('✅ 设备2测试数据已清理');
  //   }
  // } catch (e) {
  //   print('⚠️  清理测试数据失败: $e');
  // }
}

/// 打印错误详情
void _printErrorDetails(dynamic error, StackTrace stackTrace) {
  var errorStr = error.toString();

  // 检查是否是连接错误
  if (errorStr.contains('Connection') ||
      errorStr.contains('Failed host lookup') ||
      errorStr.contains('Network')) {
    print('   ⚠️  检测到连接错误！');
    print('   可能的原因:');
    print('   1. MinIO 服务未启动');
    print('   2. Endpoint 地址不正确');
    print('   3. 网络连接问题');
  }

  // 检查是否是签名错误
  if (errorStr.contains('SignatureDoesNotMatch') ||
      errorStr.contains('403') ||
      errorStr.contains('signature')) {
    print('   ⚠️  检测到签名错误！');
    print('   可能的原因:');
    print('   1. Access Key 或 Secret Key 不正确');
    print('   2. 时间不同步（需要 UTC 时间）');
    print('   3. Region 配置不匹配');
  }

  // 检查是否是权限错误
  if (errorStr.contains('AccessDenied') || errorStr.contains('Forbidden')) {
    print('   ⚠️  检测到权限错误！');
    print('   可能的原因:');
    print('   1. Access Key 没有足够权限');
    print('   2. Bucket 不存在或无权访问');
  }

  // 检查是否是 Bucket 不存在
  if (errorStr.contains('NoSuchBucket') || errorStr.contains('bucket')) {
    print('   ⚠️  检测到 Bucket 问题！');
    print('   可能的原因:');
    print('   1. Bucket 不存在，需要在 MinIO 控制台创建');
    print('   2. Bucket 名称拼写错误');
  }

  // 打印完整错误信息
  if (errorStr.length > 200) {
    print('   错误信息（前200字符）: ${errorStr.substring(0, 200)}...');
  } else {
    print('   错误信息: $errorStr');
  }
}
