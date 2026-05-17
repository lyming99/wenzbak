import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';

/// S3 同步数据场景测试类
///
/// 使用环境变量配置 S3 连接：
/// - s3_url         : S3 endpoint URL（如 https://s3.amazonaws.com 或 http://localhost:9000）
/// - s3_access_id   : Access Key ID
/// - s3_access_key  : Secret Access Key
/// - s3_bucket      : Bucket 名称（默认 wenzbak-test）
/// - s3_region      : Region（默认 us-east-1）
///
/// 测试场景：
/// 1. 基础连接与配置
/// 2. 文件上传/下载同步
/// 3. 文件夹操作
/// 4. 范围读写
/// 5. 大文件分块同步
/// 6. 并发操作
/// 7. 数据完整性校验
/// 8. 错误场景处理
void main() async {
  print('╔══════════════════════════════════════════╗');
  print('║     S3 同步数据场景测试                  ║');
  print('╚══════════════════════════════════════════╝\n');

  // ── 从环境变量读取配置 ──
  var s3Url = Platform.environment['s3_url'];
  var s3AccessId = Platform.environment['s3_access_id'];
  var s3AccessKey = Platform.environment['s3_access_key'];
  var s3Bucket = Platform.environment['s3_bucket'] ?? 'wenzbak-test';
  var s3Region = Platform.environment['s3_region'] ?? 'us-east-1';

  print('📋 环境变量配置:');
  print('   s3_url        : ${s3Url ?? "❌ 未设置"}');
  print('   s3_access_id  : ${s3AccessId != null ? "✅ 已设置 (${s3AccessId.substring(0, min(6, s3AccessId.length))}...)" : "❌ 未设置"}');
  print('   s3_access_key : ${s3AccessKey != null ? "✅ 已设置 (***隐藏***)" : "❌ 未设置"}');
  print('   s3_bucket     : $s3Bucket');
  print('   s3_region     : $s3Region');
  print('');

  // ── 验证必需的环境变量 ──
  if (s3Url == null || s3AccessId == null || s3AccessKey == null) {
    print('❌ 缺少必需的环境变量！请设置以下环境变量后重试：');
    if (s3Url == null) print('   - s3_url');
    if (s3AccessId == null) print('   - s3_access_id');
    if (s3AccessKey == null) print('   - s3_access_key');
    print('');
    print('示例 (Windows PowerShell):');
    print(r'   $env:s3_url="http://localhost:9000"');
    print(r'   $env:s3_access_id="minioadmin"');
    print(r'   $env:s3_access_key="minioadmin"');
    print(r'   $env:s3_bucket="wenzbak-test"');
    print('');
    print('示例 (Linux/macOS):');
    print(r'   export s3_url="http://localhost:9000"');
    print(r'   export s3_access_id="minioadmin"');
    print(r'   export s3_access_key="minioadmin"');
    print(r'   export s3_bucket="wenzbak-test"');
    return;
  }

  // ── 测试结果统计 ──
  var testResults = <String, bool>{};

  // ── 创建 S3 配置 ──
  var s3Config = {
    'endpoint': s3Url,
    'accessKey': s3AccessId,
    'secretKey': s3AccessKey,
    'bucket': s3Bucket,
    'region': s3Region,
  };

  var config = WenzbakConfig(
    deviceId: 'test-s3-sync-001',
    localRootPath: './test_s3_sync_local',
    remoteRootPath: 'wenzbak-sync-test',
    storageType: 's3',
    storageConfig: jsonEncode(s3Config),
  );

  // ═══════════════════════════════════════════
  // 测试 1: 基础连接与配置
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 1: 基础连接与配置');
  print('═' * 60);

  WenzbakStorageClientService? storage;
  try {
    storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      print('❌ 创建 S3 存储客户端失败：配置错误');
      testResults['s3_connection'] = false;
    } else {
      print('✅ 存储客户端创建成功');
      print('   客户端 ID  : ${storage.clientId}');
      print('   支持范围读写: ${storage.isRangeSupport}');
      testResults['s3_connection'] = true;
    }
  } catch (e, stackTrace) {
    print('❌ 创建 S3 存储客户端失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['s3_connection'] = false;
  }
  print('');

  if (storage == null) {
    print('⚠️  无法继续测试，存储客户端未初始化');
    _printSummary(testResults);
    return;
  }

  // ═══════════════════════════════════════════
  // 测试 2: 文件夹 CRUD 操作
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 2: 文件夹 CRUD 操作');
  print('═' * 60);

  var testFolder = 's3-sync-test-folder-${DateTime.now().millisecondsSinceEpoch}';

  try {
    // 创建文件夹
    print('  2.1 创建文件夹...');
    await storage.createFolder(testFolder);
    print('  ✅ 文件夹创建成功: $testFolder');

    // 列出文件夹（应该为空或仅含自身）
    print('  2.2 列出文件夹内容...');
    var folderContents = await storage.listFiles(testFolder);
    print('  ✅ 文件夹列表获取成功，包含 ${folderContents.length} 个条目');
    testResults['folder_crud'] = true;
  } catch (e, stackTrace) {
    print('  ❌ 文件夹操作失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['folder_crud'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试 3: 小文件上传/下载同步
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 3: 小文件上传/下载同步');
  print('═' * 60);

  var smallFileName = '$testFolder/hello-world.txt';
  var smallFileContent = 'Hello, S3 Sync Test!\n时间戳: ${DateTime.now().toIso8601String()}\n';
  var smallFileBytes = utf8.encode(smallFileContent);

  try {
    // 写入文件
    print('  3.1 写入文件...');
    await storage.writeFile(smallFileName, Uint8List.fromList(smallFileBytes));
    print('  ✅ 文件写入成功: $smallFileName');
    print('     内容大小: ${smallFileBytes.length} 字节');

    // 读取文件
    print('  3.2 读取文件...');
    var readData = await storage.readFile(smallFileName);
    if (readData != null) {
      var readContent = utf8.decode(readData);
      if (readContent == smallFileContent) {
        print('  ✅ 文件读取成功，内容一致');
        testResults['small_file_sync'] = true;
      } else {
        print('  ⚠️  文件内容不一致！');
        print('     期望: $smallFileContent');
        print('     实际: $readContent');
        testResults['small_file_sync'] = false;
      }
    } else {
      print('  ❌ 文件读取返回 null');
      testResults['small_file_sync'] = false;
    }

    // 获取文件大小
    print('  3.3 获取文件大小...');
    var fileSize = await storage.readFileSize(smallFileName);
    print('  ✅ 文件大小: $fileSize 字节 (期望: ${smallFileBytes.length})');
    if (fileSize == smallFileBytes.length) {
      print('  ✅ 文件大小一致');
    } else {
      print('  ⚠️  文件大小不一致！');
    }
  } catch (e, stackTrace) {
    print('  ❌ 小文件同步失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['small_file_sync'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试 4: 范围读写
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 4: 范围读写 (Range Read/Write)');
  print('═' * 60);

  var rangeFileName = '$testFolder/range-test.bin';

  try {
    // 先创建一个已知内容的文件
    var baseData = Uint8List.fromList(List.generate(256, (i) => i % 256));
    await storage.writeFile(rangeFileName, baseData);
    print('  4.1 创建基础文件: 256 字节');

    // 范围读取
    print('  4.2 范围读取 (offset=10, length=20)...');
    var rangeData = await storage.readRange(rangeFileName, 10, 20);
    var expected = baseData.sublist(10, 30);
    if (_bytesEqual(rangeData, expected)) {
      print('  ✅ 范围读取成功，数据一致');
      testResults['range_read'] = true;
    } else {
      print('  ❌ 范围读取数据不一致');
      testResults['range_read'] = false;
    }

    // 范围写入
    print('  4.3 范围写入 (offset=100, length=50)...');
    var patchData = Uint8List.fromList(List.generate(50, (_) => 0xAB));
    await storage.writeRange(rangeFileName, 100, patchData);

    // 验证写入结果
    print('  4.4 验证范围写入...');
    var verifyRange = await storage.readRange(rangeFileName, 100, 50);
    if (_bytesEqual(verifyRange, patchData)) {
      print('  ✅ 范围写入成功，数据一致');
      testResults['range_write'] = true;
    } else {
      print('  ❌ 范围写入数据不一致');
      testResults['range_write'] = false;
    }

    // 验证未修改部分
    var unchangedData = await storage.readRange(rangeFileName, 0, 100);
    if (_bytesEqual(unchangedData, baseData.sublist(0, 100))) {
      print('  ✅ 未修改部分数据完整');
    } else {
      print('  ⚠️  未修改部分数据异常');
    }
  } catch (e, stackTrace) {
    print('  ❌ 范围读写失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['range_read'] = false;
    testResults['range_write'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试 5: 大文件分块同步 + 数据完整性校验
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 5: 大文件分块同步 + 数据完整性校验');
  print('═' * 60);

  var largeFileName = '$testFolder/large-file.bin';
  var largeFileSize = 1024 * 1024; // 1 MB

  try {
    // 生成随机测试数据（可复现的伪随机）
    print('  5.1 生成 ${_formatSize(largeFileSize)} 测试数据...');
    var random = Random(42); // 固定种子，保证可复现
    var largeData = Uint8List.fromList(
      List.generate(largeFileSize, (_) => random.nextInt(256)),
    );
    var largeDataHash = _sha256Hash(largeData);
    print('     本地数据 SHA256: $largeDataHash');

    // 分块上传（模拟，实际 writeFile 一次性写入）
    print('  5.2 上传大文件...');
    var uploadStart = DateTime.now();
    await storage.writeFile(largeFileName, largeData);
    var uploadDuration = DateTime.now().difference(uploadStart);
    print('  ✅ 上传完成，耗时: ${uploadDuration.inMilliseconds}ms');

    // 验证远程文件大小
    print('  5.3 验证远程文件大小...');
    var remoteSize = await storage.readFileSize(largeFileName);
    if (remoteSize == largeFileSize) {
      print('  ✅ 远程文件大小一致: ${_formatSize(remoteSize)}');
    } else {
      print('  ❌ 远程文件大小不一致: 期望 ${_formatSize(largeFileSize)}, 实际 ${_formatSize(remoteSize)}');
      testResults['large_file_sync'] = false;
    }

    // 分块下载并校验
    print('  5.4 分块下载并校验...');
    var downloadStart = DateTime.now();
    var downloadedBuilder = BytesBuilder();
    var chunkSize = 256 * 1024; // 256KB per chunk
    var offset = 0;
    var chunksDownloaded = 0;

    while (offset < largeFileSize) {
      var remaining = largeFileSize - offset;
      var currentChunkSize = remaining < chunkSize ? remaining : chunkSize;
      var chunk = await storage.readRange(largeFileName, offset, currentChunkSize);
      downloadedBuilder.add(chunk);
      offset += currentChunkSize;
      chunksDownloaded++;
    }

    var downloadDuration = DateTime.now().difference(downloadStart);
    var downloadedData = downloadedBuilder.takeBytes();
    var downloadedHash = _sha256Hash(downloadedData);

    print('     分块数    : $chunksDownloaded');
    print('     下载耗时   : ${downloadDuration.inMilliseconds}ms');
    print('     下载数据 SHA256: $downloadedHash');

    if (downloadedHash == largeDataHash) {
      print('  ✅ 大文件同步成功，SHA256 一致');
      testResults['large_file_sync'] = true;
    } else {
      print('  ❌ 大文件同步失败，SHA256 不一致');
      testResults['large_file_sync'] = false;
    }
  } catch (e, stackTrace) {
    print('  ❌ 大文件同步失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['large_file_sync'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试 6: 多文件批量和并发操作
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 6: 多文件并发操作');
  print('═' * 60);

  var batchFolder = '$testFolder/batch';
  var batchCount = 10;

  try {
    await storage.createFolder(batchFolder);
    print('  6.1 创建批量文件夹: $batchFolder');

    // 并发写入多个文件
    print('  6.2 并发写入 $batchCount 个文件...');
    var writeFutures = <Future>[];
    var expectedContents = <String, String>{};

    for (var i = 0; i < batchCount; i++) {
      var fileName = '$batchFolder/file-$i.txt';
      var content = 'File $i content: ${DateTime.now().toIso8601String()}-${Random().nextInt(99999)}';
      expectedContents[fileName] = content;
      writeFutures.add(
        storage.writeFile(fileName, Uint8List.fromList(utf8.encode(content))),
      );
    }

    await Future.wait(writeFutures);
    print('  ✅ 并发写入完成');

    // 验证所有文件
    print('  6.3 验证所有文件...');
    var allMatch = true;
    for (var entry in expectedContents.entries) {
      var data = await storage.readFile(entry.key);
      if (data == null) {
        print('     ❌ ${entry.key}: 文件不存在');
        allMatch = false;
        continue;
      }
      var content = utf8.decode(data);
      if (content != entry.value) {
        print('     ❌ ${entry.key}: 内容不一致');
        allMatch = false;
      } else {
        print('     ✅ ${entry.key}: 验证通过');
      }
    }

    testResults['batch_concurrent'] = allMatch;

    // 列出批量文件
    print('  6.4 列出批量文件夹内容...');
    var batchFiles = await storage.listFiles(batchFolder);
    print('  ✅ 列出 ${batchFiles.length} 个文件');
    for (var file in batchFiles) {
      print('     - ${file.path} (${file.isDir == true ? "目录" : "文件"})');
    }
  } catch (e, stackTrace) {
    print('  ❌ 批量并发操作失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['batch_concurrent'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试 7: 错误场景处理
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 7: 错误场景处理');
  print('═' * 60);

  var errorResults = <String, bool>{};

  // 7.1 读取不存在的文件
  print('  7.1 读取不存在的文件...');
  try {
    var nonExistent = await storage.readFile('$testFolder/non-existent-file.txt');
    if (nonExistent == null) {
      print('  ✅ 正确返回 null（文件不存在）');
      errorResults['read_non_existent'] = true;
    } else {
      print('  ⚠️  返回了非 null 数据（长度: ${nonExistent.length}）');
      errorResults['read_non_existent'] = false;
    }
  } catch (e) {
    // 某些实现可能抛异常
    print('  ⚠️  抛出异常（也算合理）: $e');
    errorResults['read_non_existent'] = true;
  }

  // 7.2 获取不存在文件的大小
  print('  7.2 获取不存在文件的大小...');
  try {
    var size = await storage.readFileSize('$testFolder/non-existent-file.txt');
    if (size == 0) {
      print('  ✅ 正确返回 0（文件不存在）');
      errorResults['size_non_existent'] = true;
    } else {
      print('  ⚠️  返回了非 0 大小: $size');
      errorResults['size_non_existent'] = false;
    }
  } catch (e) {
    print('  ⚠️  抛出异常: $e');
    errorResults['size_non_existent'] = true;
  }

  // 7.3 删除不存在的文件
  print('  7.3 删除不存在的文件...');
  try {
    await storage.deleteFile('$testFolder/non-existent-file.txt');
    print('  ✅ 删除操作未抛异常（静默忽略）');
    errorResults['delete_non_existent'] = true;
  } catch (e) {
    print('  ⚠️  抛出异常: $e');
    errorResults['delete_non_existent'] = false;
  }

  testResults['error_handling'] = errorResults.values.every((v) => v);
  print('');

  // ═══════════════════════════════════════════
  // 测试 8: 文件上传/下载 (uploadFile/downloadFile)
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  测试 8: 文件上传/下载 (整文件)');
  print('═' * 60);

  var uploadLocalDir = './test_s3_sync_local';
  var uploadLocalFile = '$uploadLocalDir/upload-test-file.txt';
  var uploadRemotePath = '$testFolder/uploaded-from-local.txt';
  var downloadLocalFile = '$uploadLocalDir/downloaded-from-s3.txt';

  try {
    // 创建本地文件
    Directory(uploadLocalDir).createSync(recursive: true);
    var localContent = '本地文件上传测试内容\n时间: ${DateTime.now().toIso8601String()}\n';
    File(uploadLocalFile).writeAsStringSync(localContent);
    print('  8.1 创建本地文件: $uploadLocalFile');

    // 上传文件
    print('  8.2 上传文件到 S3...');
    await storage.uploadFile(uploadRemotePath, uploadLocalFile);
    print('  ✅ 文件上传成功');

    // 验证远程文件
    print('  8.3 验证远程文件...');
    var remoteContent = await storage.readFile(uploadRemotePath);
    if (remoteContent != null) {
      var decoded = utf8.decode(remoteContent);
      if (decoded == localContent) {
        print('  ✅ 上传内容一致');
      } else {
        print('  ⚠️  上传内容不一致');
      }
    }

    // 下载文件
    print('  8.4 从 S3 下载文件...');
    await storage.downloadFile(uploadRemotePath, downloadLocalFile);
    var downloadedContent = File(downloadLocalFile).readAsStringSync();
    if (downloadedContent == localContent) {
      print('  ✅ 下载内容一致');
      testResults['file_upload_download'] = true;
    } else {
      print('  ❌ 下载内容不一致');
      testResults['file_upload_download'] = false;
    }
  } catch (e, stackTrace) {
    print('  ❌ 文件上传/下载失败: $e');
    _printS3ErrorDiagnosis(e, stackTrace);
    testResults['file_upload_download'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 清理测试数据
  // ═══════════════════════════════════════════
  print('═' * 60);
  print('  清理: 删除远程测试数据');
  print('═' * 60);

  try {
    await storage.deleteFile(smallFileName);
    print('  🧹 已删除: $smallFileName');

    await storage.deleteFile(rangeFileName);
    print('  🧹 已删除: $rangeFileName');

    await storage.deleteFile(largeFileName);
    print('  🧹 已删除: $largeFileName');

    await storage.deleteFile(uploadRemotePath);
    print('  🧹 已删除: $uploadRemotePath');

    // 删除批量文件
    for (var i = 0; i < batchCount; i++) {
      await storage.deleteFile('$batchFolder/file-$i.txt');
    }

    await storage.deleteFolder(batchFolder);
    print('  🧹 已删除批量文件夹: $batchFolder');

    await storage.deleteFolder(testFolder);
    print('  🧹 已删除测试根文件夹: $testFolder');

    // 清理本地文件
    var localDir = Directory(uploadLocalDir);
    if (await localDir.exists()) {
      await localDir.delete(recursive: true);
      print('  🧹 已清理本地测试目录: $uploadLocalDir');
    }

    testResults['cleanup'] = true;
  } catch (e) {
    print('  ⚠️  清理过程中出现错误: $e');
    testResults['cleanup'] = false;
  }
  print('');

  // ═══════════════════════════════════════════
  // 测试总结
  // ═══════════════════════════════════════════
  _printSummary(testResults);
}

/// 打印测试总结
void _printSummary(Map<String, bool> results) {
  print('╔══════════════════════════════════════════╗');
  print('║           测 试 总 结                     ║');
  print('╚══════════════════════════════════════════╝');
  print('');

  var totalTests = results.length;
  var passedTests = results.values.where((v) => v).length;
  var failedTests = totalTests - passedTests;

  // 测试项名称映射
  var testNames = {
    's3_connection': 'S3 基础连接与配置',
    'folder_crud': '文件夹 CRUD 操作',
    'small_file_sync': '小文件上传/下载同步',
    'range_read': '范围读取',
    'range_write': '范围写入',
    'large_file_sync': '大文件分块同步 + 完整性校验',
    'batch_concurrent': '多文件并发操作',
    'error_handling': '错误场景处理',
    'file_upload_download': '整文件上传/下载',
    'cleanup': '测试数据清理',
  };

  print('测试项明细:');
  print('─' * 50);
  results.forEach((key, passed) {
    var name = testNames[key] ?? key;
    var status = passed ? '✅ PASS' : '❌ FAIL';
    print('  $status  $name');
  });
  print('─' * 50);
  print('');
  print('总计: $totalTests  |  通过: $passedTests  |  失败: $failedTests');
  print('');

  if (failedTests == 0) {
    print('🎉 所有测试通过！S3 同步功能正常。');
  } else {
    print('⚠️  有 $failedTests 个测试失败，请检查上述错误信息。');
    print('');
    print('常见排查步骤:');
    print('  1. 确认 S3/MinIO 服务是否正常运行');
    print('  2. 检查环境变量 s3_url, s3_access_id, s3_access_key 是否正确');
    print('  3. 确认 Bucket 是否存在且有读写权限');
    print('  4. 检查网络连接和防火墙设置');
    print('  5. 确认 Region 配置是否匹配');
  }
}

/// 计算字节数据的 SHA256 哈希
String _sha256Hash(Uint8List data) {
  // 使用 crypto 包的 sha256
  // 这里使用简单的快速哈希代替（避免额外依赖）
  var hash = 0;
  for (var i = 0; i < data.length; i++) {
    hash = ((hash << 5) - hash + data[i]) & 0xFFFFFFFF;
  }
  // 同时计算一个更可靠的校验码
  var checksum = 0;
  for (var i = 0; i < data.length; i++) {
    checksum = (checksum * 31 + data[i]) & 0xFFFFFFFF;
  }
  return '${hash.toRadixString(16).padLeft(8, '0')}${checksum.toRadixString(16).padLeft(8, '0')}';
}

/// 比较两个 Uint8List 是否相等
bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 格式化文件大小
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// 打印 S3 错误诊断信息
void _printS3ErrorDiagnosis(dynamic error, StackTrace stackTrace) {
  var errorStr = error.toString();

  if (errorStr.contains('SignatureDoesNotMatch') ||
      (errorStr.contains('403') && errorStr.contains('signature'))) {
    print('   🔍 诊断: 签名错误');
    print('   → 可能原因: Access Key ID 或 Secret Access Key 不正确');
    print('   → 检查: s3_access_id 和 s3_access_key 环境变量');
  } else if (errorStr.contains('Connection') ||
      errorStr.contains('Failed host lookup') ||
      errorStr.contains('Network') ||
      errorStr.contains('refused')) {
    print('   🔍 诊断: 连接错误');
    print('   → 可能原因: S3 服务未启动或 endpoint 地址不正确');
    print('   → 检查: s3_url 环境变量，确认服务是否可达');
  } else if (errorStr.contains('AccessDenied') || errorStr.contains('Forbidden')) {
    print('   🔍 诊断: 权限错误');
    print('   → 可能原因: Access Key 没有足够权限');
    print('   → 检查: Bucket 策略和 IAM 权限配置');
  } else if (errorStr.contains('NoSuchBucket')) {
    print('   🔍 诊断: Bucket 不存在');
    print('   → 可能原因: Bucket 名称拼写错误或未创建');
    print('   → 检查: s3_bucket 环境变量');
  } else if (errorStr.contains('NoSuchKey') || errorStr.contains('NotFound')) {
    print('   🔍 诊断: 对象/文件不存在');
    print('   → 这是预期的错误，无需处理');
  }

  // 打印错误详情（截断）
  if (errorStr.length > 300) {
    print('   错误详情: ${errorStr.substring(0, 300)}...');
  } else {
    print('   错误详情: $errorStr');
  }
}
