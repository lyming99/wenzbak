import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/message.dart';
import 'package:wenzbak/src/service/message/upload.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/crypt_util.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:synchronized/synchronized.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 消息上传服务实现类
/// 负责消息缓存、写入和上传功能
class WenzbakMessageUploadServiceImpl extends WenzbakMessageUploadService {
  final WenzbakConfig config;
  final WenzbakMessageLock _messageLock = WenzbakMessageLock();
  final Lock _msgUploadLock = Lock();
  final Lock _msgCacheLock = Lock();
  Queue<WenzbakMessage> _messageCache = Queue();
  int? _lastUploadTime;

  WenzbakMessageUploadServiceImpl(this.config);

  @override
  Future<void> addMessage(WenzbakMessage message) async {
    await _msgUploadLock.synchronized(() async {
      await _addMsg(message);
      await _writeMsgCache();
    });
  }

  @override
  Future<void> readCache() async {
    await _readMsgCache();
  }

  @override
  Future<void> executeUploadTask() async {
    if (_messageCache.isEmpty) {
      return;
    }
    var lastUploadTime = _lastUploadTime;
    var now = DateTime.now().millisecondsSinceEpoch;
    if (lastUploadTime != null) {
      // 频率限制3秒一次
      var d = 3000;
      if (now - lastUploadTime < d) {
        var delay = d - (now - lastUploadTime) + 1;
        Timer(Duration(milliseconds: delay), () {
          executeUploadTask();
        });
        return;
      }
    }
    _lastUploadTime = now;
    await _msgUploadLock.synchronized(() async {
      Set<String> msgFilePaths = {};
      String msgRootPath = config.getLocalMessageRootPath();
      // 1.编码消息并且写入文件
      while (true) {
        var msg = await _removeFirstMsg();
        if (msg == null) {
          break;
        }
        var time = msg.timestamp;
        if (time == null) {
          continue;
        }
        var date = DateTime.fromMillisecondsSinceEpoch(time);
        var timeFilePath = FileUtils.getTimeFilePath(date);
        String msgFilePath = [msgRootPath, "$timeFilePath.msg"].join("/");
        var msgIndexFile = await _calcMsgFileIndex(msgFilePath);
        _messageLock.updateTime(time);
        await FileUtils.appendLine(msgIndexFile, jsonEncode(msg.toJson()));
        msgFilePaths.add(msgIndexFile);
      }
      List<String> uploadFilePaths = [];
      // 2.压缩以及加密文件
      for (var msgFilePath in msgFilePaths) {
        String msgGzipFilePath = "$msgFilePath.gz";
        String msgEncryptFilePath = "$msgFilePath.gz.enc";
        bool needEncrypt = config.secretKey != null;
        // 压缩消息文件
        await GZipUtil.compressFile(msgFilePath, msgGzipFilePath);
        // 加密消息文件
        if (needEncrypt) {
          await WenzbakCryptUtil(
            config.secretKey ?? '',
            config.secret ?? '',
          ).encryptFile(msgGzipFilePath, msgEncryptFilePath);
          uploadFilePaths.add(msgEncryptFilePath);
        } else {
          uploadFilePaths.add(msgGzipFilePath);
        }
      }
      // 3.上传文件
      for (var uploadFilePath in uploadFilePaths) {
        await _uploadMsgFile(uploadFilePath);
      }
      // 4.写入lock
      await _uploadMsgLock();
      // 5.保存消息缓存
      await _writeMsgCache();
      // 6.删除过期消息文件
      await _deleteOldMsg();
    });
  }

  /// 计算消息文件索引
  Future<String> _calcMsgFileIndex(
    String msgFilePath, [
    int maxBlockLength = 128 * 1024,
  ]) async {
    var index = 0;
    while (true) {
      String tempPath = "$msgFilePath-$index";
      var exist = await FileUtils.exist(tempPath);
      if (exist) {
        var length = await FileUtils.getFileLength(tempPath);
        if (length > maxBlockLength) {
          index++;
        } else {
          return tempPath;
        }
      } else {
        return tempPath;
      }
    }
  }

