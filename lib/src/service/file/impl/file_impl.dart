import 'dart:io';
import 'dart:convert';

import 'package:wenzbak/src/service/file/file.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/crypt_util.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 文件管理器实现
class WenzbakFileServiceImpl implements WenzbakFileService {
  final WenzbakConfig config;

  WenzbakFileServiceImpl(this.config);

  @override
  Future<String?> downloadFile(String remotePath) async {
    var name = FileUtils.getFileName(remotePath);
    var savePath = config.getLocalFileSavePath(name);
    if (savePath == null) {
      return null;
    }
    if (savePath.endsWith(".enc")) {
      savePath = savePath.substring(0, savePath.length - 4);
    }
    var sha256File = "$name.sha256";
    if (await File(sha256File).exists() && await File(savePath).exists()) {
      return savePath;
    }
    await _downloadFile(remotePath, savePath, sha256File);
    return savePath;
  }

  Future _downloadFile(
    String remotePath,
    String savePath,
    String sha256File,
  ) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }
    var saveDir = config.getLocalAssetPath();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    bool isEncryptFile = config.encryptFile && config.secretKey != null;
    await storage.downloadFile("$remotePath.sha256", sha256File);
    if (isEncryptFile) {
      var encryptFilePath = "$savePath.enc";
      await storage.downloadFile(remotePath, encryptFilePath);
      var sha256 = await Sha256Util.sha256File(encryptFilePath);
      if (sha256 != await File(sha256File).readAsString()) {
        await File(encryptFilePath).delete();
        await File(sha256File).delete();
        throw Exception("文件校验失败");
      }
      await WenzbakCryptUtil(
        config.secretKey ?? '',
        config.secret ?? '',
      ).decryptFile(encryptFilePath, savePath);
      await File(encryptFilePath).delete();
    } else {
      await storage.downloadFile(remotePath, savePath);
      var sha256 = await Sha256Util.sha256File(savePath);
      if (sha256 != await File(sha256File).readAsString()) {
        await File(savePath).delete();
        await File(sha256File).delete();
        throw Exception("文件校验失败");
      }
    }
  }

  @override
  Future<String?> uploadFile(String localPath) async {
    // 1. 检查本地文件是否存在
    var localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception("本地文件不存在: $localPath");
    }

    // 2. 获取存储服务
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }

    // 3. 读取local文件名称，拼接remote文件路径
    var fileName = FileUtils.getFileName(localPath);
    var remoteAssetPath = config.getRemoteAssetPath();
    var remotePath = [remoteAssetPath, fileName].join('/');

    // 4. 判断是否需要加密
    bool isEncryptFile =
        config.encryptFile && config.secretKey != null && config.secret != null;

    String? encryptedFilePath;
    String fileToHash;

    try {
      // 5. 如果配置了加密模式，则对文件加密
      if (isEncryptFile) {
        var assetsPath = config.getLocalSecretAssetPath();
        // 确保目录存在
        var assetsDir = Directory(assetsPath);
        if (!await assetsDir.exists()) {
          await assetsDir.create(recursive: true);
        }
        encryptedFilePath = "$assetsPath/$fileName.enc";
        await WenzbakCryptUtil(
          config.secretKey!,
          config.secret!,
        ).encryptFile(localPath, encryptedFilePath);
        fileToHash = encryptedFilePath;
        // 加密后的远程路径
        remotePath = "$remotePath.enc";
      } else {
        fileToHash = localPath;
      }

      // 6. 读取本地文件sha256（如果文件加密了，则读取加密后的文件sha256）
      var localSha256 = await Sha256Util.sha256File(fileToHash);

      // 7. 读取remote文件sha256
      String? remoteSha256;
      try {
        var remoteSha256Bytes = await storage.readFile("$remotePath.sha256");
        if (remoteSha256Bytes != null) {
          remoteSha256 = utf8.decode(remoteSha256Bytes).trim();
        }
      } catch (e) {
        // 远程sha256文件不存在，继续上传
        remoteSha256 = null;
      }

      // 8. 如果sha256不一致，则调用storage进行上传文件
      if (remoteSha256 == null || localSha256 != remoteSha256) {
        // 上传文件
        if (isEncryptFile && encryptedFilePath != null) {
          await storage.uploadFile(remotePath, encryptedFilePath);
        } else {
          await storage.uploadFile(remotePath, localPath);
        }

        // 上传sha256文件
        await storage.writeFile("$remotePath.sha256", utf8.encode(localSha256));
      }

      // 9. 上传完成后，返回上传后的路径
      return remotePath;
    } finally {
      // 清理临时加密文件
      if (encryptedFilePath != null && await File(encryptedFilePath).exists()) {
        await File(encryptedFilePath).delete();
      }
    }
  }

  @override
  Future<String?> uploadTempFile(String localPath) async {
    // 1. 检查本地文件是否存在
    var localFile = File(localPath);
    if (!await localFile.exists()) {
      throw Exception("本地文件不存在: $localPath");
    }

    // 2. 获取存储服务
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }

    // 3. 读取local文件名称，拼接remote文件路径，文件前缀要携带日期和时间(yyyy-MM-dd-HH)
    var fileName = FileUtils.getFileName(localPath);
    var now = DateTime.now();
    var timePrefix = FileUtils.getTimeFilePath(now);
    // 文件名格式：yyyy-MM-dd-HH-{原文件名}
    var remoteFileName = '$timePrefix-$fileName';
    // 文件夹在~/tempAssets/
    var remoteTempAssetsPath = config.getRemoteTempAssetPath();
    var remotePath = [remoteTempAssetsPath, remoteFileName].join('/');

    // 4. 判断是否需要加密
    bool isEncryptFile =
        config.encryptFile && config.secretKey != null && config.secret != null;

    String? encryptedFilePath;
    String fileToHash;

    try {
      // 5. 如果配置了加密模式，则对文件加密
      if (isEncryptFile) {
        var assetsPath = config.getLocalSecretAssetPath();
        // 确保目录存在
        var assetsDir = Directory(assetsPath);
        if (!await assetsDir.exists()) {
          await assetsDir.create(recursive: true);
        }
        encryptedFilePath = "$assetsPath/$remoteFileName.enc";
        await WenzbakCryptUtil(
          config.secretKey!,
          config.secret!,
        ).encryptFile(localPath, encryptedFilePath);
        fileToHash = encryptedFilePath;
        // 加密后的远程路径
        remotePath = "$remotePath.enc";
      } else {
        fileToHash = localPath;
      }

      // 6. 读取本地文件sha256（如果文件加密了，则读取加密后的文件sha256）
      var localSha256 = await Sha256Util.sha256File(fileToHash);

      // 7. 调用storage进行上传文件
      if (isEncryptFile && encryptedFilePath != null) {
        await storage.uploadFile(remotePath, encryptedFilePath);
      } else {
        await storage.uploadFile(remotePath, localPath);
      }

      // 8. 上传完成后上传sha256文件
      await storage.writeFile("$remotePath.sha256", utf8.encode(localSha256));

      // 9. 上传完成后，返回上传后的路径
      return remotePath;
    } finally {
      // 清理临时加密文件
      if (encryptedFilePath != null && await File(encryptedFilePath).exists()) {
        await File(encryptedFilePath).delete();
      }
    }
  }

  @override
  Future<void> deleteTempFile() async {
    // 1. 获取存储服务
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }

    // 2. 获取tempAssets目录路径
    var remoteTempAssetsPath = config.getRemoteTempAssetPath();

    // 3. 列出tempAssets目录下的所有文件
    var files = await storage.listFiles(remoteTempAssetsPath);

    // 4. 计算1天前的时间
    var now = DateTime.now();
    var oneDayAgo = now.subtract(Duration(days: 1));

    // 5. 用于存储需要删除的文件路径（避免重复删除）
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

      // 跳过sha256文件，它们会在主文件被删除时一起处理
      if (filePath.endsWith('.sha256')) {
        continue;
      }

      var filename = FileUtils.getFileName(filePath);

      // 6. 解析文件名中的时间信息
      // 文件名格式：YYYY-MM-DD-HH-{原文件名} 或 YYYY-MM-DD-HH-{原文件名}.enc
      DateTime? fileTime = _parseTimeFromTempFilename(filename);
      if (fileTime == null) {
        continue;
      }

      // 7. 判断文件时间是否超过1天
      if (fileTime.isBefore(oneDayAgo)) {
        filesToDelete.add(filePath);
        // 同时添加对应的sha256文件
        filesToDelete.add("$filePath.sha256");
      }
    }

    // 8. 删除所有需要删除的文件
    for (var filePath in filesToDelete) {
      try {
        await storage.deleteFile(filePath);
      } catch (e) {
        // 忽略删除失败的文件，继续删除其他文件
        print('删除临时文件失败: $filePath, 错误: $e');
      }
    }
  }

  /// 从临时文件名中解析时间信息
  /// 文件名格式：YYYY-MM-DD-HH-{原文件名} 或 YYYY-MM-DD-HH-{原文件名}.enc
  DateTime? _parseTimeFromTempFilename(String filename) {
    try {
      // 文件名格式：YYYY-MM-DD-HH-{原文件名} 或 YYYY-MM-DD-HH-{原文件名}.enc
      // 需要提取时间部分（前4个用-分隔的部分）
      // 先去掉可能的.enc后缀
      var nameWithoutExt = filename;
      if (filename.endsWith('.enc')) {
        nameWithoutExt = filename.substring(0, filename.length - 4);
      }

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

  /// 检查字符串是否是时间格式 YYYY-MM-DD-HH
  bool _isTimeFormat(String str) {
    var pattern = RegExp(r'^\d{4}-\d{2}-\d{2}-\d{2}$');
    return pattern.hasMatch(str);
  }

  @override
  String? getAssetsPath(String localPath) {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }
    var fileName = FileUtils.getFileName(localPath);
    var remoteAssetPath = config.getRemoteAssetPath();
    return [remoteAssetPath, fileName].join('/');
  }

  @override
  String? getTempAssetsPath(String localPath) {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw Exception("未配置存储服务");
    }
    var fileName = FileUtils.getFileName(localPath);
    var remoteTempAssetsPath = config.getRemoteTempAssetPath();
    return [remoteTempAssetsPath, fileName].join('/');
  }
}
