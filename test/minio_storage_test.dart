import 'dart:convert';
import 'dart:typed_data';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

/// MinIO 存储客户端测试类
/// 用于测试和调试 MinIO 连接问题
void main() async {
  print('=== MinIO 存储客户端测试 ===\n');

  // MinIO 配置信息
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建配置
  var config = WenzbakConfig(
    deviceId: 'test-device-001',
    localRootPath: './test_local',
    remoteRootPath: '/',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  // 获取存储客户端实例
  WenzbakStorageClientService? storage;
  try {
    storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      print('❌ 存储客户端创建失败：配置错误');
      return;
    }
    print('✅ 存储客户端创建成功');
    print('   客户端 ID: ${storage.clientId}');
    print('   支持范围读取: ${storage.isRangeSupport}\n');
  } catch (e, stackTrace) {
    print('❌ 存储客户端创建失败: $e');
    print('   堆栈: $stackTrace');
    return;
  }

  // 测试用例
  var testResults = <String, bool>{};

  // 测试 1: 创建文件夹
  print('--- 测试 1: 创建文件夹 ---');
  try {
    await storage.createFolder('test-folder');
    print('✅ 文件夹创建成功');
    testResults['createFolder'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件夹创建失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['createFolder'] = false;
  }
  print('');

  // 测试 2: 写入文件
  print('--- 测试 2: 写入文件 ---');
  try {
    var testData = utf8.encode('Hello, MinIO! This is a test file.');
    await storage.writeFile('test-folder/test.txt', Uint8List.fromList(testData));
    print('✅ 文件写入成功');
    print('   文件大小: ${testData.length} 字节');
    testResults['writeFile'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件写入失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['writeFile'] = false;
  }
  print('');

  // 测试 3: 读取文件
  print('--- 测试 3: 读取文件 ---');
  try {
    var fileData = await storage.readFile('test-folder/test.txt');
    if (fileData != null) {
      var content = utf8.decode(fileData);
      print('✅ 文件读取成功');
      print('   文件内容: $content');
      print('   文件大小: ${fileData.length} 字节');
      testResults['readFile'] = true;
    } else {
      print('⚠️  文件不存在或为空');
      testResults['readFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 文件读取失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['readFile'] = false;
  }
  print('');

  // 测试 4: 获取文件大小
  print('--- 测试 4: 获取文件大小 ---');
  try {
    var fileSize = await storage.readFileSize('test-folder/test.txt');
    print('✅ 文件大小获取成功: $fileSize 字节');
    testResults['readFileSize'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件大小获取失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['readFileSize'] = false;
  }
  print('');

  // 测试 5: 列出文件
  print('--- 测试 5: 列出文件 ---');
  try {
    var files = await storage.listFiles('test-folder');
    print('✅ 文件列表获取成功');
    print('   文件数量: ${files.length}');
    for (var file in files) {
      print('   - ${file.path} (${file.isDir == true ? "目录" : "文件"})');
    }
    testResults['listFiles'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件列表获取失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['listFiles'] = false;
  }
  print('');

  // 测试 6: 范围读取
  print('--- 测试 6: 范围读取 ---');
  try {
    var rangeData = await storage.readRange('test-folder/test.txt', 0, 5);
    var content = utf8.decode(rangeData);
    print('✅ 范围读取成功');
    print('   前 5 个字节: $content');
    testResults['readRange'] = true;
  } catch (e, stackTrace) {
    print('❌ 范围读取失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['readRange'] = false;
  }
  print('');

  // 测试 7: 删除文件
  print('--- 测试 7: 删除文件 ---');
  try {
    await storage.deleteFile('test-folder/test.txt');
    print('✅ 文件删除成功');
    testResults['deleteFile'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件删除失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['deleteFile'] = false;
  }
  print('');

  // 测试 8: 删除文件夹
  print('--- 测试 8: 删除文件夹 ---');
  try {
    await storage.deleteFolder('test-folder');
    print('✅ 文件夹删除成功');
    testResults['deleteFolder'] = true;
  } catch (e, stackTrace) {
    print('❌ 文件夹删除失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['deleteFolder'] = false;
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
}

/// 打印错误详情
void _printErrorDetails(dynamic error, StackTrace stackTrace) {
  var errorStr = error.toString();
  
  // 检查是否是签名错误
  if (errorStr.contains('SignatureDoesNotMatch') || 
      errorStr.contains('403') ||
      errorStr.contains('signature')) {
    print('   ⚠️  检测到签名错误！');
    print('   可能的原因:');
    print('   1. Access Key 或 Secret Key 不正确');
    print('   2. 时间不同步（需要 UTC 时间）');
    print('   3. Region 配置不匹配');
    print('   4. Host 头或 URI 路径格式错误');
    print('   5. 签名算法实现问题');
  }
  
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
  
  // 检查是否是权限错误
  if (errorStr.contains('AccessDenied') || 
      errorStr.contains('Forbidden')) {
    print('   ⚠️  检测到权限错误！');
    print('   可能的原因:');
    print('   1. Access Key 没有足够权限');
    print('   2. Bucket 不存在或无权访问');
  }
  
  // 检查是否是 Bucket 不存在
  if (errorStr.contains('NoSuchBucket') || 
      errorStr.contains('bucket')) {
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
  
  // 如果是 XML 错误响应，尝试解析
  if (errorStr.contains('<?xml')) {
    try {
      var xmlStart = errorStr.indexOf('<?xml');
      var xmlEnd = errorStr.indexOf('</Error>', xmlStart);
      if (xmlEnd > xmlStart) {
        var xmlContent = errorStr.substring(xmlStart, xmlEnd + 8);
        print('   XML 错误响应:');
        // 提取关键信息
        if (xmlContent.contains('<Code>')) {
          var codeStart = xmlContent.indexOf('<Code>') + 6;
          var codeEnd = xmlContent.indexOf('</Code>', codeStart);
          if (codeEnd > codeStart) {
            print('      Code: ${xmlContent.substring(codeStart, codeEnd)}');
          }
        }
        if (xmlContent.contains('<Message>')) {
          var msgStart = xmlContent.indexOf('<Message>') + 9;
          var msgEnd = xmlContent.indexOf('</Message>', msgStart);
          if (msgEnd > msgStart) {
            print('      Message: ${xmlContent.substring(msgStart, msgEnd)}');
          }
        }
        if (xmlContent.contains('<Resource>')) {
          var resStart = xmlContent.indexOf('<Resource>') + 10;
          var resEnd = xmlContent.indexOf('</Resource>', resStart);
          if (resEnd > resStart) {
            print('      Resource: ${xmlContent.substring(resStart, resEnd)}');
          }
        }
      }
    } catch (e) {
      // 解析失败，忽略
    }
  }
}
