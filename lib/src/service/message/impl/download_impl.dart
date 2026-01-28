import 'dart:convert';
import 'dart:io';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/service/device/device.dart';
import 'package:wenzbak/src/service/message/download.dart';
import 'package:wenzbak/src/service/message/message.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/crypt_util.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 消息下载服务实现类
/// 负责消息下载、读取和文件下载功能
class WenzbakMessageDownloadServiceImpl extends WenzbakMessageDownloadService {
  final WenzbakConfig config;

  // 按小时分类的 uuid 缓存：key 为小时标识（如 "2025-01-15-14"），value 为该小时的所有 uuid
  final Map<String, Set<String>> _processedMessageUuids = {};
  final Map<String, String> _fileSha256Cache = {};
  final Map<String, WenzbakMessageLock> _deviceLockCache = {};

  WenzbakMessageDownloadServiceImpl(this.config) {
    _loadProcessedMessageUuids();
    _loadFileSha256Cache();
    _loadDeviceLockCache();
  }

  @override
  Future<void> readMessage(Iterable<MessageReceiver> receivers) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }
    var startTime = DateTime.now().millisecondsSinceEpoch;
    // 1. 读取设备列表
    var deviceService = WenzbakDeviceService.getInstance(config);
    var deviceIds = await deviceService.queryDeviceIdList();
    print("查询设备耗时：${DateTime.now().millisecondsSinceEpoch - startTime} ms");
    // 2. 遍历每个设备，读取 msg.lock 并判断是否有新消息
    var remoteMsgRootPath = config.getRemoteMessageRootPath();
    var futures = <Future>[];
    for (var deviceId in deviceIds) {
      if (deviceId == config.deviceId) {
        continue;
      }
      futures.add(
        _readDeviceMessage(remoteMsgRootPath, deviceId, storage, receivers),
      );
    }
    await Future.wait(futures);
    // 清理2小时之前的文件 sha256 缓存
    _cleanOldFileSha256Cache();

    // 保存缓存
    await _saveProcessedMessageUuids();
    await _saveFileSha256Cache();
    await _saveDeviceLockCache();
    print("读取消息总耗时：${DateTime.now().millisecondsSinceEpoch - startTime} ms");
  }

  Future<void> _readDeviceMessage(
    String remoteMsgRootPath,
    String deviceId,
    WenzbakStorageClientService storage,
    Iterable<MessageReceiver> receivers,
  ) async {
    try {
      var devicePath = [remoteMsgRootPath, deviceId].join("/");
      var remoteMsgLockFile = [devicePath, "msg.lock"].join("/");
      var lockBytes = await storage.readFile(remoteMsgLockFile);
      if (lockBytes == null || lockBytes.length < 16) {
        // 没有锁文件，跳过该设备
        return;
      }

      var remoteLock = WenzbakMessageLock.fromBytes(lockBytes);
      var localLock = _deviceLockCache[deviceId];

      // 判断是否有新消息：心跳时间或消息时间有更新
      bool hasNewMessage = false;
      if (localLock == null) {
        hasNewMessage = true;
      } else {
        // 心跳时间更新或消息时间更新，说明有新消息
        if (remoteLock.timestamp != null &&
            (localLock.timestamp == null ||
                remoteLock.timestamp! > localLock.timestamp!)) {
          hasNewMessage = true;
        }
        if (remoteLock.msgTimestamp != null &&
            (localLock.msgTimestamp == null ||
                remoteLock.msgTimestamp! > localLock.msgTimestamp!)) {
          hasNewMessage = true;
        }
      }

      if (!hasNewMessage) {
        // 没有新消息，跳过该设备
        return;
      }

      // 3. 读取设备消息文件：sha256 判断文件是否被更新，只读取近2小时的数据
      var deviceFiles = await storage.listFiles(devicePath);

      // 先找到所有消息文件的最大时间
      DateTime? maxFileTime;
      for (var file in deviceFiles) {
        var filePath = file.path;
        var isDir = file.isDir;
        if (isDir == true || filePath == null) {
          continue;
        }

        var filename = FileUtils.getFileName(filePath);
        // 只处理消息文件：.msg.gz 或 .msg.gz.enc
        if (!filename.contains('.msg-') || filename.endsWith('.sha256')) {
          continue;
        }

        // 解析文件名中的时间信息
        DateTime? fileTime = _parseTimeFromFilename(filename);
        if (fileTime != null) {
          if (maxFileTime == null || fileTime.isAfter(maxFileTime)) {
            maxFileTime = fileTime;
          }
        }
      }

      // 计算最大时间近2小时的时间点
      if (maxFileTime == null) {
        return;
      }
      var twoHoursBeforeMaxTime = maxFileTime.subtract(Duration(hours: 2));
      var futures = <Future>[];
      // 只处理最大时间近2小时内的文件
      for (var file in deviceFiles) {
        var filePath = file.path;
        var isDir = file.isDir;
        if (isDir == true || filePath == null) {
          continue;
        }

        futures.add(
          _readDeviceMessageFile(
            filePath,
            twoHoursBeforeMaxTime,
            maxFileTime,
            storage,
            receivers,
            deviceId,
          ),
        );
      }
      await Future.wait(futures);
      // 更新设备锁缓存
      _deviceLockCache[deviceId] = remoteLock;
    } catch (e) {
      // 忽略单个设备处理失败，继续处理其他设备
      print('处理设备消息失败: $deviceId, 错误: $e');
    }
  }

  Future<void> _readDeviceMessageFile(
    String filePath,
    DateTime twoHoursBeforeMaxTime,
    DateTime maxFileTime,
    WenzbakStorageClientService storage,
    Iterable<MessageReceiver> receivers,
    String deviceId,
  ) async {
    var filename = FileUtils.getFileName(filePath);
    // 只处理消息文件：.msg.gz 或 .msg.gz.enc
    if (!filename.contains('.msg-') || filename.endsWith('.sha256')) {
      return;
    }

    // 解析文件名中的时间信息，只处理最大时间近2小时的文件
    DateTime? fileTime = _parseTimeFromFilename(filename);
    if (fileTime == null) {
      return;
    }
    if (fileTime.isBefore(twoHoursBeforeMaxTime) ||
        fileTime.isAfter(maxFileTime)) {
      return;
    }

    // 检查文件是否更新（通过 sha256）
    var remoteSha256File = "$filePath.sha256";
    var remoteSha256Bytes = await storage.readFile(remoteSha256File);
    if (remoteSha256Bytes == null) {
      return;
    }
    var remoteSha256 = utf8.decode(remoteSha256Bytes).trim();
    var localSha256 = _fileSha256Cache[filePath];

    if (localSha256 == remoteSha256) {
      // 文件未更新，跳过
      return;
    }
    // 4. 下载并解析消息文件
    try {
      await _downloadAndParseMessageFile(
        filePath,
        receivers,
        deviceId,
        remoteSha256,
      );
      // 更新 sha256 缓存
      _fileSha256Cache[filePath] = remoteSha256;
    } catch (e) {
      // 忽略单个文件下载失败，继续处理其他文件
      print('下载消息文件失败: $filePath, 错误: $e');
    }
  }

  /// 下载并解析消息文件
  Future<void> _downloadAndParseMessageFile(
    String remoteFilePath,
    Iterable<MessageReceiver> receivers,
    String deviceId,
    String remoteSha256,
  ) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }

    var filename = FileUtils.getFileName(remoteFilePath);
    var localMsgRootPath = config.getLocalMessageRootPath();
    var localMsgWithDeviceIdPath = [localMsgRootPath, deviceId].join("/");
    var localDir = Directory(localMsgWithDeviceIdPath);
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }

    // 1. 下载消息文件（可能是加密的）
    bool isEncrypted = config.secretKey != null;
    var localMsgFile = [localMsgWithDeviceIdPath, filename].join("/");

    if (isEncrypted) {
      // 下载加密文件
      var localEncryptedFile = localMsgFile;
      localMsgFile = localEncryptedFile.substring(
        0,
        localEncryptedFile.length - 4,
      );
      await storage.downloadFile(remoteFilePath, localEncryptedFile);

      // 校验加密文件
      var sha256 = await Sha256Util.sha256File(localEncryptedFile);
      if (remoteSha256 != sha256) {
        await File(localEncryptedFile).delete();
        throw Exception("文件校验失败");
      }

      // 解密文件
      await WenzbakCryptUtil(
        config.secretKey ?? '',
        config.secret ?? '',
      ).decryptFile(localEncryptedFile, localMsgFile);
      await File(localEncryptedFile).delete();
    } else {
      // 下载压缩文件
      await storage.downloadFile(remoteFilePath, localMsgFile);

      // 校验压缩文件
      var localSha256 = await Sha256Util.sha256File(localMsgFile);
      if (remoteSha256 != localSha256) {
        await File(localMsgFile).delete();
        throw Exception("文件校验失败");
      }
    }

    // 2. 解压文件
    var gzipBytes = await File(localMsgFile).readAsBytes();
    var msgBytes = GZipUtil.decompressBytes(gzipBytes);

    // 3. 读取并解析消息，用 uuid 缓存判断消息是否被处理过
    var lines = utf8.decode(msgBytes).split("\n");
    for (var line in lines) {
      if (line.isEmpty) {
        continue;
      }
      try {
        var msg = WenzbakMessage.fromJson(jsonDecode(line));
        if (msg.uuid == null) {
          continue;
        }

        // 检查消息是否已处理过（检查所有小时的数据）
        bool isProcessed = false;
        for (var hourUuids in _processedMessageUuids.values) {
          if (hourUuids.contains(msg.uuid)) {
            isProcessed = true;
            break;
          }
        }
        if (isProcessed) {
          continue;
        }

        // 处理消息
        for (var receiver in receivers) {
          await receiver(msg);
        }

        // 将 uuid 添加到对应小时的缓存
        if (msg.timestamp != null) {
          var date = DateTime.fromMillisecondsSinceEpoch(msg.timestamp!);
          var hourKey = FileUtils.getTimeFilePath(date);
          _processedMessageUuids
              .putIfAbsent(hourKey, () => <String>{})
              .add(msg.uuid!);
        }
      } catch (e) {
        // 忽略单条消息解析失败，继续处理其他消息
        print('解析消息失败: $line, 错误: $e');
      }
    }
    // 4. 清理消息文件
    if (await File(localMsgFile).exists()) {
      await File(localMsgFile).delete();
    }
  }

  /// 从文件名中解析时间信息
  /// 文件名格式：YYYY-MM-DD-HH.msg 或 YYYY-MM-DD-HH.msg-0 等
  DateTime? _parseTimeFromFilename(String filename) {
    try {
      // 提取时间部分（YYYY-MM-DD-HH）
      // 文件名格式：YYYY-MM-DD-HH.msg 或 YYYY-MM-DD-HH.msg-0 等
      // 需要找到第一个点之前的部分，那就是时间部分
      var dotIndex = filename.indexOf('.');
      if (dotIndex <= 0) {
        return null;
      }

      var timePart = filename.substring(0, dotIndex);

      // 验证时间格式：YYYY-MM-DD-HH（正好4个部分，用-分隔）
      if (!_isTimeFormat(timePart)) {
        return null;
      }

      // 解析时间
      var timeParts = timePart.split('-');
      if (timeParts.length != 4) {
        return null;
      }

      var year = int.parse(timeParts[0]);
      var month = int.parse(timeParts[1]);
      var day = int.parse(timeParts[2]);
      var hour = int.parse(timeParts[3]);

      return DateTime(year, month, day, hour);
    } catch (e) {
      return null;
    }
  }

  /// 检查字符串是否是时间格式 YYYY-MM-DD-HH
  bool _isTimeFormat(String str) {
    var pattern = RegExp(r'^\d{4}-\d{2}-\d{2}-\d{2}$');
    return pattern.hasMatch(str);
  }

  /// 清理2小时之前的文件 sha256 缓存
  void _cleanOldFileSha256Cache() {
    var now = DateTime.now();
    var twoHoursAgo = now.subtract(Duration(hours: 2));

    var keysToRemove = <String>[];
    for (var filePath in _fileSha256Cache.keys) {
      var filename = FileUtils.getFileName(filePath);
      var fileTime = _parseTimeFromFilename(filename);
      if (fileTime == null || fileTime.isBefore(twoHoursAgo)) {
        keysToRemove.add(filePath);
      }
    }

    for (var key in keysToRemove) {
      _fileSha256Cache.remove(key);
    }
  }

  /// 加载已处理的消息 uuid 缓存
  void _loadProcessedMessageUuids() {
    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'processed_uuids.json'].join("/");
    if (File(cacheFile).existsSync()) {
      try {
        var content = File(cacheFile).readAsStringSync();
        var map = jsonDecode(content) as Map;
        for (var entry in map.entries) {
          var hourKey = entry.key as String;
          var uuids = (entry.value as List).cast<String>();
          _processedMessageUuids[hourKey] = uuids.toSet();
        }
      } catch (e) {
        print('加载已处理消息 uuid 缓存失败: $e');
      }
    }
  }

  /// 保存已处理的消息 uuid 缓存，自动清除2小时前的缓存
  Future<void> _saveProcessedMessageUuids() async {
    // 清理2小时之前的 uuid 缓存
    _cleanOldProcessedMessageUuids();

    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'processed_uuids.json'].join("/");
    try {
      await FileUtils.createParentDir(cacheFile);
      // 将 Set 转换为 List 以便序列化
      var mapToSave = <String, List<String>>{};
      for (var entry in _processedMessageUuids.entries) {
        mapToSave[entry.key] = entry.value.toList();
      }
      await File(cacheFile).writeAsString(jsonEncode(mapToSave));
    } catch (e) {
      print('保存已处理消息 uuid 缓存失败: $e');
    }
  }

  /// 清理2小时之前的已处理消息 uuid 缓存
  void _cleanOldProcessedMessageUuids() {
    var now = DateTime.now();
    var twoHoursAgo = now.subtract(Duration(hours: 2));

    var keysToRemove = <String>[];
    for (var hourKey in _processedMessageUuids.keys) {
      // 解析小时标识（格式：YYYY-MM-DD-HH）
      var timeParts = hourKey.split('-');
      if (timeParts.length != 4) {
        // 格式不正确，删除
        keysToRemove.add(hourKey);
        continue;
      }

      try {
        var year = int.parse(timeParts[0]);
        var month = int.parse(timeParts[1]);
        var day = int.parse(timeParts[2]);
        var hour = int.parse(timeParts[3]);
        var hourTime = DateTime(year, month, day, hour);

        if (hourTime.isBefore(twoHoursAgo)) {
          keysToRemove.add(hourKey);
        }
      } catch (e) {
        // 解析失败，删除
        keysToRemove.add(hourKey);
      }
    }

    for (var key in keysToRemove) {
      _processedMessageUuids.remove(key);
    }
  }

  /// 加载文件 sha256 缓存
  void _loadFileSha256Cache() {
    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'file_sha256_cache.json'].join("/");
    if (File(cacheFile).existsSync()) {
      try {
        var content = File(cacheFile).readAsStringSync();
        var map = jsonDecode(content) as Map;
        _fileSha256Cache.addAll(Map<String, String>.from(map));
      } catch (e) {
        print('加载文件 sha256 缓存失败: $e');
      }
    }
  }

  /// 保存文件 sha256 缓存
  Future<void> _saveFileSha256Cache() async {
    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'file_sha256_cache.json'].join("/");
    try {
      await FileUtils.createParentDir(cacheFile);
      await File(cacheFile).writeAsString(jsonEncode(_fileSha256Cache));
    } catch (e) {
      print('保存文件 sha256 缓存失败: $e');
    }
  }

  /// 加载设备锁缓存
  void _loadDeviceLockCache() {
    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'device_lock_cache.json'].join("/");
    if (File(cacheFile).existsSync()) {
      try {
        var content = File(cacheFile).readAsStringSync();
        var map = jsonDecode(content) as Map;
        for (var entry in map.entries) {
          var deviceId = entry.key as String;
          var lockData = entry.value as Map;
          _deviceLockCache[deviceId] = WenzbakMessageLock(
            timestamp: lockData['timestamp'] as int?,
            msgTimestamp: lockData['msgTimestamp'] as int?,
          );
        }
      } catch (e) {
        print('加载设备锁缓存失败: $e');
      }
    }
  }

  /// 保存设备锁缓存
  Future<void> _saveDeviceLockCache() async {
    var localMsgRootPath = config.getLocalMessageRootPath();
    var cacheFile = [localMsgRootPath, 'device_lock_cache.json'].join("/");
    try {
      await FileUtils.createParentDir(cacheFile);
      var map = <String, Map<String, int?>>{};
      for (var entry in _deviceLockCache.entries) {
        map[entry.key] = {
          'timestamp': entry.value.timestamp,
          'msgTimestamp': entry.value.msgTimestamp,
        };
      }
      await File(cacheFile).writeAsString(jsonEncode(map));
    } catch (e) {
      print('保存设备锁缓存失败: $e');
    }
  }
}
