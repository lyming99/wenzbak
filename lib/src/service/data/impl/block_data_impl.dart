import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';
import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/index/indexes.dart';
import 'package:wenzbak/src/utils/file_line_reader_util.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:wenzbak/src/utils/index_util.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';
import 'package:wenzbak/wenzbak.dart';

import '../block_file_upload_cache.dart';
import 'block_file_upload_cache_impl.dart';

/// 文件路径解析结果
class _PathParseResult {
  final DateTime dateTime;
  final bool isHourly; // true: 按小时存储, false: 按天存储

  _PathParseResult(this.dateTime, this.isHourly);
}

/// 数据块管理器实现
class WenzbakBlockDataServiceImpl implements WenzbakBlockDataService {
  final WenzbakConfig config;

  /// 操作锁
  final Lock _fileLock = Lock();

  late final WenzbakBlockFileUploadCache _blockFileUploadCache =
      WenzbakBlockFileUploadCacheImpl(config);

  /// 构造函数
  /// [config] 配置对象，包含数据库路径等信息
  /// [serverId] 服务器ID，如果为 null 则查询所有服务器的数据块
  WenzbakBlockDataServiceImpl(this.config);

  final Map<String, String> _localSha256Cache = {};

  @override
  Future<void> addBackupData(WenzbakDataLine line) async {
    var data = line.content;
    if (data == null) {
      return Future.error("数据为空");
    }
    var txtPath = await _blockFileUploadCache.getCurrentCacheFile(
      line.createTime,
    );
    if (txtPath == null) {
      return Future.error("未指定缓存文件");
    }
    await _fileLock.synchronized(() async {
      await FileUtils.appendLine(txtPath, data);
    });
  }

  @override
  Future<void> addBackupDataList(List<WenzbakDataLine> lines) async {
    if (lines.isEmpty) {
      return;
    }
    var lineMap = <String, List<String>>{};
    for (var line in lines) {
      var lineData = line.content;
      if (lineData == null) {
        continue;
      }
      var txtPath = await _blockFileUploadCache.getCurrentCacheFile(
        line.createTime,
      );
      if (txtPath == null) {
        continue;
      }
      lineMap.putIfAbsent(txtPath, () => []).add(lineData);
    }
    for (var entry in lineMap.entries) {
      var txtPath = entry.key;
      var values = entry.value;
      await _fileLock.synchronized(() async {
        await FileUtils.appendLine(txtPath, values.join("\n"));
      });
    }
  }

  /// 上传block数据
  /// 1. 用block_file_cache读取需要上传的列表
  /// 2. 计算remote path：block path + deviceId + local file name
  /// 3. 通过storage上传内容，注意如果需要数据加密，则先进行加密
  /// 4. 计算文件sha256，并且上传
  /// 5. 通过index_service更新并且上传文件索引
  @override
  Future<void> uploadBlockData(bool oneHoursAgo) async {
    // 1. 用block_file_cache读取需要上传的列表
    var uploadFiles = await _blockFileUploadCache.getUploadFiles(oneHoursAgo);
    if (uploadFiles.isEmpty) {
      return;
    }

    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "storage is null";
    }

    // 获取索引服务
    var indexesService = WenzbakBlockIndexesService.getInstance(config);

