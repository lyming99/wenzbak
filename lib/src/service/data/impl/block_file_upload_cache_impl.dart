import 'dart:convert';
import 'dart:io';

import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/utils/file_utils.dart';

import '../block_file_upload_cache.dart';

/// 待上传block数据文件缓存实现类
class WenzbakBlockFileUploadCacheImpl implements WenzbakBlockFileUploadCache {
  final WenzbakConfig config;

  /// 缓存数据：key 为文件标识（如 date-uuid），value 为文件路径
  final Map<String, String> _cache = {};

  /// 操作锁
  final Lock _lock = Lock();

  /// 缓存文件路径
  String get _cacheFilePath {
    var localRootPath = config.localRootPath;
    if (localRootPath == null) {
      throw 'localRootPath is null';
    }
    return [localRootPath, 'public', 'data', 'block_file_cache.json'].join('/');
  }

  WenzbakBlockFileUploadCacheImpl(this.config) {
    // 初始化时读取缓存
    readCache();
  }

  @override
  Future<String?> getCurrentCacheFile(DateTime? dateTime) async {
    try {
      var now = dateTime ?? DateTime.now();
      // 生成当前小时的文件路径标识
      // 格式：yyyy-MM-dd-HH
      var dateStr = FileUtils.getTimeFilePath(now);
      var cacheKey = dateStr;
      // 如果缓存中已存在当前小时的文件，返回已有路径
      if (_cache.containsKey(cacheKey)) {
        return _cache[cacheKey];
      }
      var needWrite = false;
      var ret = await _lock.synchronized(() async {
        // 如果缓存中已存在当前小时的文件，返回已有路径
        if (_cache.containsKey(cacheKey)) {
          return _cache[cacheKey];
        }
        var blockDir = config.getLocalPublicBlockDir();
        // 确保目录存在
        var dir = Directory(blockDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        needWrite = true;
        var fileName = Uuid().v4();
        _cache[cacheKey] = [blockDir, "$cacheKey-$fileName.txt"].join('/');
        return _cache[cacheKey];
      });
      if (needWrite) {
        // 保存缓存
        await writeCache();
      }
      return ret;
    } finally {}
  }

  @override
  Future<List<String>> getUploadFiles(bool oneHoursAgo) async {
    return await _lock.synchronized(() async {
      if (!oneHoursAgo) {
        return _cache.values.toList();
      }
      var now = DateTime.now();
      var oneHourAgo = now.subtract(const Duration(hours: 1));

      var uploadFiles = <String>[];

      // 遍历缓存，找出所有一小时之前的文件
      var keysToCheck = List<String>.from(_cache.keys);
      for (var key in keysToCheck) {
        try {
          // 解析时间标识：yyyy-MM-dd-HH
          var parts = key.split('-');
          if (parts.length != 4) {
            // 格式不正确，跳过
            continue;
          }

          var year = int.parse(parts[0]);
          var month = int.parse(parts[1]);
          var day = int.parse(parts[2]);
          var hour = int.parse(parts[3]);
          var fileTime = DateTime(year, month, day, hour);

          // 如果文件时间在一小时之前，添加到上传列表
          if (fileTime.isBefore(oneHourAgo)) {
            var filePath = _cache[key];
            if (filePath != null && await File(filePath).exists()) {
              uploadFiles.add(filePath);
            }
          }
        } catch (e) {
          // 解析失败，跳过
          continue;
        }
      }

      return uploadFiles;
    });
  }

  @override
  Future<void> removeFile(String filePath) async {
    await _lock.synchronized(() async {
      // 从缓存中查找并移除对应的条目
      var keysToRemove = <String>[];
      for (var entry in _cache.entries) {
        if (entry.value == filePath) {
          keysToRemove.add(entry.key);
        }
      }
      // 移除缓存条目
      for (var key in keysToRemove) {
        _cache.remove(key);
      }

      // 删除物理文件
      var file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    });
    // 保存缓存
    await writeCache();
  }

  @override
  Future<void> readCache() async {
    var keysToRemove = <String>[];
    await _lock.synchronized(() async {
      var cacheFile = File(_cacheFilePath);
      if (!await cacheFile.exists()) {
        return;
      }

      try {
        var content = await cacheFile.readAsString();
        var map = jsonDecode(content) as Map;
        _cache.clear();
        _cache.addAll(Map<String, String>.from(map));

        // 验证缓存中的文件是否仍然存在，移除不存在的文件
        var keysToRemove = <String>[];
        for (var entry in _cache.entries) {
          if (!await File(entry.value).exists()) {
            keysToRemove.add(entry.key);
          }
        }
        for (var key in keysToRemove) {
          _cache.remove(key);
        }
      } catch (e) {
        print('读取block文件缓存失败: $e');
        // 读取失败时清空缓存
        _cache.clear();
      }
    });
    // 如果有清理，保存缓存
    if (keysToRemove.isNotEmpty) {
      await writeCache();
    }
  }

  @override
  Future<void> writeCache() async {
    await _lock.synchronized(() async {
      try {
        await FileUtils.createParentDir(_cacheFilePath);
        await File(_cacheFilePath).writeAsString(jsonEncode(_cache));
      } catch (e) {
        print('写入block文件缓存失败: $e');
      }
    });
  }
}
