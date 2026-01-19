import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/line.dart';
import 'package:wenzbak/src/service/data/impl/block_data_impl.dart';
import 'package:wenzbak/src/service/data/impl/block_file_upload_cache_impl.dart';
import 'package:wenzbak/src/service/index/indexes.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';

/// Block数据上传功能测试类
/// 用于测试block数据上传功能，包括：
/// 1. 通过addBackupData生成本地数据
/// 2. 调用uploadBlockData上传数据
/// 3. 验证上传是否成功
void main() async {
  print('=== Block数据上传功能测试 ===\n');

  // MinIO 配置信息
  var minioConfig = {
    'endpoint': 'http://localhost:9000',
    'accessKey': 'minioadmin',
    'secretKey': 'minioadmin',
    'bucket': 'wenzbak',
    'region': 'us-east-1',
  };

  // 创建测试配置
  var deviceId = 'test-device-block-001';
  var config = WenzbakConfig(
    deviceId: deviceId,
    localRootPath: './test_local_block_upload',
    remoteRootPath: 'wenzbak',
    storageType: 's3',
    storageConfig: jsonEncode(minioConfig),
  );

  // 创建block data service实例
  var blockDataService = WenzbakBlockDataServiceImpl(config);
  print('   设备 ID: $deviceId\n');

  // 测试用例
  var testResults = <String, bool>{};

  // 测试 1: 添加数据并上传（非加密模式）
  print('--- 测试 1: 添加数据并上传（非加密模式） ---');
  try {
    // 1. 通过addBackupData生成本地数据
    print('   步骤 1: 添加测试数据...');
    var testData = [
      '这是第一条测试数据',
      '这是第二条测试数据',
      '这是第三条测试数据',
      '测试数据包含中文和English',
      '测试数据包含特殊字符: !@#\$%^&*()',
    ];

    for (var i = 0; i < testData.length; i++) {
      var line = WenzbakDataLine(content: testData[i]);
      await blockDataService.addBackupData(line);
      print('   添加数据 ${i + 1}/${testData.length}: ${testData[i]}');
    }

    // 2. 等待文件写入完成
    await Future.delayed(Duration(seconds: 1));
    print('   ✅ 数据添加完成\n');

    // 3. 由于getUploadFiles只返回一小时之前的文件，我们需要手动触发上传
    // 方法：修改文件的时间戳，使其成为一小时之前的文件
    print('   步骤 2: 准备上传文件...');
    var blockFileCache = WenzbakBlockFileUploadCacheImpl(config);
    var uploadFiles = await blockFileCache.getUploadFiles(true);
    print('   当前可上传文件数: ${uploadFiles.length}');

    // 如果没有可上传的文件，说明文件是当前小时的，需要等待或手动修改
    if (uploadFiles.isEmpty) {
      print('   ⚠️  当前没有可上传的文件（文件是当前小时的）');
      print('   提示: getUploadFiles只返回一小时之前的文件');
      print('   解决方案: 等待1小时后再次运行，或手动修改文件时间戳\n');

      // 为了测试，我们可以直接调用上传方法，但会因为没有文件而直接返回
      print('   尝试调用uploadBlockData（预期：没有文件需要上传）...');
      await blockDataService.uploadBlockData(true);
      print('   ✅ uploadBlockData执行完成（没有文件需要上传）\n');

      // 为了完整测试，我们创建一个旧文件来测试上传功能
      // 注意：需要将文件添加到缓存中才能被识别
      print('   步骤 3: 创建测试用的旧文件并添加到缓存...');
      var oldDateTime = DateTime.now().subtract(Duration(hours: 2));
      var oldDateStr = _formatDateTimeForFileName(oldDateTime);
      var testUuid = Uuid().v4();
      var oldFileName = '$oldDateStr-$testUuid.txt';

      var blockDir = config.getLocalPublicBlockDir();
      var oldFilePath = [blockDir, oldFileName].join('/');
      var oldFile = File(oldFilePath);
      await FileUtils.createParentDir(oldFilePath);
      await oldFile.writeAsString('这是用于测试上传的旧文件数据\n测试数据行2\n测试数据行3');
      print('   创建旧文件: $oldFilePath');

      // 将文件添加到缓存中（通过读取和写入缓存文件）
      // 缓存文件格式：JSON，key为时间标识（yyyy-MM-dd-HH），value为文件路径
      var cacheFilePath = _getCacheFilePath(config);
      var cacheFile = File(cacheFilePath);
      Map<String, String> cacheMap = {};

      // 读取现有缓存
      if (await cacheFile.exists()) {
        try {
          var cacheContent = await cacheFile.readAsString();
          cacheMap = Map<String, String>.from(jsonDecode(cacheContent));
        } catch (e) {
          print('   ⚠️  读取缓存文件失败: $e');
        }
      }

      // 添加新文件到缓存（使用时间标识作为key）
      var cacheKey = oldDateStr; // 格式：yyyy-MM-dd-HH
      cacheMap[cacheKey] = oldFilePath;
      print('   将文件添加到缓存: key=$cacheKey, path=$oldFilePath');

      // 写回缓存文件
      await FileUtils.createParentDir(cacheFilePath);
      await cacheFile.writeAsString(jsonEncode(cacheMap));
      print('   ✅ 缓存文件已更新\n');

      // 重新读取缓存
      await blockFileCache.readCache();
      print('   ✅ 旧文件创建并添加到缓存完成\n');

      // 再次尝试上传
      print('   步骤 4: 再次尝试上传...');
      uploadFiles = await blockFileCache.getUploadFiles(true);
      print('   可上传文件数: ${uploadFiles.length}');

      if (uploadFiles.isNotEmpty) {
        print('   ✅ 找到可上传的文件');
        for (var file in uploadFiles) {
          print('     文件: $file');
        }
        print('');

        // 调用uploadBlockData上传
        print('   步骤 5: 调用uploadBlockData上传...');
        try {
          await blockDataService.loadBlockFileUploadCache();
          await blockDataService.uploadBlockData(true);
          print('   ✅ uploadBlockData执行完成\n');
        } catch (e, stackTrace) {
          print('   ❌ uploadBlockData执行失败: $e');
          print('   错误堆栈:');
          print(stackTrace);
          print('');
          rethrow;
        }

        // 验证上传是否成功
        print('   步骤 6: 验证上传结果...');
        var storage = WenzbakStorageClientService.getInstance(config);
        if (storage != null) {
          // 等待一下，确保索引已写入
          await Future.delayed(Duration(milliseconds: 500));

          // 检查本地索引文件是否存在
          var localIndexPath = config.getLocalBlockIndexPath();
          var localIndexFile = File(localIndexPath);
          print('   本地索引文件路径: $localIndexPath');
          print('   本地索引文件存在: ${await localIndexFile.exists()}');

          if (await localIndexFile.exists()) {
            var indexContent = await localIndexFile.readAsString();
            print('   本地索引文件内容长度: ${indexContent.length}');
            if (indexContent.isNotEmpty) {
              print('   本地索引文件内容:');
              var lines = indexContent
                  .split('\n')
                  .where((l) => l.trim().isNotEmpty)
                  .toList();
              print('   索引行数: ${lines.length}');
              for (var i = 0; i < lines.length && i < 5; i++) {
                print('     行${i + 1}: ${lines[i]}');
              }
            }
          }

          // 检查文件是否已上传
          // 由于我们不知道确切的remote path，我们检查索引
          // 注意：需要创建新的索引服务实例来强制重新读取
          var indexesService = WenzbakBlockIndexesService.getInstance(config);
          // 由于索引服务是单例，我们需要手动重新读取
          // 但readIndexes有isRead标志，所以我们需要直接读取文件
          var indexes = await indexesService.getIndexes();
          print('   索引文件数: ${indexes.length}');

          if (indexes.isNotEmpty) {
            print('   ✅ 找到上传的文件索引:');
            for (var entry in indexes.entries) {
              var path = entry.key;
              var sha256 = entry.value;
              print('     路径: $path');
              print('     SHA256: $sha256');

              // 验证远程文件是否存在
              try {
                var remoteFileData = await storage.readFile(path);
                if (remoteFileData != null) {
                  print('     ✅ 远程文件存在，大小: ${remoteFileData.length} 字节');

                  // 验证SHA256文件
                  var remoteSha256Bytes = await storage.readFile(
                    '$path.sha256',
                  );
                  if (remoteSha256Bytes != null) {
                    var remoteSha256 = String.fromCharCodes(
                      remoteSha256Bytes,
                    ).trim();
                    if (remoteSha256 == sha256) {
                      print('     ✅ SHA256验证成功');
                    } else {
                      print('     ⚠️  SHA256不匹配');
                    }
                  }
                } else {
                  print('     ⚠️  远程文件不存在');
                }
              } catch (e) {
                print('     ⚠️  读取远程文件失败: $e');
              }
            }
            testResults['uploadBlockData'] = true;
          } else {
            print('   ⚠️  没有找到上传的文件索引');
            testResults['uploadBlockData'] = false;
          }
        } else {
          print('   ⚠️  无法获取storage服务');
          testResults['uploadBlockData'] = false;
        }
      } else {
        print('   ⚠️  仍然没有可上传的文件');
        print('   提示: 文件可能还没有被缓存系统识别');
        testResults['uploadBlockData'] = false;
      }
    } else {
      // 如果有可上传的文件，直接上传
      print('   ✅ 找到可上传的文件');
      for (var file in uploadFiles) {
        print('     文件: $file');
      }
      print('');

      // 调用uploadBlockData上传
      print('   步骤 3: 调用uploadBlockData上传...');
      await blockDataService.uploadBlockData(true);
      print('   ✅ uploadBlockData执行完成\n');

      // 验证上传结果
      print('   步骤 4: 验证上传结果...');
      var storage = WenzbakStorageClientService.getInstance(config);
      if (storage != null) {
        var indexesService = WenzbakBlockIndexesService.getInstance(config);
        await indexesService.readIndexes();
        var indexes = await indexesService.getIndexes();
        print('   索引文件数: ${indexes.length}');

        if (indexes.isNotEmpty) {
          print('   ✅ 找到上传的文件索引');
          testResults['uploadBlockData'] = true;
        } else {
          print('   ⚠️  没有找到上传的文件索引');
          testResults['uploadBlockData'] = false;
        }
      } else {
        print('   ⚠️  无法获取storage服务');
        testResults['uploadBlockData'] = false;
      }
    }
  } catch (e, stackTrace) {
    print('❌ 测试失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadBlockData'] = false;
  }
  print('');

  // 测试 2: 加密模式上传
  print('--- 测试 2: 加密模式上传 ---');
  try {
    // 创建加密配置
    var encryptConfig = WenzbakConfig(
      deviceId: deviceId,
      localRootPath: './test_local_block_upload_encrypted',
      remoteRootPath: 'wenzbak',
      storageType: 's3',
      storageConfig: jsonEncode(minioConfig),
      encryptFile: true,
      secretKey: 'test-secret-key',
      secret: 'test-secret',
    );

    var encryptBlockDataService = WenzbakBlockDataServiceImpl(encryptConfig);
    print('   创建加密配置的block data service\n');

    // 添加测试数据
    print('   步骤 1: 添加加密测试数据...');
    var testData = ['这是加密模式的第一条测试数据', '这是加密模式的第二条测试数据'];

    for (var i = 0; i < testData.length; i++) {
      var line = WenzbakDataLine(content: testData[i]);
      await encryptBlockDataService.addBackupData(line);
      print('   添加数据 ${i + 1}/${testData.length}: ${testData[i]}');
    }

    await Future.delayed(Duration(seconds: 1));
    print('   ✅ 数据添加完成\n');

    // 尝试上传
    print('   步骤 2: 尝试上传...');
    var encryptBlockFileCache = WenzbakBlockFileUploadCacheImpl(encryptConfig);
    var encryptUploadFiles = await encryptBlockFileCache.getUploadFiles(true);
    print('   可上传文件数: ${encryptUploadFiles.length}');

    if (encryptUploadFiles.isEmpty) {
      print('   ⚠️  当前没有可上传的文件（文件是当前小时的）');
      print('   提示: 需要等待1小时或手动修改文件时间戳');
      testResults['uploadEncryptedBlockData'] = false;
    } else {
      print('   ✅ 找到可上传的文件');
      await encryptBlockDataService.uploadBlockData(true);
      print('   ✅ uploadBlockData执行完成');

      // 验证上传结果
      var storage = WenzbakStorageClientService.getInstance(encryptConfig);
      if (storage != null) {
        var indexesService = WenzbakBlockIndexesService.getInstance(
          encryptConfig,
        );
        await indexesService.readIndexes();
        var indexes = await indexesService.getIndexes();
        print('   索引文件数: ${indexes.length}');

        if (indexes.isNotEmpty) {
          print('   ✅ 找到上传的文件索引（加密模式）');
          testResults['uploadEncryptedBlockData'] = true;
        } else {
          print('   ⚠️  没有找到上传的文件索引');
          testResults['uploadEncryptedBlockData'] = false;
        }
      } else {
        print('   ⚠️  无法获取storage服务');
        testResults['uploadEncryptedBlockData'] = false;
      }
    }
  } catch (e, stackTrace) {
    print('❌ 加密模式测试失败: $e');
    print('   错误详情:');
    _printErrorDetails(e, stackTrace);
    testResults['uploadEncryptedBlockData'] = false;
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
    var testDirs = [
      Directory('./test_local_block_upload'),
      Directory('./test_local_block_upload_encrypted'),
    ];

    for (var dir in testDirs) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        print('✅ 已清理: ${dir.path}');
      }
    }
  } catch (e) {
    print('⚠️  清理测试文件失败: $e');
  }
}

/// 格式化日期时间为文件名格式
/// 格式：yyyy-MM-dd-HH
String _formatDateTimeForFileName(DateTime dateTime) {
  var year = dateTime.year;
  var month = dateTime.month.toString().padLeft(2, '0');
  var day = dateTime.day.toString().padLeft(2, '0');
  var hour = dateTime.hour.toString().padLeft(2, '0');
  return '$year-$month-$day-$hour';
}

/// 获取缓存文件路径
String _getCacheFilePath(WenzbakConfig config) {
  var localRootPath = config.localRootPath;
  if (localRootPath == null) {
    throw 'localRootPath is null';
  }
  var secretKey = config.secretKey;
  if (secretKey != null) {
    return [
      localRootPath,
      'private',
      secretKey,
      'data',
      'block_file_cache.json',
    ].join('/');
  }
  return [localRootPath, 'public', 'data', 'block_file_cache.json'].join('/');
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
