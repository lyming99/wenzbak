import 'dart:convert';
import 'dart:typed_data';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/impl/file_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/s3_storage_client.dart';
import 'package:wenzbak/src/service/storage/impl/webdav_storage_client.dart';

import '../../models/index.dart';

/// 存储客户端，需要实现以下基础功能：
/// 1.上传文件
/// 2.下载文件
/// 3.删除文件
/// 4.创建文件夹
/// 5.删除文件夹
/// 6.查询文件列表
abstract class WenzbakStorageClientService {
  /// 每个客户端有一个持久化的客户端id，用uuid生成
  String? clientId;

  bool get isRangeSupport;

  Future<void> uploadFile(String path, String localFilepath);

  Future<void> downloadFile(String path, String localFilepath);

  Future<void> deleteFile(String path);

  Future<void> createFolder(String path);

  Future<void> deleteFolder(String path);

  Future<List<WenzbakStorageFile>> listFiles(String path);

  Future<Uint8List?> readFile(String path);

  Future<int> readFileSize(String path);

  Future<void> writeFile(String path, Uint8List data);

  Future<Uint8List> readRange(String path, int start, int length);

  Future<void> writeRange(String path, int start, Uint8List data);

  static WenzbakStorageClientService? getInstance(WenzbakConfig config) {
    var storageType = config.storageType?.toLowerCase();
    var storageConfig = config.storageConfig;

    if (storageType == null || storageConfig == null) {
      return null;
    }

    try {
      var configMap = jsonDecode(storageConfig) as Map<String, dynamic>;

      switch (storageType) {
        case 'file':
          var basePath = configMap['basePath'] as String?;
          if (basePath == null) {
            throw Exception('File storage requires "basePath" in storageConfig');
          }
          return FileStorageClient(config, basePath);

        case 'webdav':
          var url = configMap['url'] as String?;
          var username = configMap['username'] as String?;
          var password = configMap['password'] as String?;
          if (url == null) {
            throw Exception('WebDAV storage requires "url" in storageConfig');
          }
          return WebDAVStorageClient(config, url, username, password);

        case 's3':
          var endpoint = configMap['endpoint'] as String?;
          var accessKey = configMap['accessKey'] as String?;
          var secretKey = configMap['secretKey'] as String?;
          var bucket = configMap['bucket'] as String?;
          var region = configMap['region'] as String?;
          if (endpoint == null || accessKey == null || secretKey == null || bucket == null) {
            throw Exception('S3 storage requires "endpoint", "accessKey", "secretKey", and "bucket" in storageConfig');
          }
          return S3StorageClient(config, endpoint, accessKey, secretKey, bucket, region);

        default:
          throw Exception('Unsupported storage type: $storageType');
      }
    } catch (e) {
      throw Exception('Failed to create storage client: $e');
    }
  }
}