    // 处理每个需要上传的文件
    for (var localFilePath in uploadFiles) {
      try {
        await _uploadSingleBlockFile(localFilePath, storage, indexesService);
        // 上传成功后，从缓存中移除文件
        await _blockFileUploadCache.removeFile(localFilePath);
      } catch (e) {
        print('上传block文件失败: $localFilePath, 错误: $e');
        // 继续处理下一个文件，不中断整个上传流程
      }
    }
  }

  /// 上传单个block文件
  Future<void> _uploadSingleBlockFile(
    String localFilePath,
    WenzbakStorageClientService storage,
    WenzbakBlockIndexesService indexesService,
  ) async {
    // 检查本地文件是否存在
    var localFile = File(localFilePath);
    if (!await localFile.exists()) {
      return;
    }

    // 2. 计算remote path：block path + deviceId + local file name
    // 从本地文件路径解析日期时间信息
    // 本地文件路径格式：.../data/[dateStr]-[uuid].txt
    // dateStr格式：yyyy-MM-dd-HH
    var fileName = FileUtils.getFileName(localFilePath);
    var dateTime = _parseDateTimeFromFileName(fileName);
    if (dateTime == null) {
      throw "无法从文件名解析日期时间: $fileName";
    }

    // 获取block path（按小时存储的目录）
    var blockPath = config.getRemoteBlockHourDir(dateTime);
    if (blockPath == null) {
      throw "无法获取remote block path";
    }

    // 从文件名中提取uuid（去掉时间前缀和.txt扩展名）
    var uuid = _extractUuidFromFileName(fileName);
    if (uuid == null) {
      throw "无法从文件名提取uuid: $fileName";
    }
    var remoteFileName = "$uuid.gz";

    // 构建remote path：block path + uuid.gz
    var remotePath = [blockPath, remoteFileName].join('/');

    // 3. 通过storage上传内容，注意如果需要数据加密，则先进行加密
    String? gzipFilePath;
    String? encryptedFilePath;
    String fileToHash;

    try {
      // 先gzip压缩
      gzipFilePath = await _getLocalTempGzipPath(Uuid().v4());
      await GZipUtil.compressFile(localFilePath, gzipFilePath);

      // 如果需要加密，则加密
      bool isEncrypted = config.secretKey != null && config.secret != null;
      if (isEncrypted) {
        encryptedFilePath = await _getLocalTempEncryptedPath(Uuid().v4());
        var cryptUtil = WenzbakCryptUtil(
          config.secretKey ?? "",
          config.secret ?? "",
        );
        await cryptUtil.encryptFile(gzipFilePath, encryptedFilePath);
        fileToHash = encryptedFilePath;
      } else {
        fileToHash = gzipFilePath;
      }

      // 4. 计算文件sha256
      var sha256 = await Sha256Util.sha256File(fileToHash);

      // 如果sha256不一致，则上传文件
      // 上传文件
      if (isEncrypted && encryptedFilePath != null) {
        await storage.uploadFile(remotePath, encryptedFilePath);
      } else {
        await storage.uploadFile(remotePath, gzipFilePath);
      }

      // 上传sha256文件
      await storage.writeFile("$remotePath.sha256", utf8.encode(sha256));

      // 5. 通过index_service更新并且上传文件索引
      indexesService.addIndex(remotePath, sha256);
      await indexesService.writeIndexes();
      await indexesService.uploadIndexes();
    } finally {
      // 清理临时文件
      if (gzipFilePath != null && await File(gzipFilePath).exists()) {
        try {
          await File(gzipFilePath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      if (encryptedFilePath != null && await File(encryptedFilePath).exists()) {
        try {
          await File(encryptedFilePath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
    }
  }

  /// 从文件名解析日期时间
  /// 文件名格式：yyyy-MM-dd-HH-[uuid].txt
  DateTime? _parseDateTimeFromFileName(String fileName) {
    try {
      // 去掉.txt扩展名
      var baseName = fileName;
      if (baseName.endsWith('.txt')) {
        baseName = baseName.substring(0, baseName.length - 4);
      }

      // 日期时间部分固定格式：yyyy-MM-dd-HH（4个部分，3个'-'分隔）
      // 找到第4个'-'的位置，之前的部分是日期时间
      var dashCount = 0;
      var dateTimeEndIndex = -1;
      for (var i = 0; i < baseName.length; i++) {
        if (baseName[i] == '-') {
          dashCount++;
          if (dashCount == 4) {
            dateTimeEndIndex = i;
            break;
          }
        }
      }

      if (dateTimeEndIndex == -1) {
        return null;
      }

      var dateTimeStr = baseName.substring(0, dateTimeEndIndex);
      // dateTimeStr格式：yyyy-MM-dd-HH
      var parts = dateTimeStr.split('-');
      if (parts.length != 4) {
        return null;
      }

      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      var hour = int.parse(parts[3]);

      return DateTime(year, month, day, hour);
    } catch (e) {
      return null;
    }
  }

  /// 从文件名提取uuid
  /// 文件名格式：yyyy-MM-dd-HH-[uuid].txt
  String? _extractUuidFromFileName(String fileName) {
    try {
      // 去掉.txt扩展名
      var baseName = fileName;
      if (baseName.endsWith('.txt')) {
        baseName = baseName.substring(0, baseName.length - 4);
      }

      // 日期时间部分固定格式：yyyy-MM-dd-HH（4个部分，3个'-'分隔）
      // 找到第4个'-'的位置，之后的部分是uuid
      var dashCount = 0;
      var uuidStartIndex = -1;
      for (var i = 0; i < baseName.length; i++) {
        if (baseName[i] == '-') {
          dashCount++;
          if (dashCount == 4) {
            uuidStartIndex = i + 1; // uuid从第4个'-'之后开始
            break;
          }
        }
      }

      if (uuidStartIndex == -1 || uuidStartIndex >= baseName.length) {
        return null;
      }

      return baseName.substring(uuidStartIndex);
    } catch (e) {
      return null;
    }
  }

  /// 获取本地临时gzip文件路径
  Future<String> _getLocalTempGzipPath(String uuid) async {
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    return [saveDir, "$uuid.gz"].join("/");
  }

  Future<void> downloadBlockFile(
    DateTime? dateTime,
    WenzbakStorageBlockFile? blockFile,
    Set<WenzbakDataReceiver> dataReceivers,
  ) async {
    if (blockFile == null) {
      return;
    }
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      return;
    }
    // 1.读取服务端的sha256值
    var remoteSha256Bytes = await storage.readFile(blockFile.sha256Path);
    if (remoteSha256Bytes == null) {
      return;
    }
    var remoteSha256 = utf8.decode(remoteSha256Bytes);
    // 2.获取本地sha256文件路径，并且读取sha256值
    var localDir = config.getLocalBlockHourDir(dateTime);
    if (localDir == null) {
      return;
    }
    if (!await Directory(localDir).exists()) {
      await Directory(localDir).create(recursive: true);
    }
    String? localSha256;
    var localSha256File = [localDir, blockFile.uuid, ".gz.sha256"].join("/");
    if (await File(localSha256File).exists()) {
      localSha256 = await File(localSha256File).readAsString();
    }
    var localFile = [localDir, blockFile.uuid, ".gz"].join("/");
    // 3.比较sha256值，如果存在差异，则下载文件
    if (localSha256 != remoteSha256) {
      await storage.downloadFile(blockFile.gzipPath, localFile);
      // 4.写入sha256文件
      await File(localSha256File).writeAsString(remoteSha256);
    }
    // 5.读取数据块文件
    bool isEncrypted = config.secretKey != null && config.secret != null;
    Uint8List data;
    if (isEncrypted) {
      WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
        config.secretKey ?? "",
        config.secret ?? "",
      );
      data = cryptUtil.decrypt(await File(localFile).readAsBytes());
    } else {
      data = await File(localFile).readAsBytes();
    }
    // 6.发送数据
    var lineBytes = GZipUtil.decompressBytes(data);
    var lineString = utf8.decode(lineBytes);
    var lines = lineString.split("\n");
    var lineCache = <WenzbakDataLine>[];
    for (var line in lines) {
      lineCache.add(WenzbakDataLine(content: line));
      if (lineCache.length >= 1000) {
        for (var receiver in dataReceivers) {
          receiver.onReceive(lineCache);
        }
        lineCache.clear();
      }
    }
    if (lineCache.isNotEmpty) {
      for (var receiver in dataReceivers) {
        receiver.onReceive(lineCache);
      }
      lineCache.clear();
    }
  }

  /// 下载数据块文件：本客户端的数据无需下载，其它客户端的数据通过sha256进行校验下载
  @override
  Future<void> downloadData(
    String remotePath,
    String? sha256,
    Set<WenzbakDataReceiver> dataReceivers,
  ) async {
    var localSha256 = await readLocalSha256(remotePath);
    if (sha256 != null && localSha256 == sha256) {
      // 对应的文件sha256已经下载，无需再次下载
      return;
    }
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "storage is null";
    }
    // 读取remote sha256
    var remoteSha256Bytes = await storage.readFile("$remotePath.sha256");
    if (remoteSha256Bytes == null) {
      throw "remote sha256 is null";
    }
    var remoteSha256 = utf8.decode(remoteSha256Bytes);
    if (sha256 != null) {
      if (remoteSha256 != sha256) {
        // 通过索引下载文件时，发现索引的hash和服务器的不一致，返回下载失败异常
        // 解决方案：重新查询文件索引，重新下载数据
        throw "remote sha256 is error";
      }
    }
    if (localSha256 == remoteSha256) {
      // 和本地索引一致，无需下载数据
      return;
    }
    // 1.下载数据
    var filename = FileUtils.encodePath(remotePath);
    var saveDir = config.getLocalBlockSaveDir();
    var localPath = [saveDir, filename].join("/");
    await storage.downloadFile(remotePath, localPath);
    // 2.校验数据
    var checkSha256 = await Sha256Util.sha256File(localPath);
    if (remoteSha256 != checkSha256) {
      throw "remote sha256 is error";
    }
    // 4.解密数据
    bool isEncrypted = config.secretKey != null && config.secret != null;
    var fileToRead = localPath;
    var decryptFile = "$localPath.dec";
    var txtFile = "$localPath.txt";
    try {
      if (isEncrypted) {
        WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
          config.secretKey ?? "",
          config.secret ?? "",
        );
        await cryptUtil.decryptFile(localPath, decryptFile);
        fileToRead = decryptFile;
      }
      // 5.解压数据
      await GZipUtil.decompressFile(fileToRead, txtFile);
      // 6.发送数据给客户端处理
      var lineCache = <WenzbakDataLine>[];
      await FileLineReaderUtil.readLinesSimple(
        txtFile,
        onLine: (line) async {
          lineCache.add(WenzbakDataLine(content: line));
          if (lineCache.length >= 1000) {
            for (var receiver in dataReceivers) {
              await receiver.onReceive(lineCache);
            }
            lineCache.clear();
          }
        },
      );
      if (lineCache.isNotEmpty) {
        for (var receiver in dataReceivers) {
          await receiver.onReceive(lineCache);
        }
        lineCache.clear();
      }
      // 7.保存sha256到本地
      await writeLocalSha256(remotePath, remoteSha256);
    } finally {
      await FileUtils.deleteFile(decryptFile);
      await FileUtils.deleteFile(txtFile);
    }
  }

  Future<String?> readLocalSha256(String remotePath) async {
    var filename = FileUtils.encodePath(remotePath);
    if (_localSha256Cache[filename] != null) {
      return _localSha256Cache[filename];
    }
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    // 读取本地sha256文件
    var localSha256File = [saveDir, "$filename.sha256"].join("/");
    if (await File(localSha256File).exists()) {
      var ret = await File(localSha256File).readAsString();
      _localSha256Cache[filename] = ret;
      return ret;
    }
    return null;
  }

  Future writeLocalSha256(String remotePath, String sha256) async {
    var filename = FileUtils.encodePath(remotePath);
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    var localSha256File = [saveDir, "$filename.sha256"].join("/");
    await File(localSha256File).writeAsString(sha256);
    _localSha256Cache[filename] = sha256;
  }

  @override
  Future<void> downloadAllData(Set<WenzbakDataReceiver> dataReceivers) async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "storage is null";
    }
    // 1.读取索引列表
    var remoteBlockIndexPath = config.getRemoteBlockIndexDir();
    var indexList = await storage.listFiles(remoteBlockIndexPath);
    for (var indexFile in indexList) {
      if (indexFile.isDir != true) {
        var indexFilePath = indexFile.path;
        if (indexFilePath == null) {
          continue;
        }
        var bytes = await storage.readFile(indexFilePath);
        if (bytes == null) {
          continue;
        }
        var indexBytes = GZipUtil.decompressBytes(bytes);
        var indexString = utf8.decode(indexBytes);
        var indexMap = IndexUtil.readIndexMap(indexString);
        // 2.根据索引下载数据
        for (var index in indexMap.entries) {
          // path
          var key = index.key;
          // sha256
          var value = index.value;
          await downloadData(key, value, dataReceivers);
        }
      }
    }
  }

  @override
  Future<void> mergeBlockData() async {
    // 1. 读取索引文件
    var indexesService = WenzbakBlockIndexesService.getInstance(config);
    await indexesService.readIndexes();
    var indexes = await indexesService.getIndexes();
    if (indexes.isEmpty) {
      return;
    }

    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      throw "未配置存储服务";
    }

    var now = DateTime.now();
    // 只取日期部分，时间设为 00:00:00
    var today = DateTime(now.year, now.month, now.day);
    var currentYear = today.year;
    // 2. 解析文件路径，提取日期和时间
    // 按小时存储的文件，合并到按天存储
    Map<String, List<MapEntry<String, String>>> hourToDayGroups = {};
    // 按天存储的文件，合并到按年存储
    Map<int, List<MapEntry<String, String>>> dayToYearGroups = {};

    for (var entry in indexes.entries) {
      var filepath = entry.key;
      // 解析路径：.../data/YYYY-MM-DD/HH/uuid.gz 或者 .../data/YYYY-MM-DD/uuid.gz
      var parseResult = _parseDateTimeFromPath(filepath);
      if (parseResult == null) {
        continue;
      }

      var dateTime = parseResult.dateTime;
      var isHourly = parseResult.isHourly;
      // 只取日期部分，时间设为 00:00:00
      var fileDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

      if (isHourly) {
        if (fileDate.isBefore(today)) {
          var dateKey = FileUtils.getDateFilePath(fileDate);
          hourToDayGroups.putIfAbsent(dateKey, () => []).add(entry);
        }
      } else {
        if (fileDate.year < currentYear) {
          var year = fileDate.year;
          dayToYearGroups.putIfAbsent(year, () => []).add(entry);
        }
      }
    }

    // 3. 按小时存储的文件合并到按天存储
    for (var dayEntry in hourToDayGroups.entries) {
      var dateKey = dayEntry.key; // YYYY-MM-DD
      var files = dayEntry.value;

      if (files.isEmpty) {
        continue;
      }

      await _mergeDayFiles(dateKey, files, storage, indexesService);
    }

    // 4. 按天存储的文件合并到按年存储
    for (var yearEntry in dayToYearGroups.entries) {
      var year = yearEntry.key;
      var files = yearEntry.value;

      if (files.isEmpty) {
        continue;
      }

      await _mergeYearFiles(year, files, storage, indexesService);
    }
  }

  /// 日期格式正则：YYYY-MM-DD
  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// 小时格式正则：HH (0-23)
  static final RegExp _hourPattern = RegExp(r'^\d{1,2}$');

  /// 从文件路径中提取 /data/ 后面的部分
  String? _extractDataPath(String filepath) {
    var dataIndex = filepath.lastIndexOf('/data/');
    if (dataIndex == -1) {
      return null;
    }
    return filepath.substring(dataIndex + 6); // 跳过 '/data/'
  }

  /// 判断字符串是否符合日期格式 YYYY-MM-DD
  bool _isDateFormat(String str) {
    if (!_datePattern.hasMatch(str)) {
      return false;
    }
    // 进一步验证日期有效性
    var parts = str.split('-');
    if (parts.length != 3) {
      return false;
    }
    try {
      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      // 验证日期范围
      if (year < 1900 || year > 3100) return false;
      if (month < 1 || month > 12) return false;
      if (day < 1 || day > 31) return false;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 判断字符串是否符合小时格式 HH (0-23)
  bool _isHourFormat(String str) {
    if (!_hourPattern.hasMatch(str)) {
      return false;
    }
    try {
      var hour = int.parse(str);
      return hour >= 0 && hour <= 23;
    } catch (e) {
      return false;
    }
  }

  /// 解析日期字符串为 DateTime（只包含日期，不包含时间）
  DateTime? _parseDate(String dateStr) {
    if (!_isDateFormat(dateStr)) {
      return null;
    }
    try {
      var parts = dateStr.split('-');
      var year = int.parse(parts[0]);
      var month = int.parse(parts[1]);
      var day = int.parse(parts[2]);
      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// 解析按小时存储的路径格式：.../data/YYYY-MM-DD/HH/uuid.gz
  _PathParseResult? _parseHourlyPath(String afterData) {
    var parts = afterData.split('/');
    if (parts.length < 2) {
      return null;
    }

    var dateStr = parts[0];
    var hourStr = parts[1];

    // 验证日期格式
    if (!_isDateFormat(dateStr)) {
      return null;
    }

    // 验证小时格式
    if (!_isHourFormat(hourStr)) {
      return null;
    }

    try {
      var date = _parseDate(dateStr);
      if (date == null) {
        return null;
      }
      var hour = int.parse(hourStr);
      return _PathParseResult(
        DateTime(date.year, date.month, date.day, hour),
        true,
      );
    } catch (e) {
      return null;
    }
  }

  /// 解析按天存储的路径格式：.../data/YYYY-MM-DD/uuid.gz
  _PathParseResult? _parseDailyPath(String afterData) {
    var parts = afterData.split('/');
    if (parts.isEmpty) {
      return null;
    }

    var dateStr = parts[0];

    // 验证日期格式
    if (!_isDateFormat(dateStr)) {
      return null;
    }

    try {
      var date = _parseDate(dateStr);
      if (date == null) {
        return null;
      }
      return _PathParseResult(date, false);
    } catch (e) {
      return null;
    }
  }

  /// 从文件路径中解析日期和时间
  /// 支持两种格式：
  /// 1. 按小时存储：.../data/YYYY-MM-DD/HH/uuid.gz
  /// 2. 按天存储：.../data/YYYY-MM-DD/uuid.gz
  _PathParseResult? _parseDateTimeFromPath(String filepath) {
    try {
      // 提取 /data/ 后面的部分
      var afterData = _extractDataPath(filepath);
      if (afterData == null) {
        return null;
      }

      // 先尝试解析按小时存储的格式
      var hourlyResult = _parseHourlyPath(afterData);
      if (hourlyResult != null) {
        return hourlyResult;
      }

      // 如果不是按小时存储，尝试解析按天存储的格式
      var dailyResult = _parseDailyPath(afterData);
      if (dailyResult != null) {
        return dailyResult;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// 合并一天的文件
  Future<void> _mergeDayFiles(
    String dateKey, // YYYY-MM-DD
    List<MapEntry<String, String>> files,
    WenzbakStorageClientService storage,
    WenzbakBlockIndexesService indexesService,
  ) async {
    bool isEncrypted = config.secretKey != null && config.secret != null;
    String? mergedTextPath;
    String? mergedGzipPath;
    String? mergedEncryptedPath;
    List<String> tempFiles = [];
    List<String> filepathsToRemove = [];

    try {
      // 创建合并文本文件
      var newUuid = Uuid().v4();
      mergedTextPath = await _getLocalTempTextPath(newUuid);
      mergedGzipPath = await _getLocalTempPath(newUuid);
      if (isEncrypted) {
        mergedEncryptedPath = await _getLocalTempEncryptedPath(newUuid);
      }

      // 下载所有文件并解压，通过数据流追加到合并文件
      bool hasData = false;
      for (var entry in files) {
        var remotePath = entry.key;
        var localPath = await _downloadFileForMerge(remotePath, storage);
        if (localPath == null) {
          continue;
        }

        String? decryptedPath;
        String? decompressedPath;

        try {
          // 如果是加密的，先解密
          if (isEncrypted) {
            decryptedPath = await _getLocalTempDecryptedPath(Uuid().v4());
            tempFiles.add(decryptedPath);
            WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
              config.secretKey ?? "",
              config.secret ?? "",
            );
            await cryptUtil.decryptFile(localPath, decryptedPath);
            localPath = decryptedPath;
          }

          // 解压 gzip 到临时文本文件
          decompressedPath = await _getLocalTempTextPath(Uuid().v4());
          tempFiles.add(decompressedPath);
          await GZipUtil.decompressFile(localPath, decompressedPath);

          // 检查文件是否有内容
          var fileLength = await File(decompressedPath).length();
          if (fileLength > 0) {
            // 如果不是第一个文件，先追加换行符
            if (await File(mergedTextPath).exists()) {
              await FileUtils.appendString(mergedTextPath, '\n');
            }
            // 追加文件内容
            await FileUtils.appendFile(mergedTextPath, decompressedPath);
            hasData = true;
          }

          filepathsToRemove.add(remotePath);
        } finally {
          // 清理临时文件
          if (decryptedPath != null && await File(decryptedPath).exists()) {
            try {
              await File(decryptedPath).delete();
            } catch (e) {
              // 忽略删除失败
            }
          }
          if (decompressedPath != null &&
              await File(decompressedPath).exists()) {
            try {
              await File(decompressedPath).delete();
            } catch (e) {
              // 忽略删除失败
            }
          }
        }
      }

      if (!hasData) {
        return;
      }

      // 压缩合并后的文本文件
      await GZipUtil.compressFile(mergedTextPath, mergedGzipPath);

      String finalPath = mergedGzipPath;
      // 如果是加密的，加密文件
      if (isEncrypted) {
        WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
          config.secretKey ?? "",
          config.secret ?? "",
        );
        await cryptUtil.encryptFile(mergedGzipPath, mergedEncryptedPath!);
        finalPath = mergedEncryptedPath;
      }

      // 计算新的 sha256
      var newSha256 = await Sha256Util.sha256File(finalPath);

      // 生成新的文件路径（日期文件夹，去掉小时）
      var newRemotePath = _buildDateFilePath(dateKey, newUuid);

      // 上传新文件
      await storage.uploadFile(newRemotePath, finalPath);

      // 上传 sha256 文件
      await storage.writeFile("$newRemotePath.sha256", utf8.encode(newSha256));

      // 更新索引：删除旧索引，添加新索引
      for (var filepath in filepathsToRemove) {
        indexesService.removeIndex(filepath);
      }
      indexesService.addIndex(newRemotePath, newSha256);
      // 写入索引文件
      await indexesService.writeIndexes();
      await indexesService.uploadIndexes();

      // 删除远程旧文件
      for (var filepath in filepathsToRemove) {
        try {
          await storage.deleteFile(filepath);
          await storage.deleteFile("$filepath.sha256");
        } catch (e) {
          print('删除文件失败: $filepath, 错误: $e');
        }
      }
    } catch (e) {
      print('按天合并文件失败: $dateKey, 错误: $e');
    } finally {
      // 清理所有临时文件
      if (mergedTextPath != null && await File(mergedTextPath).exists()) {
        try {
          await File(mergedTextPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      if (mergedGzipPath != null && await File(mergedGzipPath).exists()) {
        try {
          await File(mergedGzipPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      if (mergedEncryptedPath != null &&
          await File(mergedEncryptedPath).exists()) {
        try {
          await File(mergedEncryptedPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      for (var tempFile in tempFiles) {
        if (await File(tempFile).exists()) {
          try {
            await File(tempFile).delete();
          } catch (e) {
            // 忽略删除失败
          }
        }
      }
    }
  }

  /// 合并一年的文件
  Future<void> _mergeYearFiles(
    int year,
    List<MapEntry<String, String>> files,
    WenzbakStorageClientService storage,
    WenzbakBlockIndexesService indexesService,
  ) async {
    bool isEncrypted = config.secretKey != null && config.secret != null;
    String? mergedTextPath;
    String? mergedGzipPath;
    String? mergedEncryptedPath;
    List<String> tempFiles = [];
    List<String> filepathsToRemove = [];

    try {
      // 创建合并文本文件
      var newUuid = Uuid().v4();
      mergedTextPath = await _getLocalTempTextPath(newUuid);
      mergedGzipPath = await _getLocalTempPath(newUuid);
      if (isEncrypted) {
        mergedEncryptedPath = await _getLocalTempEncryptedPath(newUuid);
      }

      // 下载所有文件并解压，通过数据流追加到合并文件
      bool hasData = false;
      for (var entry in files) {
        var remotePath = entry.key;
        var localPath = await _downloadFileForMerge(remotePath, storage);
        if (localPath == null) {
          continue;
        }

        String? decryptedPath;
        String? decompressedPath;

        try {
          // 如果是加密的，先解密
          if (isEncrypted) {
            decryptedPath = await _getLocalTempDecryptedPath(Uuid().v4());
            tempFiles.add(decryptedPath);
            WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
              config.secretKey ?? "",
              config.secret ?? "",
            );
            await cryptUtil.decryptFile(localPath, decryptedPath);
            localPath = decryptedPath;
          }

          // 解压 gzip 到临时文本文件
          decompressedPath = await _getLocalTempTextPath(Uuid().v4());
          tempFiles.add(decompressedPath);
          await GZipUtil.decompressFile(localPath, decompressedPath);

          // 检查文件是否有内容
          var fileLength = await File(decompressedPath).length();
          if (fileLength > 0) {
            // 如果不是第一个文件，先追加换行符
            if (await File(mergedTextPath).exists()) {
              await FileUtils.appendString(mergedTextPath, '\n');
            }
            // 追加文件内容
            await FileUtils.appendFile(mergedTextPath, decompressedPath);
            hasData = true;
          }

          filepathsToRemove.add(remotePath);
        } finally {
          // 清理临时文件
          if (decryptedPath != null && await File(decryptedPath).exists()) {
            try {
              await File(decryptedPath).delete();
            } catch (e) {
              // 忽略删除失败
            }
          }
          if (decompressedPath != null &&
              await File(decompressedPath).exists()) {
            try {
              await File(decompressedPath).delete();
            } catch (e) {
              // 忽略删除失败
            }
          }
        }
      }

      if (!hasData) {
        return;
      }

      // 压缩合并后的文本文件
      await GZipUtil.compressFile(mergedTextPath, mergedGzipPath);

      String finalPath = mergedGzipPath;
      // 如果是加密的，加密文件
      if (isEncrypted) {
        WenzbakCryptUtil cryptUtil = WenzbakCryptUtil(
          config.secretKey ?? "",
          config.secret ?? "",
        );
        await cryptUtil.encryptFile(mergedGzipPath, mergedEncryptedPath!);
        finalPath = mergedEncryptedPath;
      }

      // 计算新的 sha256
      var newSha256 = await Sha256Util.sha256File(finalPath);

      // 生成新的文件路径（年份文件夹）
      var newRemotePath = _buildYearFilePath(year, newUuid);

      // 上传新文件
      await storage.uploadFile(newRemotePath, finalPath);

      // 上传 sha256 文件
      await storage.writeFile("$newRemotePath.sha256", utf8.encode(newSha256));

      // 更新索引：删除旧索引，添加新索引
      for (var filepath in filepathsToRemove) {
        indexesService.removeIndex(filepath);
      }
      indexesService.addIndex(newRemotePath, newSha256);

      // 写入索引文件
      await indexesService.writeIndexes();
      await indexesService.uploadIndexes();
      // 删除远程旧文件
      for (var filepath in filepathsToRemove) {
        try {
          await storage.deleteFile(filepath);
          await storage.deleteFile("$filepath.sha256");
        } catch (e) {
          print('删除文件失败: $filepath, 错误: $e');
        }
      }
    } catch (e) {
      print('按年合并文件失败: $year, 错误: $e');
    } finally {
      // 清理所有临时文件
      if (mergedTextPath != null && await File(mergedTextPath).exists()) {
        try {
          await File(mergedTextPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      if (mergedGzipPath != null && await File(mergedGzipPath).exists()) {
        try {
          await File(mergedGzipPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      if (mergedEncryptedPath != null &&
          await File(mergedEncryptedPath).exists()) {
        try {
          await File(mergedEncryptedPath).delete();
        } catch (e) {
          // 忽略删除失败
        }
      }
      for (var tempFile in tempFiles) {
        if (await File(tempFile).exists()) {
          try {
            await File(tempFile).delete();
          } catch (e) {
            // 忽略删除失败
          }
        }
      }
    }
  }

  /// 下载文件用于合并
  Future<String?> _downloadFileForMerge(
    String remotePath,
    WenzbakStorageClientService storage,
  ) async {
    try {
      var filename = FileUtils.encodePath(remotePath);
      var saveDir = config.getLocalBlockSaveDir();
      var localPath = [saveDir, filename].join("/");

      // 如果文件已存在，直接返回
      if (await File(localPath).exists()) {
        return localPath;
      }

      // 下载文件
      await storage.downloadFile(remotePath, localPath);
      return localPath;
    } catch (e) {
      print('下载文件失败: $remotePath, 错误: $e');
      return null;
    }
  }

  /// 获取本地临时文件路径
  Future<String> _getLocalTempPath(String uuid) async {
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    return [saveDir, "$uuid.gz"].join("/");
  }

  /// 获取本地临时文本文件路径
  Future<String> _getLocalTempTextPath(String uuid) async {
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    return [saveDir, "$uuid.txt"].join("/");
  }

  /// 获取本地临时加密文件路径
  Future<String> _getLocalTempEncryptedPath(String uuid) async {
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    return [saveDir, "$uuid.enc"].join("/");
  }

  /// 获取本地临时解密文件路径
  Future<String> _getLocalTempDecryptedPath(String uuid) async {
    var saveDir = config.getLocalBlockSaveDir();
    if (!await Directory(saveDir).exists()) {
      await Directory(saveDir).create(recursive: true);
    }
    return [saveDir, "$uuid.dec"].join("/");
  }

  /// 构建日期文件路径（去掉小时）
  String _buildDateFilePath(String dateKey, String uuid) {
    // dateKey 格式：YYYY-MM-DD
    if (config.secretKey == null) {
      return [
        config.remoteRootPath ?? 'wenzbak',
        'public',
        'data',
        dateKey,
        "$uuid.gz",
      ].join('/');
    } else {
      return [
        config.remoteRootPath ?? 'wenzbak',
        'private',
        config.secretKey,
        'data',
        dateKey,
        "$uuid.gz",
      ].join('/');
    }
  }

  /// 构建年份文件路径
  String _buildYearFilePath(int year, String uuid) {
    if (config.secretKey == null) {
      return [
        config.remoteRootPath ?? 'wenzbak',
        'public',
        'data',
        year.toString(),
        "$uuid.gz",
      ].join('/');
    } else {
      return [
        config.remoteRootPath ?? 'wenzbak',
        'private',
        config.secretKey,
        'data',
        year.toString(),
        "$uuid.gz",
      ].join('/');
    }
  }

  @override
  Future<void> loadBlockFileUploadCache() async {
    await _blockFileUploadCache.readCache();
  }
}
