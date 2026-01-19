import 'package:wenzbak/src/utils/file_utils.dart';

/// 温知备份系统配置类
class WenzbakConfig {
  final String deviceId;
  final String? localRootPath;
  final String? remoteRootPath;
  final String? secretKey;
  final String? secret;
  final bool encryptFile;

  /// 存储类型: 'file', 'webdav', 's3'
  final String? storageType;

  /// 存储配置信息 (JSON 字符串)
  /// 对于 file: {"basePath": "/path/to/storage"}
  /// 对于 webdav: {"url": "https://example.com/webdav", "username": "user", "password": "pass"}
  /// 对于 s3: {"endpoint": "https://s3.amazonaws.com", "accessKey": "key", "secretKey": "secret", "bucket": "bucket-name", "region": "us-east-1"}
  final String? storageConfig;

  WenzbakConfig({
    required this.deviceId,
    required this.localRootPath,
    required this.remoteRootPath,
    this.secretKey,
    this.secret,
    this.encryptFile = false,
    this.storageType,
    this.storageConfig,
  });

  /// 获取当前小时备份目录
  String? getLocalCurrentPublicBlockHourBakPath() {
    if (localRootPath == null) {
      throw 'wenzbakRootPath is null';
    }
    var date = DateTime.now();
    var hour = date.hour;
    // yyyy-MM-dd
    var dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // [wenzbakRootPath]/public/data/[date]/[hour]/[txtUuid].txt
    return [
      localRootPath ?? 'wenzbak',
      'public',
      'data',
      dateStr,
      hour.toString(),
    ].join('/');
  }

  /// 获取文本缓存文件路径
  String? getLocalPublicBlockTextCachePath(String? txtUuid) {
    if (localRootPath == null) {
      throw 'wenzbakRootPath is null';
    }
    if (txtUuid == null) {
      return null;
    }
    var date = DateTime.now();
    var timeName = FileUtils.getTimeFilePath(date);
    return [
      localRootPath ?? 'wenzbak',
      'public',
      'data',
      "$timeName-$txtUuid.txt",
    ].join('/');
  }

  /// 获取文本缓存gzip文件路径
  String getLocalPublicBlockDir() {
    if (localRootPath == null) {
      throw 'wenzbakRootPath is null';
    }
    return [localRootPath ?? 'wenzbak', 'public', 'data'].join('/');
  }

  /// 获取文本缓存gzip文件路径
  String? getLocalPublicBlockPath(String? txtUuid) {
    if (localRootPath == null) {
      throw 'wenzbakRootPath is null';
    }
    if (txtUuid == null) {
      return null;
    }
    var date = DateTime.now();
    var timeName = FileUtils.getTimeFilePath(date);
    return [
      localRootPath ?? 'wenzbak',
      'public',
      'data',
      "$timeName-$txtUuid.gz",
    ].join('/');
  }

