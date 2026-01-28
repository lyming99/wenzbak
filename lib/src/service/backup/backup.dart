import 'package:wenzbak/src/models/index.dart';
import 'package:wenzbak/src/service/data/block_data.dart';
import 'package:wenzbak/src/service/message/message.dart';

abstract class WenzbakClientService {
  bool get isSecretClient;

  /// 添加备份数据到系统
  /// 系统会自动将数据上传，失败会重新上传
  Future<void> addBackupData(WenzbakDataLine line);

  Future<void> addBackupDataList(List<WenzbakDataLine> lines);

  /// 上传文件
  Future<String?> uploadAssets(String localPath);

  /// 获取文件路径
  String? getRemoteAssetsPath(String localPath);

  /// 上传临时文件
  Future<String?> uploadTempAssets(String localPath);

  /// 获取临时文件路径
  String? getRemoteTempAssetsPath(String localPath);

  /// 添加数据接收器
  void addDataReceiver(WenzbakDataReceiver receiver);

  /// 移除数据接收器
  void removeDataReceiver(WenzbakDataReceiver receiver);

  /// 下载指定remotePath文件,返回本地路径
  /// [remotePath] 文件remotePath
  Future<String?> downloadFile(String remotePath);

  /// 下载指定remotePath数据
  Future<void> downloadData(String remotePath);

  /// 下载所有数据: 增量下载
  Future<void> downloadAllData();

  Future<void> reloadAllData();

  /// 添加消息接收器
  void addMessageReceiver(MessageReceiver receiver);

  /// 移除消息接收器
  void removeMessageReceiver(MessageReceiver receiver);

  /// 发送消息
  Future<void> sendMessage(WenzbakMessage message);

  /// 启动消息Timer
  void startMessageTimer();

  /// 停止消息Timer
  void stopMessageTimer();

  Future uploadAllData(bool oneHoursAgo);

  Future<void> mergeHistoryData();

  Future<void> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]);
}
