import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 临时文件上传与清除功能测试类
/// 用于测试临时文件上传和自动清除功能，包括加密和非加密模式
void main() async {
  print('=== 临时文件上传与清除功能测试 ===\n');

  // MinIO 配置信息（参考 minio_storage_test.dart）
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建测试配置
  var deviceId = 'test-device-001';
  var config = WenzbakConfig(
    deviceId: deviceId,
    localRootPath: './test_local_temp_upload',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  // 创建文件服务实例
  var fileService = WenzbakFileServiceImpl(config);
  print('   设备 ID: $deviceId\n');

  // 测试用例
  var testResults = <String, bool>{};

  // 准备测试文件
  var testDir = Directory('./test_temp_upload_files');
  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }

  // 测试 1: 上传临时文件（非加密模式）
  print('--- 测试 1: 上传临时文件（非加密模式） ---');
  try {
    // 创建测试文件
    var testFile = File('${testDir.path}/test_temp_upload.txt');
    var testContent = 'Hello, Wenzbak! This is a temporary test file.';
    await testFile.writeAsString(testContent);
    print('   创建测试文件: ${testFile.path}');
    print('   文件内容: $testContent');

    // 上传临时文件
    var remotePath = await fileService.uploadTempFile(testFile.path);
    if (remotePath != null) {
      print('✅ 临时文件上传成功');
      print('   远程路径: $remotePath');

      // 验证文件是否已上传
      var storage = WenzbakStorageClientService.getInstance(config);
      if (storage != null) {
        // 检查远程文件是否存在
        var remoteFileData = await storage.readFile(remotePath);
        if (remoteFileData != null) {
          var remoteContent = String.fromCharCodes(remoteFileData);
          if (remoteContent == testContent) {
            print('✅ 文件内容验证成功');
          } else {
            print('⚠️  文件内容不匹配');
          }

          // 检查 SHA256 文件
          var remoteSha256Bytes = await storage.readFile('$remotePath.sha256');
          if (remoteSha256Bytes != null) {
            var remoteSha256 = String.fromCharCodes(remoteSha256Bytes).trim();
            var localSha256 = await Sha256Util.sha256File(testFile.path);
            if (remoteSha256 == localSha256) {
              print('✅ SHA256 验证成功: $localSha256');
            } else {
              print('⚠️  SHA256 不匹配');
              print('   本地: $localSha256');
              print('   远程: $remoteSha256');
            }
          }

          // 验证文件名包含时间前缀
          var fileName = remotePath.split('/').last;
          if (fileName.contains(RegExp(r'^\d{4}-\d{2}-\d{2}-\d{2}-'))) {
            print('✅ 文件名包含时间前缀（格式正确）');
          } else {
            print('⚠️  文件名不包含时间前缀');
          }
        }
      }
      testResults['uploadTempFile'] = true;
    } else {
      print('❌ 临时文件上传失败：返回路径为 null');
      testResults['uploadTempFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 临时文件上传失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadTempFile'] = false;
  }
  print('');

  // 测试 2: 上传加密临时文件
  print('--- 测试 2: 上传加密临时文件 ---');
  try {
    // 创建加密配置
    var encryptConfig = WenzbakConfig(
      deviceId: deviceId,
      localRootPath: './test_local_temp_upload',
      remoteRootPath: 'wenzbak',
      storageType: 's3',
      storageConfig: jsonEncode(minioConfig),
      encryptFile: true,
      secretKey: 'test-secret-key',
      secret: 'test-secret',
    );

    var encryptFileService = WenzbakFileServiceImpl(encryptConfig);

    // 创建测试文件
    var testFile = File('${testDir.path}/test_temp_upload_encrypted.txt');
    var testContent = 'Hello, Wenzbak! This is an encrypted temporary test file.';
    await testFile.writeAsString(testContent);
    print('   创建测试文件: ${testFile.path}');
    print('   文件内容: $testContent');

    // 上传临时文件
    var remotePath = await encryptFileService.uploadTempFile(testFile.path);
    if (remotePath != null) {
      print('✅ 加密临时文件上传成功');
      print('   远程路径: $remotePath');

      // 验证文件是否已上传（应该是 .enc 后缀）
      if (remotePath.endsWith('.enc')) {
        print('✅ 远程路径包含 .enc 后缀（正确）');
      } else {
        print('⚠️  远程路径不包含 .enc 后缀');
      }

      // 验证文件名包含时间前缀
      var fileName = remotePath.split('/').last;
      if (fileName.contains(RegExp(r'^\d{4}-\d{2}-\d{2}-\d{2}-.*\.enc$'))) {
        print('✅ 文件名包含时间前缀和.enc后缀（格式正确）');
      } else {
        print('⚠️  文件名格式不正确');
      }

      // 验证 SHA256
      var storage = WenzbakStorageClientService.getInstance(encryptConfig);
      if (storage != null) {
        var remoteSha256Bytes = await storage.readFile('$remotePath.sha256');
        if (remoteSha256Bytes != null) {
          var remoteSha256 = String.fromCharCodes(remoteSha256Bytes).trim();
          print('✅ 远程 SHA256: $remoteSha256');
        }
      }
      testResults['uploadEncryptedTempFile'] = true;
    } else {
      print('❌ 加密临时文件上传失败：返回路径为 null');
      testResults['uploadEncryptedTempFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 加密临时文件上传失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadEncryptedTempFile'] = false;
  }
  print('');

  // 测试 3: 上传不存在的临时文件（应该抛出异常）
  print('--- 测试 3: 上传不存在的临时文件（应该抛出异常） ---');
  try {
    var nonExistentFile = '${testDir.path}/non_existent_temp_file.txt';
    await fileService.uploadTempFile(nonExistentFile);
    print('❌ 应该抛出异常，但没有抛出');
    testResults['uploadNonExistentTempFile'] = false;
  } catch (e) {
    if (e.toString().contains('不存在')) {
      print('✅ 正确抛出异常: $e');
      testResults['uploadNonExistentTempFile'] = true;
    } else {
      print('⚠️  抛出了异常，但异常信息不正确: $e');
      testResults['uploadNonExistentTempFile'] = false;
    }
  }
  print('');

  // 测试 4: 清除1天前的临时文件
  print('--- 测试 4: 清除1天前的临时文件 ---');
  try {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage != null) {
      // 先上传一些测试文件
      var testFile1 = File('${testDir.path}/test_old_file1.txt');
      await testFile1.writeAsString('Old file 1');
      var remotePath1 = await fileService.uploadTempFile(testFile1.path);
      print('   上传测试文件1: $remotePath1');

      var testFile2 = File('${testDir.path}/test_old_file2.txt');
      await testFile2.writeAsString('Old file 2');
      var remotePath2 = await fileService.uploadTempFile(testFile2.path);
      print('   上传测试文件2: $remotePath2');

      // 列出清除前的文件
      var tempAssetsPath = config.getRemoteTempAssetPath();
      var filesBefore = await storage.listFiles(tempAssetsPath);
      print('   清除前的文件数量: ${filesBefore.length}');

      // 执行清除操作（注意：由于文件是刚上传的，不会超过1天，所以不会被清除）
      await fileService.deleteTempFile();
      print('✅ 清除操作执行成功');

      // 列出清除后的文件
      var filesAfter = await storage.listFiles(tempAssetsPath);
      print('   清除后的文件数量: ${filesAfter.length}');

      // 由于文件是刚上传的，不应该被清除
      if (filesAfter.length >= filesBefore.length) {
        print('✅ 新上传的文件未被清除（正确）');
        testResults['deleteTempFile'] = true;
      } else {
        print('⚠️  新上传的文件被清除了（可能有问题）');
        testResults['deleteTempFile'] = false;
      }

      // 注意：要测试真正清除1天前的文件，需要手动创建带有旧时间前缀的文件
      // 或者等待1天后再测试
      print('   提示：要测试清除1天前的文件，需要创建带有旧时间前缀的文件');
    } else {
      print('❌ 无法获取存储服务');
      testResults['deleteTempFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 清除临时文件测试失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['deleteTempFile'] = false;
  }
  print('');

  // 测试 5: 验证时间前缀格式
  print('--- 测试 5: 验证时间前缀格式 ---');
  try {
    var testFile = File('${testDir.path}/test_time_format.txt');
    await testFile.writeAsString('Test time format');
    var remotePath = await fileService.uploadTempFile(testFile.path);
    
    if (remotePath != null) {
      var fileName = remotePath.split('/').last;
      // 移除可能的.enc后缀
      var nameWithoutExt = fileName.endsWith('.enc') 
          ? fileName.substring(0, fileName.length - 4)
          : fileName;
      
      // 提取时间前缀（前4个用-分隔的部分）
      var parts = nameWithoutExt.split('-');
      if (parts.length >= 4) {
        var timePart = parts.sublist(0, 4).join('-');
        var pattern = RegExp(r'^\d{4}-\d{2}-\d{2}-\d{2}$');
        if (pattern.hasMatch(timePart)) {
          print('✅ 时间前缀格式正确: $timePart');
          print('   完整文件名: $fileName');
          testResults['verifyTimeFormat'] = true;
        } else {
          print('⚠️  时间前缀格式不正确: $timePart');
          testResults['verifyTimeFormat'] = false;
        }
      } else {
        print('⚠️  文件名格式不正确，无法提取时间前缀');
        testResults['verifyTimeFormat'] = false;
      }
    } else {
      print('❌ 上传失败，无法验证时间格式');
      testResults['verifyTimeFormat'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 验证时间格式失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['verifyTimeFormat'] = false;
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

  // 清理测试文件（可选）
  print('\n--- 清理测试文件 ---');
  try {
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
      print('✅ 测试文件已清理');
    }
  } catch (e) {
    print('⚠️  清理测试文件失败: $e');
  }
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
