import 'package:wenzbak/src/config/backup.dart';

import 'impl/indexes_impl.dart';

abstract class WenzbakBlockIndexesService {
  static final Map<String, WenzbakBlockIndexesService> _indexesServices = {};

  static WenzbakBlockIndexesService getInstance(WenzbakConfig config) {
    var key = config.getUploadKey();
    return _indexesServices.putIfAbsent(
      key,
          () => WenzbakBlockIndexesServiceImpl(config),
    );
  }

  Future<Map<String, String>> getIndexes();

  /// 调用此方法前，必须先读取本地索引文件，否则可能失效
  Future<void> addIndex(String filepath, String sha256);

  /// 调用此方法前，必须先读取本地索引文件，否则可能失效
  Future<void> removeIndex(String filepath);

  Future readIndexes();

  Future writeIndexes();

  Future uploadIndexes();
}