  Future<void> _addMsg(WenzbakMessage msg) async {
    await _msgCacheLock.synchronized(() async {
      _messageCache.add(msg);
    });
  }

  Future<WenzbakMessage?> _removeFirstMsg() async {
    return await _msgCacheLock.synchronized(() async {
      if (_messageCache.isEmpty) {
        return null;
      }
      return _messageCache.removeFirst();
    });
  }

  /// 读取消息缓存
  Future<void> _readMsgCache() async {
    await _msgCacheLock.synchronized(() async {
      String msgCacheFile = config.getLocalMessageCacheFile();
      if (await FileUtils.exist(msgCacheFile)) {
        var lines = await FileUtils.readLines(msgCacheFile);
        Queue<WenzbakMessage> msgCache = Queue();
        for (var line in lines) {
          if (line.isNotEmpty) {
            var msg = WenzbakMessage.fromJson(jsonDecode(line));
            msgCache.add(msg);
          }
        }
        _messageCache = msgCache;
      }
    });
  }

  /// 写入消息缓存
  Future<void> _writeMsgCache() async {
    await _msgCacheLock.synchronized(() async {
      var lines = _messageCache.map((e) => jsonEncode(e.toJson())).toList();
      String msgCacheFile = config.getLocalMessageCacheFile();
      await FileUtils.writeLines(msgCacheFile, lines);
    });
  }

