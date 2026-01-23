import 'package:wenzbak/src/models/index.dart';

/// 数据接收器
/// 用于接收数据下载时解析出来的行数据
abstract class WenzbakDataReceiver {
  /// 接收一行数据
  /// [lines] 解析出来的数据行
  Future onReceive(List<WenzbakDataLine> lines);
}

/// 记录与查询数据块，通过本地数据库实现
abstract class WenzbakBlockDataService {
  /// 添加数据行
  Future<void> addBackupData(WenzbakDataLine line);

  Future<void> addBackupDataList(List<WenzbakDataLine> line);

  /// 上传1小时前数据：每小时取余，1小时前不代表间隔1小时。
  /// 说明：数据记录按小时合并，避免文件数量过多。
  /// 为啥不直接按天合并？为了避免数据上传时间太久，导致数据没有上传。
  /// 如何保障实时性？通过消息系统传递数据。
  Future<void> uploadBlockData(bool oneHoursAgo);

  /// 下载指定路径数据
  Future<void> downloadData(
    String remotePath,
    String? sha256,
    Set<WenzbakDataReceiver> dataReceivers,
  );

  /// 下载所有数据
  Future<void> downloadAllData(Set<WenzbakDataReceiver> dataReceivers);

  /// 合并数据索引
  /// 1. 根据索引文件路径读取文件日期和时间
  /// 2. 实现按天合并：如果存在1天前数据(每小时一个文件)，则合并数据到日期文件夹
  /// 3. 实现按年合并：如果存在1年前数据，则合并到年份文件夹
  /// 4. 合并后要更新索引到索引文件
  /// 5. 只合并本设备数据
  /// 6. 合并数据为直接拼接内容即可(换行拼接)
  Future<void> mergeBlockData();

  Future<void> loadBlockFileUploadCache();
}
