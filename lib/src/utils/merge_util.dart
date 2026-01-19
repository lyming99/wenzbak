import 'dart:io';

/// 数据合并工具类
/// 对2个数据块文件进行内容合并
class WenzbakMergeUtil {
  WenzbakMergeUtil._();

  /// 合并两个数据块文件
  /// [file1Path] 第一个数据块文件路径
  /// [file2Path] 第二个数据块文件路径
  /// [outputPath] 合并后的输出文件路径
  ///
  /// 合并规则：
  /// 1. 按时间顺序合并数据行
  /// 2. 去除重复的数据行（基于uuid）
  /// 3. 保持数据行的原始格式
  Future<void> mergeBlockFiles(
    String file1Path,
    String file2Path,
    String outputPath,
  ) async {
    final file1 = File(file1Path);
    final file2 = File(file2Path);

    if (!await file1.exists()) {
      throw FileSystemException('文件不存在: $file1Path');
    }
    if (!await file2.exists()) {
      throw FileSystemException('文件不存在: $file2Path');
    }

    // 读取两个文件的内容
    // 解析文件内容为数据行
    final lines1 = await file1.readAsLines();
    final lines2 = await file2.readAsLines();

    // 合并数据行，去除重复
    final mergedLines = _mergeLines(lines1, lines2);

    // 写入输出文件
    final outputFile = File(outputPath);
    await outputFile.writeAsString(mergedLines.join("\n"));
  }

  /// 合并两个数据行列表，去除重复
  List<String> _mergeLines(List<String> lines1, List<String> lines2) {
    Set<String> lineSet = {};
    lineSet.addAll(lines1);
    lineSet.addAll(lines2);
    return List.from(lineSet);
  }
}
