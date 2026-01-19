import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/service/storage/storage.dart';
import 'package:wenzbak/src/utils/file_utils.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:synchronized/synchronized.dart';

import '../indexes.dart';

class WenzbakBlockIndexesServiceImpl extends WenzbakBlockIndexesService {
  WenzbakBlockIndexesServiceImpl(this.config);

  WenzbakConfig config;
  bool isRead = false;
  var indexesMap = HashMap<String, String>();
  var lock = Lock();

  @override
  Future<Map<String, String>> getIndexes() async {
    await readIndexes();
    return indexesMap;
  }

  @override
  Future<void> addIndex(String filepath, String sha256) async {
    await readIndexes();
    indexesMap[filepath] = sha256;
  }

  @override
  Future<void> removeIndex(String filepath) async {
    await readIndexes();
    indexesMap.remove(filepath);
  }

  @override
  Future uploadIndexes() async {
    var storage = WenzbakStorageClientService.getInstance(config);
    if (storage == null) {
      return;
    }
    var indexPath = config.getRemoteCurrentBlockIndexPath();
    var indexString = getIndexesString();
    var bytes = utf8.encode(indexString);
    var gz = GZipUtil.compressBytes(bytes);
    await storage.writeFile(indexPath, gz);
  }

  @override
  Future readIndexes() async {
    await lock.synchronized(() async {
      if (isRead) {
        return;
      }
      var indexFilepath = config.getLocalBlockIndexPath();
      // 一行一个，文件的sha256 + 文件路径
      // 1w个文件*(64+32) = 96w字节 = 960kb内存
      if (await File(indexFilepath).exists()) {
        var lines = await File(indexFilepath).readAsLines();
        for (var line in lines) {
          var pos = line.indexOf(" ");
          if (pos != -1) {
            var sha256 = line.substring(0, pos);
            var filepath = line.substring(pos + 1);
            indexesMap[filepath] = sha256;
          }
        }
      }
      isRead = true;
    });
  }

  @override
  Future writeIndexes() async {
    await lock.synchronized(() async {
      var indexFilepath = config.getLocalBlockIndexPath();
      await FileUtils.createParentDir(indexFilepath);
      await File(indexFilepath).writeAsString(getIndexesString());
    });
  }

  String getIndexesString() {
    var buffer = StringBuffer();
    for (var line in indexesMap.entries) {
      var path = line.key;
      var sha256 = line.value;
      buffer.write("$sha256 $path\n");
    }
    return buffer.toString();
  }
}
