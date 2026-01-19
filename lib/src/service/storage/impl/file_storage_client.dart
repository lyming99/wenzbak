import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/file.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';

/// 本地文件系统存储客户端
class FileStorageClient extends WenzbakStorageClientService {
  final WenzbakConfig config;
  final String basePath;
  final Uuid _uuid = const Uuid();

  FileStorageClient(this.config, this.basePath) {
    clientId = _uuid.v4();
  }

  @override
  bool get isRangeSupport => true;

  String _getFullPath(String remotePath) {
    // 如果 remotePath 是绝对路径，直接使用
    // 否则基于 basePath 和 remoteRootPath 构建完整路径
    if (path.isAbsolute(remotePath)) {
      return remotePath;
    }
    var fullPath = path.join(basePath, remotePath);
    return path.normalize(fullPath);
  }

  @override
  Future<void> uploadFile(String path, String localFilepath) async {
    var fullPath = _getFullPath(path);
    await FileUtils.createParentDir(fullPath);
    await File(localFilepath).copy(fullPath);
  }

  @override
  Future<void> downloadFile(String path, String localFilepath) async {
    var fullPath = _getFullPath(path);
    await FileUtils.createParentDir(localFilepath);
    await File(fullPath).copy(localFilepath);
  }

  @override
  Future<void> deleteFile(String path) async {
    var fullPath = _getFullPath(path);
    var file = File(fullPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> createFolder(String path) async {
    var fullPath = _getFullPath(path);
    var dir = Directory(fullPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  @override
  Future<void> deleteFolder(String path) async {
    var fullPath = _getFullPath(path);
    var dir = Directory(fullPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  @override
  Future<List<WenzbakStorageFile>> listFiles(String path) async {
    var fullPath = _getFullPath(path);
    var dir = Directory(fullPath);
    if (!await dir.exists()) {
      return [];
    }

    var files = <WenzbakStorageFile>[];
    await for (var entity in dir.list()) {
      var entityPath = entity.path.replaceAll('\\', '/');
      var base = basePath.replaceAll('\\', '/');
      var relativePath = entityPath;
      if (entityPath.startsWith(base)) {
        relativePath = entityPath.substring(base.length);
        if (relativePath.startsWith('/')) {
          relativePath = relativePath.substring(1);
        }
      }
      files.add(WenzbakStorageFile(
        path: relativePath,
        isDir: entity is Directory,
      ));
    }
    return files;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    var fullPath = _getFullPath(path);
    var file = File(fullPath);
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  }

  @override
  Future<int> readFileSize(String path) async {
    var fullPath = _getFullPath(path);
    var file = File(fullPath);
    if (!await file.exists()) {
      return 0;
    }
    return await file.length();
  }

  @override
  Future<void> writeFile(String path, Uint8List data) async {
    var fullPath = _getFullPath(path);
    await FileUtils.createParentDir(fullPath);
    await File(fullPath).writeAsBytes(data);
  }

  @override
  Future<Uint8List> readRange(String path, int start, int length) async {
    var fullPath = _getFullPath(path);
    var file = File(fullPath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', fullPath);
    }

    var raf = await file.open();
    try {
      await raf.setPosition(start);
      var buffer = Uint8List(length);
      var bytesRead = await raf.readInto(buffer);
      if (bytesRead < length) {
        return buffer.sublist(0, bytesRead);
      }
      return buffer;
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> writeRange(String path, int start, Uint8List data) async {
    var fullPath = _getFullPath(path);
    await FileUtils.createParentDir(fullPath);
    
    var file = File(fullPath);
    var raf = await file.open(mode: FileMode.writeOnlyAppend);
    try {
      // 如果文件不存在或大小小于 start，需要先扩展文件
      var currentSize = await file.length();
      if (currentSize < start) {
        // 填充空白数据
        var padding = Uint8List(start - currentSize);
        await raf.writeFrom(padding);
      } else {
        await raf.setPosition(start);
      }
      await raf.writeFrom(data);
    } finally {
      await raf.close();
    }
  }
}
