/// 待上传block数据文件缓存抽象类
/// 用于管理待上传的block数据文件，按小时组织文件
abstract class WenzbakBlockFileUploadCache {
  /// 获取或生成当前小时的文件存储路径
  /// 返回当前小时对应的缓存文件路径
  /// 如果文件不存在，会创建对应的目录结构
  Future<String?> getCurrentCacheFile(DateTime?dateTime);

  /// 获取一小时之前的数据文件用于上传
  /// 返回所有一小时之前的缓存文件路径列表
  Future<List<String>> getUploadFiles(bool oneHoursAgo);

  /// 文件上传后清除文件
  /// [filePath] 要删除的文件路径
  Future<void> removeFile(String filePath);

  /// 读取缓存数据
  /// 从持久化存储中读取缓存数据到内存
  Future<void> readCache();

  /// 写入缓存数据
  /// 将内存中的缓存数据写入持久化存储
  Future<void> writeCache();
}