  String? getRemoteBlockHourPath(String? txtUuid) {
    if (remoteRootPath == null) {
      throw 'remoteRootPath is null';
    }
    if (txtUuid == null) {
      return null;
    }
    var date = DateTime.now();
    var hour = date.hour;
    // yyyy-MM-dd
    var dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // [wenzbakRootPath]/public/data/[date]/[hour]/[txtUuid].txt
    if (secretKey == null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'public',
        'data',
        dateStr,
        hour.toString(),
        "$txtUuid.gz",
      ].join('/');
    } else {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'data',
        dateStr,
        hour.toString(),
        "$txtUuid.gz",
      ].join('/');
    }
  }

  String? getLocalBlockHourDir(DateTime? dateTime) {
    if (localRootPath == null) {
      throw 'wenzbakRootPath is null';
    }
    dateTime ??= DateTime.now();
    var hour = dateTime.hour;
    // yyyy-MM-dd
    var dateStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    // [wenzbakRootPath]/public/data/[date]/[hour]/[txtUuid].txt
    if (secretKey == null) {
      return [
        localRootPath ?? 'wenzbak',
        'public',
        'data',
        dateStr,
        hour.toString(),
      ].join('/');
    } else {
      return [
        localRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'data',
        dateStr,
        hour.toString(),
      ].join('/');
    }
  }

  String? getRemoteBlockHourDir(DateTime? dateTime) {
    if (remoteRootPath == null) {
      throw 'remoteRootPath is null';
    }
    dateTime ??= DateTime.now();
    var hour = dateTime.hour;
    // yyyy-MM-dd
    var dateStr =
        '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    // [wenzbakRootPath]/public/data/[date]/[hour]/[txtUuid].txt
    if (secretKey == null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'public',
        'data',
        dateStr,
        hour.toString(),
      ].join('/');
    } else {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'data',
        dateStr,
        hour.toString(),
      ].join('/');
    }
  }

  String? getRemoteBlockSha256Path(String? txtUuid) {
    var remotePath = getRemoteBlockHourPath(txtUuid);
    if (remotePath == null) {
      return null;
    }
    return '$remotePath.sha256';
  }

  String getRemoteAssetPath() {
    if (encryptFile) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'assets',
      ].join('/');
    }
    return [remoteRootPath ?? 'wenzbak', 'public', 'assets'].join('/');
  }

  String getRemoteTempAssetPath() {
    if (encryptFile) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'tempAssets',
      ].join('/');
    }
    return [remoteRootPath ?? 'wenzbak', 'public', 'tempAssets'].join('/');
  }

  String getLocalSecretAssetPath() {
    return [
      remoteRootPath ?? 'wenzbak',
      'private',
      secretKey,
      'assets',
    ].join('/');
  }

  String getLocalAssetPath() {
    if (encryptFile) {
      return [
        localRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'assets',
      ].join('/');
    }
    return [localRootPath ?? 'wenzbak', 'public', 'assets'].join('/');
  }

  String getLocalBlockIndexPath() {
    if (encryptFile) {
      return [
        localRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'indexes',
        'data',
        deviceId,
      ].join('/');
    }
    return [
      localRootPath ?? 'wenzbak',
      'public',
      'indexes',
      'data',
      deviceId,
    ].join('/');
  }

  String getRemoteBlockIndexDir() {
    if (secretKey != null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'indexes',
        'data',
      ].join('/');
    }
    return [remoteRootPath ?? 'wenzbak', 'public', 'indexes', 'data'].join('/');
  }

  String getRemoteCurrentBlockIndexPath() {
    if (secretKey != null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'indexes',
        'data',
        deviceId,
      ].join('/');
    }
    return [
      remoteRootPath ?? 'wenzbak',
      'public',
      'indexes',
      'data',
      deviceId,
    ].join('/');
  }

  String getUploadKey() {
    return [localRootPath ?? 'wenzbak', secretKey ?? 'public'].join('-');
  }

  String getLocalBlockSaveDir() {
    return [localRootPath ?? 'wenzbak', 'public', 'download'].join('/');
  }

  String? getLocalFileSavePath(String filename) {
    var saveDir = getLocalAssetPath();
    var name = FileUtils.getFileName(filename);
    return [saveDir, name].join("/");
  }

  String getLocalMessageRootPath() {
    if (secretKey != null) {
      return [
        localRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'messages',
      ].join('/');
    }
    return [localRootPath ?? 'wenzbak', 'public', 'messages'].join('/');
  }

  String getLocalMessageCacheFile() {
    return [getLocalMessageRootPath(), 'cache.json'].join('/');
  }

  String getRemoteCurrentMessagePath() {
    var root = getRemoteMessageRootPath();
    return [root, deviceId].join('/');
  }

  String getRemoteMessageRootPath() {
    if (secretKey != null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'messages',
      ].join('/');
    }
    return [remoteRootPath ?? 'wenzbak', 'public', 'messages'].join('/');
  }

  String getLocalDeviceRootPath() {
    if (secretKey != null) {
      return [
        localRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'devices',
      ].join('/');
    }
    return [localRootPath ?? 'wenzbak', 'public', 'devices'].join('/');
  }

  String getLocalDeviceInfoCacheFile() {
    return [getLocalDeviceRootPath(), 'device_info.json'].join('/');
  }

  String getRemoteCurrentDevicePath() {
    var root = getRemoteDeviceRootPath();
    return [root, deviceId].join('/');
  }

  String getRemoteDeviceInfoPath(String deviceId) {
    var root = getRemoteDeviceRootPath();
    return [root, deviceId, 'device_info.json'].join('/');
  }

  String getRemoteDeviceRootPath() {
    if (secretKey != null) {
      return [
        remoteRootPath ?? 'wenzbak',
        'private',
        secretKey,
        'devices',
      ].join('/');
    }
    return [remoteRootPath ?? 'wenzbak', 'public', 'devices'].join('/');
  }
}
