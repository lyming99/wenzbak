import 'package:wenzbak/src/models/message.dart';

/// 消息上传服务抽象类
/// 负责消息缓存、写入和上传功能
abstract class WenzbakMessageUploadService {
  /// 添加消息到缓存
  Future<void> addMessage(WenzbakMessage message);

  /// 读取消息缓存
  Future<void> readCache();

  /// 执行上传任务
  Future<void> executeUploadTask();

  /// 上传文件
  /// [localPath] 本地文件路径
  /// 返回远程文件路径，如果上传失败返回 null
  Future<String?> uploadFile(String localPath);

  /// 删除1天前的文件
  /// 删除 assets 目录下1天前的文件
  Future<void> deleteOldFiles();
}