  /// 上传消息文件
  Future<void> _uploadMsgFile(String localMsgFile) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }
    // 1.获取remote路径
    var remoteMsgRootPath = config.getRemoteCurrentMessagePath();
    // 可能为msg.gz 和 msg.gz.enc
    var filename = FileUtils.getFileName(localMsgFile);
    var remoteMsgFile = [remoteMsgRootPath, filename].join("/");
    // 2.上传消息文件
    await storage.uploadFile(remoteMsgFile, localMsgFile);
    // 3.上传消息文件sha256
    var remoteMsgSha256File = [remoteMsgFile, "sha256"].join(".");
    var sha256 = await Sha256Util.sha256File(localMsgFile);
    await storage.writeFile(remoteMsgSha256File, utf8.encode(sha256));
  }

  /// 上传消息锁文件
  Future<void> _uploadMsgLock() async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }
    // 1.获取remote路径
    var remoteMsgRootPath = config.getRemoteCurrentMessagePath();
    var remoteMsgLockFile = [remoteMsgRootPath, "msg.lock"].join("/");
    var bytes = _messageLock.toBytes();
    // 2.写入状态文件
    await storage.writeFile(remoteMsgLockFile, bytes);
  }

  /// 删除过期消息文件
  Future<void> _deleteOldMsg() async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }
    var remoteMsgRootPath = config.getRemoteCurrentMessagePath();
    var files = await storage.listFiles(remoteMsgRootPath);

    // 计算2小时前的时间戳
    var now = DateTime.now();
    var twoHoursAgo = now.subtract(Duration(hours: 2));

    // 用于存储需要删除的文件路径（避免重复删除）
    Set<String> filesToDelete = {};

    for (var file in files) {
      var filePath = file.path;
      var isDir = file.isDir;
      if (isDir == true) {
        continue;
      }
      if (filePath == null) {
        continue;
      }
      // 2025-01-02-01开头
      var filename = FileUtils.getFileName(filePath);

      // 解析文件名中的时间信息
      // 文件名格式：YYYY-MM-DD-HH.msg 或 YYYY-MM-DD-HH.msg-0 等
      // 可能的后缀：.msg, .msg-0, .msg-0.gz, .msg-0.enc, .msg-0.gz.sha256 等
      DateTime? fileTime = _parseTimeFromFilename(filename);
      if (fileTime == null) {
        continue;
      }

      // 判断文件时间是否超过2小时
      if (fileTime.isBefore(twoHoursAgo)) {
        filesToDelete.add(filePath);
      }
    }

    // 删除所有需要删除的文件
    for (var filePath in filesToDelete) {
      try {
        await storage.deleteFile(filePath);
      } catch (e) {
        // 忽略删除失败的文件，继续删除其他文件
        print('删除文件失败: $filePath, 错误: $e');
      }
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

  @override
  Future<String?> uploadFile(String localPath) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }

    // 检查本地文件是否存在
    var localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception("本地文件不存在: $localPath");
    }

    // 1. 生成上传文件路径：[remoteRootMessagePath]/assets/[时间]-[uuid].[type]
    var remoteMsgRootPath = config.getRemoteMessageRootPath();
    var now = DateTime.now();
    var timeStr = FileUtils.getTimeFilePath(now);
    var uuid = Uuid().v4();

    // 获取文件扩展名
    var fileType = FileUtils.getFileExtension(localPath);

    // 生成远程文件路径
    var remoteFilePath = [
      remoteMsgRootPath,
      'assets',
      '$timeStr-$uuid${fileType.isNotEmpty ? '.$fileType' : ''}',
    ].join('/');

    // 2. 调用 storage 上传文件
    try {
      await storage.uploadFile(remoteFilePath, localPath);
      return remoteFilePath;
    } catch (e) {
      print('上传文件失败: $localPath, 错误: $e');
      return null;
    }
  }

  @override
  Future<void> deleteOldFiles() async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }

    var remoteMsgRootPath = config.getRemoteMessageRootPath();
    var assetsPath = [remoteMsgRootPath, 'assets'].join('/');

    // 列出 assets 目录下的所有文件
    var files = await storage.listFiles(assetsPath);

    // 计算1天前的时间
    var now = DateTime.now();
    var oneDayAgo = now.subtract(Duration(days: 1));

    // 用于存储需要删除的文件路径（避免重复删除）
    Set<String> filesToDelete = {};

    for (var file in files) {
      var filePath = file.path;
      var isDir = file.isDir;
      if (isDir == true) {
        continue;
      }
      if (filePath == null) {
        continue;
      }

      var filename = FileUtils.getFileName(filePath);

      // 解析文件名中的时间信息
      // 文件名格式：YYYY-MM-DD-HH-uuid.type
      DateTime? fileTime = _parseTimeFromAssetsFilename(filename);
      if (fileTime == null) {
        continue;
      }

      // 判断文件时间是否超过1天
      if (fileTime.isBefore(oneDayAgo)) {
        filesToDelete.add(filePath);
      }
    }

    // 删除所有需要删除的文件
    for (var filePath in filesToDelete) {
      try {
        await storage.deleteFile(filePath);
      } catch (e) {
        // 忽略删除失败的文件，继续删除其他文件
        print('删除文件失败: $filePath, 错误: $e');
      }
    }
  }

  /// 从 assets 文件名中解析时间信息
  /// 文件名格式：YYYY-MM-DD-HH-uuid.type
  DateTime? _parseTimeFromAssetsFilename(String filename) {
    try {
      // 文件名格式：YYYY-MM-DD-HH-uuid.type
      // 需要找到第一个点之前的部分，然后提取时间部分（前4个用-分隔的部分）
      var dotIndex = filename.indexOf('.');
      var nameWithoutExt = dotIndex > 0
          ? filename.substring(0, dotIndex)
          : filename;

      // 按 - 分割，前4个部分是时间：YYYY-MM-DD-HH
      var parts = nameWithoutExt.split('-');
      if (parts.length < 4) {
        return null;
      }

      // 验证时间格式：YYYY-MM-DD-HH（正好4个部分）
      var timePart = parts.sublist(0, 4).join('-');
      if (!_isTimeFormat(timePart)) {
        return null;
      }

      // 解析时间
      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      var hour = int.parse(parts[3]);

      return DateTime(year, month, day, hour);
    } catch (e) {
      return null;
    }
  }
}
