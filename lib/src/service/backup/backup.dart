import 'package:wenzbak/src/models/index.dart';
import 'package:wenzbak/src/service/message/message.dart';

/// 数据接收器
/// 用于接收数据下载时解析出来的行数据
abstract class WenzbakDataReceiver {
  /// 接收一行数据
  /// [line] 解析出来的数据行
  Future onReceive(WenzbakDataLine line);
}

abstract class WenzbakClientService {
  /// 添加备份数据到系统
  /// 系统会自动将数据上传，失败会重新上传
  Future<void> addBackupData(WenzbakDataLine line);

  /// 上传文件
  Future<String?> uploadAssets(String localPath);

  /// 上传临时文件
  Future<String?> uploadTempAssets(String localPath);

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

  /// 添加消息接收器
  void addMessageReceiver(MessageReceiver receiver);

  /// 启动消息Timer
  void startMessageTimer();

  /// 停止消息Timer
  void stopMessageTimer();

  Future uploadAllData(bool oneHoursAgo);

  Future<void> mergeHistoryData();

  Future<void> uploadDeviceInfo([WenzbakDeviceInfo? deviceInfo]);
}
