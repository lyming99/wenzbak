import 'dart:convert';
import 'dart:io';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/file/impl/file_impl.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 文件上传功能测试类
/// 用于测试文件上传功能，包括加密和非加密模式
void main() async {
  print('=== 文件上传功能测试 ===\n');

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
    localRootPath: './test_local_file_upload',
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
  var testDir = Directory('./test_upload_files');
  if (!await testDir.exists()) {
    await testDir.create(recursive: true);
  }

  // 测试 1: 上传普通文件（非加密模式）
  print('--- 测试 1: 上传普通文件（非加密模式） ---');
  try {
    // 创建测试文件
    var testFile = File('${testDir.path}/test_upload.txt');
    var testContent = 'Hello, Wenzbak! This is a test file for upload.';
    await testFile.writeAsString(testContent);
    print('   创建测试文件: ${testFile.path}');
    print('   文件内容: $testContent');

    // 上传文件
    var remotePath = await fileService.uploadFile(testFile.path);
    if (remotePath != null) {
      print('✅ 文件上传成功');
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
        }
      }
      testResults['uploadNormalFile'] = true;
    } else {
      print('❌ 文件上传失败：返回路径为 null');
      testResults['uploadNormalFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 文件上传失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadNormalFile'] = false;
  }
  print('');

  // 测试 2: 上传加密文件
  print('--- 测试 2: 上传加密文件 ---');
  try {
    // 创建加密配置
    var encryptConfig = WenzbakConfig(
      deviceId: deviceId,
      localRootPath: './test_local_file_upload',
      remoteRootPath: 'wenzbak',
      storageType: 's3',
      storageConfig: jsonEncode(minioConfig),
      encryptFile: true,
      secretKey: 'test-secret-key',
      secret: 'test-secret',
    );

    var encryptFileService = WenzbakFileServiceImpl(encryptConfig);

    // 创建测试文件
    var testFile = File('${testDir.path}/test_upload_encrypted.txt');
    var testContent = 'Hello, Wenzbak! This is an encrypted test file.';
    await testFile.writeAsString(testContent);
    print('   创建测试文件: ${testFile.path}');
    print('   文件内容: $testContent');

    // 上传文件
    var remotePath = await encryptFileService.uploadFile(testFile.path);
    if (remotePath != null) {
      print('✅ 加密文件上传成功');
      print('   远程路径: $remotePath');

      // 验证文件是否已上传（应该是 .enc 后缀）
      if (remotePath.endsWith('.enc')) {
        print('✅ 远程路径包含 .enc 后缀（正确）');
      } else {
        print('⚠️  远程路径不包含 .enc 后缀');
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
      testResults['uploadEncryptedFile'] = true;
    } else {
      print('❌ 加密文件上传失败：返回路径为 null');
      testResults['uploadEncryptedFile'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 加密文件上传失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadEncryptedFile'] = false;
  }
  print('');

  // 测试 3: 上传相同文件（SHA256 一致，应该跳过上传）
  print('--- 测试 3: 上传相同文件（SHA256 一致，应该跳过上传） ---');
  try {
    // 使用相同的测试文件
    var testFile = File('${testDir.path}/test_upload.txt');
    if (!await testFile.exists()) {
      print('⚠️  测试文件不存在，跳过此测试');
      testResults['uploadSameFile'] = false;
    } else {
      var firstUploadTime = DateTime.now();
      var remotePath1 = await fileService.uploadFile(testFile.path);
      var firstUploadDuration = DateTime.now().difference(firstUploadTime);

      var secondUploadTime = DateTime.now();
      var remotePath2 = await fileService.uploadFile(testFile.path);
      var secondUploadDuration = DateTime.now().difference(secondUploadTime);

      if (remotePath1 == remotePath2) {
        print('✅ 两次上传返回相同的远程路径');
        print('   第一次上传耗时: ${firstUploadDuration.inMilliseconds}ms');
        print('   第二次上传耗时: ${secondUploadDuration.inMilliseconds}ms');
        if (secondUploadDuration < firstUploadDuration) {
          print('✅ 第二次上传更快（可能跳过了实际上传）');
        }
        testResults['uploadSameFile'] = true;
      } else {
        print('⚠️  两次上传返回不同的远程路径');
        testResults['uploadSameFile'] = false;
      }
    }
  } catch (e, stackTrace) {
    print('❌ 上传相同文件测试失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadSameFile'] = false;
  }
  print('');

  // 测试 4: 上传不存在的文件（应该抛出异常）
  print('--- 测试 4: 上传不存在的文件（应该抛出异常） ---');
  try {
    var nonExistentFile = '${testDir.path}/non_existent_file.txt';
    await fileService.uploadFile(nonExistentFile);
    print('❌ 应该抛出异常，但没有抛出');
    testResults['uploadNonExistentFile'] = false;
  } catch (e) {
    if (e.toString().contains('不存在')) {
      print('✅ 正确抛出异常: $e');
      testResults['uploadNonExistentFile'] = true;
    } else {
      print('⚠️  抛出了异常，但异常信息不正确: $e');
      testResults['uploadNonExistentFile'] = false;
    }
  }
  print('');

  // 测试 5: 上传后下载验证
  print('--- 测试 5: 上传后下载验证 ---');
  try {
    // 创建新测试文件
    var testFile = File('${testDir.path}/test_upload_download.txt');
    var testContent = 'Test content for upload and download verification.';
    await testFile.writeAsString(testContent);

    // 上传文件
    var remotePath = await fileService.uploadFile(testFile.path);
    if (remotePath != null) {
      print('   上传成功，远程路径: $remotePath');

      // 下载文件
      var downloadedPath = await fileService.downloadFile(remotePath);
      if (downloadedPath != null) {
        print('   下载成功，本地路径: $downloadedPath');

        // 验证文件内容
        var downloadedContent = await File(downloadedPath).readAsString();
        if (downloadedContent == testContent) {
          print('✅ 上传下载验证成功：文件内容一致');
          testResults['uploadDownloadVerify'] = true;
        } else {
          print('⚠️  文件内容不一致');
          print('   原始: $testContent');
          print('   下载: $downloadedContent');
          testResults['uploadDownloadVerify'] = false;
        }
      } else {
        print('❌ 文件下载失败：返回路径为 null');
        testResults['uploadDownloadVerify'] = false;
      }
    } else {
      print('❌ 文件上传失败：返回路径为 null');
      testResults['uploadDownloadVerify'] = false;
    }
  } catch (e, stackTrace) {
    print('❌ 上传下载验证失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadDownloadVerify'] = false;
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
