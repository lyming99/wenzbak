import 'package:wenzbak/src/service/message/message.dart';

/// 消息下载服务抽象类
/// 负责消息下载、读取和文件下载功能
abstract class WenzbakMessageDownloadService {
  /// 读取消息
  /// [receivers] 消息接收器列表，每条消息会调用所有接收器
  Future<void> readMessage(Iterable<MessageReceiver> receivers);
}
