import 'dart:typed_data';

import 'package:minio/io.dart';
import 'package:minio/minio.dart';
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/models/file.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:wenzbak/src/utils/storage_client_util.dart';

/// MinIO 存储客户端
/// 使用 minio: ^3.5.8 包实现
class MinioStorageClient extends WenzbakStorageClientService {
  final WenzbakConfig config;
  final Minio _minio;
  final String bucket;
  final Uuid _uuid = const Uuid();

  MinioStorageClient(
    this.config,
    String endpoint,
    String accessKey,
    String secretKey,
    this.bucket,
    String? region,
  ) : _minio = StorageClientUtil.createMinioClient(
          endpoint,
          accessKey,
          secretKey,
          bucket,
          region,
        ) {
    clientId = _uuid.v4();
  }

  @override
  bool get isRangeSupport => true;

  String _normalizePath(String path) {
    path = path.replaceAll('\\', '/');
    if (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }

  String _getObjectKey(String remotePath) {
    return _normalizePath(remotePath);
  }

  @override
  Future<void> uploadFile(String path, String localFilepath) async {
    var objectKey = _getObjectKey(path);
    await _minio.fPutObject(bucket, objectKey, localFilepath);
  }

  @override
  Future<void> downloadFile(String path, String localFilepath) async {
    var objectKey = _getObjectKey(path);
    await FileUtils.createParentDir(localFilepath);
    try {
      await _minio.fGetObject(bucket, objectKey, localFilepath);
    } on MinioS3Error catch (e) {
      if (_isNotImplementedError(e)) {
        throw Exception('当前存储服务不支持此操作(下载文件): ${e.message}');
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    var objectKey = _getObjectKey(path);
    try {
      await _minio.removeObject(bucket, objectKey);
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey') {
        // 文件不存在，忽略错误
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> createFolder(String path) async {
    var objectKey = _getObjectKey(path);
    if (!objectKey.endsWith('/')) {
      objectKey = '$objectKey/';
    }
    // 在 S3/MinIO 中创建空对象表示文件夹
    try {
      await _minio.putObject(bucket, objectKey, Stream<Uint8List>.value(Uint8List(0)));
    } on MinioS3Error catch (e) {
      if (_isNotImplementedError(e)) {
        // 不支持创建文件夹操作，忽略（S3 本身无文件夹概念）
        return;
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteFolder(String path) async {
    var files = await listFiles(path);
    for (var file in files) {
      if (file.path != null) {
        await deleteFile(file.path!);
      }
    }
    var objectKey = _getObjectKey(path);
    if (!objectKey.endsWith('/')) {
      objectKey = '$objectKey/';
    }
    try {
      await _minio.removeObject(bucket, objectKey);
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey') {
        // 文件夹不存在，忽略错误
        return;
      }
      rethrow;
    }
  }

  @override
  Future<List<WenzbakStorageFile>> listFiles(String path) async {
    var prefix = _getObjectKey(path);
    if (!prefix.endsWith('/') && prefix.isNotEmpty) {
      prefix = '$prefix/';
    }

    var files = <WenzbakStorageFile>[];

    try {
      await for (var chunk in _minio.listObjects(bucket, prefix: prefix, recursive: false)) {
        for (var obj in chunk.objects) {
          var key = obj.key;
          if (key == null) continue;
          if (key == prefix || key == path) {
            continue;
          }

          // 移除前缀，获取相对路径
          var relativePath = key.startsWith(prefix) ? key.substring(prefix.length) : key;

          // 如果是目录（以 / 结尾），或者在当前层级下还有 /
          var isDir = key.endsWith('/') || relativePath.contains('/');

          files.add(WenzbakStorageFile(
            path: key,
            isDir: isDir,
          ));
        }
      }
    } on MinioS3Error catch (e) {
      // 如果是不支持的 API 错误，尝试使用 listObjectsV2 降级
      if (_isNotImplementedError(e)) {
        return await _listFilesFallbackV2(prefix);
      }
      rethrow;
    }

    return files;
  }

  /// 使用 listObjectsV2 的降级列表方法
  /// 某些 S3 兼容服务对 listObjects V1 支持不完整，但 V2 可用
  Future<List<WenzbakStorageFile>> _listFilesFallbackV2(String prefix) async {
    var files = <WenzbakStorageFile>[];
    try {
      await for (var chunk in _minio.listObjectsV2(bucket, prefix: prefix, recursive: false)) {
        for (var obj in chunk.objects) {
          var key = obj.key;
          if (key == null) continue;
          if (key == prefix) continue;

          var relativePath = key.startsWith(prefix) ? key.substring(prefix.length) : key;
          var isDir = key.endsWith('/') || relativePath.contains('/');

          files.add(WenzbakStorageFile(
            path: key,
            isDir: isDir,
          ));
        }
      }
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        return [];
      }
      rethrow;
    } on Exception {
      // V2 也失败，返回空列表
    }
    return files;
  }

  @override
  Future<Uint8List?> readFile(String path) async {
    var objectKey = _getObjectKey(path);
    try {
      var stream = await _minio.getObject(bucket, objectKey);
      var builder = BytesBuilder();
      await for (var chunk in stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        return null;
      }
      if (_isNotImplementedError(e)) {
        // 不支持 getObject，尝试使用 getPartialObject 降级读取
        return await _readFileFallback(objectKey);
      }
      rethrow;
    }
  }

  /// 使用 getPartialObject 的降级读取方法
  /// 某些 S3 兼容服务不支持 getObject，但支持 getPartialObject（范围请求）
  Future<Uint8List?> _readFileFallback(String objectKey) async {
    try {
      // 先获取文件大小
      var stat = await _minio.statObject(bucket, objectKey, retrieveAcls: false);
      var size = stat.size ?? 0;
      if (size == 0) return Uint8List(0);
      // 使用范围请求读取全部内容
      var stream = await _minio.getPartialObject(bucket, objectKey, 0, size);
      var builder = BytesBuilder();
      await for (var chunk in stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<int> readFileSize(String path) async {
    var objectKey = _getObjectKey(path);
    try {
      var stat = await _minio.statObject(bucket, objectKey, retrieveAcls: false);
      return stat.size ?? 0;
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        return 0;
      }
      if (_isNotImplementedError(e)) {
        // 不支持 statObject，尝试通过读取文件来获取大小
        var data = await readFile(path);
        return data?.length ?? 0;
      }
      rethrow;
    }
  }

  @override
  Future<void> writeFile(String path, Uint8List data) async {
    var objectKey = _getObjectKey(path);
    try {
      await _minio.putObject(bucket, objectKey, Stream<Uint8List>.value(data));
    } on MinioS3Error catch (e) {
      if (_isNotImplementedError(e)) {
        throw Exception('当前存储服务不支持此操作(写入文件): ${e.message}');
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> readRange(String path, int start, int length) async {
    var objectKey = _getObjectKey(path);
    try {
      var stream = await _minio.getPartialObject(bucket, objectKey, start, length);
      var builder = BytesBuilder();
      await for (var chunk in stream) {
        builder.add(chunk);
      }
      var bytes = builder.takeBytes();
      if (bytes.length > length) {
        return bytes.sublist(0, length);
      }
      return bytes;
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        throw Exception('文件不存在: $path');
      }
      if (_isNotImplementedError(e)) {
        // 不支持范围请求，降级为读取完整文件后截取
        var fullData = await readFile(path);
        if (fullData == null) {
          throw Exception('文件不存在: $path');
        }
        if (start >= fullData.length) {
          return Uint8List(0);
        }
        var end = start + length;
        if (end > fullData.length) {
          end = fullData.length;
        }
        return Uint8List.fromList(fullData.sublist(start, end));
      }
      rethrow;
    }
  }

  @override
  Future<void> writeRange(String path, int start, Uint8List data) async {
    var existingData = await readFile(path) ?? Uint8List(0);

    if (existingData.length < start) {
      var padding = Uint8List(start - existingData.length);
      existingData = Uint8List.fromList([...existingData, ...padding]);
    }

    var newData = Uint8List.fromList([
      ...existingData.sublist(0, start),
      ...data,
      if (start + data.length < existingData.length)
        ...existingData.sublist(start + data.length),
    ]);

    await writeFile(path, newData);
  }

  /// 判断是否为 S3 "NotImplemented" 错误
  /// 某些 S3 兼容服务不支持完整的 S3 API（如 GetObjectAcl），
  /// 会返回 code=NotImplemented 或在 message 中包含 "not implemented"
  static bool _isNotImplementedError(MinioS3Error e) {
    final code = e.error?.code;
    final message = e.error?.message ?? e.message ?? '';
    return code == 'NotImplemented' ||
        code == 'NotImplementedException' ||
        message.toLowerCase().contains('not implemented');
  }
}
