import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:wenzbak/src/config/backup.dart';
import 'package:wenzbak/src/utils/gzip_util.dart';
import 'package:wenzbak/src/utils/sha256_util.dart';

/// 1.要验证private模式的索引文件如何保存
/// 2.增加1000个索引，验证索引文件长度是否合适
void main() {
  String clientId = Uuid().v4();
  // /wenzflow/private/
  var config = WenzbakConfig(
    deviceId: clientId,
    remoteRootPath: 'wenzflow',
    localRootPath: 'wenzflow',
    secretKey: clientId,
    secret: "hello",
  );
  var uploadKey = config.getUploadKey();
  var localBlockHourDir = config.getLocalBlockHourDir(null);
  var localPublicBlockIndexPath = config.getLocalBlockIndexPath();
  var localCurrentPublicBlockHourBakPath = config
      .getLocalCurrentPublicBlockHourBakPath();
  var localPublicBlockTextCachePath = config.getLocalPublicBlockTextCachePath(
    Uuid().v4(),
  );
  var localSecretAssetPath = config.getLocalSecretAssetPath();
  var remoteBlockIndexPath = config.getRemoteCurrentBlockIndexPath();
  var remoteBlockHourDir = config.getRemoteBlockHourDir(null);
  var remoteAssetPath = config.getRemoteAssetPath();
  var remoteBlockHourPath = config.getRemoteBlockHourPath(Uuid().v4());
  var remoteBlockSha256Path = config.getRemoteBlockSha256Path(Uuid().v4());
  // 打印print
  print('uploadKey: $uploadKey');
  print('localBlockHourDir: $localBlockHourDir');
  print('localPublicBlockIndexPath: $localPublicBlockIndexPath');
  print(
    'localCurrentPublicBlockHourBakPath: $localCurrentPublicBlockHourBakPath',
  );
  print('localPublicBlockTextCachePath: $localPublicBlockTextCachePath');
  print('localSecretAssetPath: $localSecretAssetPath');
  print('remoteBlockIndexPath: $remoteBlockIndexPath');
  print('remoteBlockHourDir: $remoteBlockHourDir');
  print('remoteAssetPath: $remoteAssetPath');
  print('remoteBlockHourPath: $remoteBlockHourPath');
  print('remoteBlockSha256Path: $remoteBlockSha256Path');
  List<String> indexList = [];
  for (var i = 0; i < 10000; i++) {
    var blockPath = config.getRemoteBlockHourPath(Uuid().v4());
    indexList.add("$blockPath ${Sha256Util.sha256(blockPath ?? '')}");
  }
  var text = indexList.join("\n");
  print(text.length);
  var bytes = GZipUtil.compressBytes(utf8.encode(text));
  print(bytes.length);
}
