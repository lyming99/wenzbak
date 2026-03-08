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
    await _minio.fGetObject(bucket, objectKey, localFilepath);
  }

  @override
  Future<void> deleteFile(String path) async {
    var objectKey = _getObjectKey(path);
    try {
      await _minio.removeObject(bucket, objectKey);
    } on MinioS3Error catch (e) {
      if (e.error?.code != 'NoSuchKey') {
        rethrow;
      }
      // 文件不存在，忽略错误
    }
  }

  @override
  Future<void> createFolder(String path) async {
    var objectKey = _getObjectKey(path);
    if (!objectKey.endsWith('/')) {
      objectKey = '$objectKey/';
    }
    // 在 S3/MinIO 中创建空对象表示文件夹
    await _minio.putObject(bucket, objectKey, Stream<Uint8List>.value(Uint8List(0)));
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
      if (e.error?.code != 'NoSuchKey') {
        rethrow;
      }
      // 文件夹不存在，忽略错误
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
    } on Exception {
      // 如果列表为空或出错，返回空列表
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
      rethrow;
    }
  }

  @override
  Future<int> readFileSize(String path) async {
    var objectKey = _getObjectKey(path);
    try {
      var stat = await _minio.statObject(bucket, objectKey);
      return stat.size ?? 0;
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.error?.code == 'NotFound') {
        return 0;
      }
      rethrow;
    }
  }

  @override
  Future<void> writeFile(String path, Uint8List data) async {
    var objectKey = _getObjectKey(path);
    await _minio.putObject(bucket, objectKey, Stream<Uint8List>.value(data));
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
}
