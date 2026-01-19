import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/device.dart';
import 'package:wenzbak/src/service/device/device.dart';
import 'package:wenzbak/src/service/device/impl/device_impl.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

/// Wenzbak 设备服务测试类
/// 用于测试设备信息的上传和查询功能
void main() async {
  print('=== Wenzbak 设备服务测试 ===\n');

  // MinIO 配置信息
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建测试设备配置
  var deviceId = 'test-device-001';
  var config = WenzbakConfig(
    deviceId: deviceId,
    localRootPath: './test_local_device',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  // 创建设备服务实例
  var deviceService = WenzbakDeviceServiceImpl(config);
  print('   设备 ID: $deviceId\n');

  // 测试用例
  var testResults = <String, bool>{};

  // 测试 1: 获取当前设备信息
  print('--- 测试 1: 获取当前设备信息 ---');
  try {
    var deviceInfo = await deviceService.getDeviceSystemInfo();
    print('✅ 获取设备信息成功');
    print('   设备 ID: ${deviceInfo.deviceId}');
    print('   平台: ${deviceInfo.platform}');
    print('   设备型号: ${deviceInfo.model}');
    print('   操作系统版本: ${deviceInfo.osVersion}');
    print('   设备名称: ${deviceInfo.deviceName}');
    print('   更新时间戳: ${deviceInfo.updateTimestamp}');
    testResults['getCurrentDeviceInfo'] = true;
  } catch (e, stackTrace) {
    print('❌ 获取设备信息失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['getCurrentDeviceInfo'] = false;
  }
  print('');

  // 测试 2: 上传设备信息（自动获取）
  print('--- 测试 2: 上传设备信息（自动获取） ---');
  try {
    var result = await deviceService.uploadDeviceInfo();
    if (result) {
      print('✅ 上传设备信息成功');
      testResults['uploadDeviceInfo_auto'] = true;
    } else {
      print('❌ 上传设备信息失败: 返回 false');
      testResults['uploadDeviceInfo_auto'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 上传设备信息失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadDeviceInfo_auto'] = false;
  }
  print('');

  // 测试 3: 上传设备信息（手动指定）
  print('--- 测试 3: 上传设备信息（手动指定） ---');
  try {
    var customDeviceInfo = WenzbakDeviceInfo(
      deviceId: deviceId,
      platform: 'test-platform',
      model: 'test-model',
      osVersion: 'test-os-1.0',
      deviceName: 'Test Device',
      updateTimestamp: DateTime.now().millisecondsSinceEpoch,
    );
    var result = await deviceService.uploadDeviceInfo(customDeviceInfo);
    if (result) {
      print('✅ 上传自定义设备信息成功');
      print('   平台: ${customDeviceInfo.platform}');
      print('   设备型号: ${customDeviceInfo.model}');
      print('   操作系统版本: ${customDeviceInfo.osVersion}');
      print('   设备名称: ${customDeviceInfo.deviceName}');
      testResults['uploadDeviceInfo_manual'] = true;
    } else {
      print('❌ 上传设备信息失败: 返回 false');
      testResults['uploadDeviceInfo_manual'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 上传设备信息失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadDeviceInfo_manual'] = false;
  }
  print('');

  // 测试 4: 查询所有设备信息
  print('--- 测试 4: 查询所有设备信息 ---');
  try {
    var deviceInfoList = await deviceService.queryDeviceInfo();
    print('✅ 查询设备信息成功');
    print('   设备数量: ${deviceInfoList.length}');
    for (var info in deviceInfoList) {
      print('   - 设备 ID: ${info.deviceId}');
      print('     平台: ${info.platform}');
      print('     设备名称: ${info.deviceName}');
      print('     更新时间: ${info.updateTimestamp}');
    }
    testResults['queryDeviceInfo_all'] = true;
  } catch (e, stackTrace) {
    print('❌ 查询设备信息失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['queryDeviceInfo_all'] = false;
  }
  print('');

  // 测试 5: 查询指定设备信息
  print('--- 测试 5: 查询指定设备信息 ---');
  try {
    var deviceInfoList = await deviceService.queryDeviceInfo(deviceId);
    print('✅ 查询指定设备信息成功');
    print('   设备数量: ${deviceInfoList.length}');
    if (deviceInfoList.isNotEmpty) {
      var info = deviceInfoList.first;
      print('   设备 ID: ${info.deviceId}');
      print('   平台: ${info.platform}');
      print('   设备型号: ${info.model}');
      print('   操作系统版本: ${info.osVersion}');
      print('   设备名称: ${info.deviceName}');
      print('   更新时间戳: ${info.updateTimestamp}');
    }
    testResults['queryDeviceInfo_specific'] = true;
  } catch (e, stackTrace) {
    print('❌ 查询指定设备信息失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['queryDeviceInfo_specific'] = false;
  }
  print('');

  // 测试 6: 验证远程文件是否已上传
  print('--- 测试 6: 验证远程文件是否已上传 ---');
  try {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage != null) {
      var remoteDeviceInfoPath = config.getRemoteDeviceInfoPath(deviceId);
      var deviceInfoBytes = await storage.readFile(remoteDeviceInfoPath);
      if (deviceInfoBytes != null) {
        var jsonStr = utf8.decode(deviceInfoBytes);
        var json = jsonDecode(jsonStr) as Map<String, dynamic>;
        var deviceInfo = WenzbakDeviceInfo.fromJson(json);
        print('✅ 远程文件验证成功');
        print('   远程路径: $remoteDeviceInfoPath');
        print('   设备 ID: ${deviceInfo.deviceId}');
        print('   平台: ${deviceInfo.platform}');
        print('   设备名称: ${deviceInfo.deviceName}');
        testResults['verifyRemoteFile'] = true;
      } else {
        print('❌ 远程文件不存在');
        testResults['verifyRemoteFile'] = false;
      }
    } else {
      print('⚠️  无法获取存储服务实例');
      testResults['verifyRemoteFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 验证远程文件失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['verifyRemoteFile'] = false;
  }
  print('');

  // 测试 7: 验证本地缓存
  print('--- 测试 7: 验证本地缓存 ---');
  try {
    var localDeviceInfoCacheFile = config.getLocalDeviceInfoCacheFile();
    var file = File(localDeviceInfoCacheFile);
    if (await file.exists()) {
      var content = await file.readAsString();
      var map = jsonDecode(content) as Map;
      print('✅ 本地缓存验证成功');
      print('   缓存文件路径: $localDeviceInfoCacheFile');
      print('   缓存设备数量: ${map.length}');
      for (var entry in map.entries) {
        var deviceId = entry.key as String;
        print('   - 设备 ID: $deviceId');
      }
      testResults['verifyLocalCache'] = true;
    } else {
      print('⚠️  本地缓存文件不存在: $localDeviceInfoCacheFile');
      testResults['verifyLocalCache'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 验证本地缓存失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['verifyLocalCache'] = false;
  }
  print('');

  // 输出测试结果汇总
  print('=== 测试结果汇总 ===');
  var totalTests = testResults.length;
  var passedTests = testResults.values.where((v) => v == true).length;
  var failedTests = totalTests - passedTests;
  print('   总测试数: $totalTests');
  print('   通过: $passedTests');
  print('   失败: $failedTests');
  print('');
  for (var entry in testResults.entries) {
    var status = entry.value ? '✅' : '❌';
    print('   $status ${entry.key}');
  }
}

/// 打印错误详情
void _printErrorDetails(dynamic error, StackTrace stackTrace) {
  print('   错误类型: ${error.runtimeType}');
  print('   错误消息: $error');
  var stackLines = stackTrace.toString().split('\n');
  for (var i = 0; i < stackLines.length && i < 5; i++) {
    print('   ${stackLines[i]}');
  }
}
