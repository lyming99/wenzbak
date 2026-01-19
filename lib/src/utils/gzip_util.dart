import 'dart:io';
import 'dart:typed_data';

/// Gzip压缩工具类
/// 提供文件压缩功能，将文件压缩为gzip格式
class GZipUtil {
  GZipUtil._();

  /// 将原始文件压缩为gzip格式并保存到目标路径
  /// [originalFilePath] 原始文件路径
  /// [targetFilePath] 目标文件路径（压缩后的文件路径）
  /// 如果原始文件不存在，将抛出异常
  /// 如果目标文件的父目录不存在，将自动创建
  static Future<int> compressFile(
    String originalFilePath,
    String targetFilePath,
  ) async {
    // 检查原始文件是否存在
    final originalFile = File(originalFilePath);
    if (!await originalFile.exists()) {
      throw FileSystemException('原始文件不存在', originalFilePath);
    }

    // 读取原始文件内容
    final originalBytes = await originalFile.readAsBytes();

    // 如果文件为空，直接创建空的目标文件
    if (originalBytes.isEmpty) {
      final targetFile = File(targetFilePath);
      final targetDir = targetFile.parent;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      await targetFile.writeAsBytes([]);
      return -1;
    }

    // 使用gzip压缩数据
    final compressedBytes = gzip.encode(originalBytes);

    // 确保目标文件的父目录存在
    final targetFile = File(targetFilePath);
    final targetDir = targetFile.parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 写入压缩后的数据到目标文件
    await targetFile.writeAsBytes(compressedBytes);
    return compressedBytes.length;
  }

  static Uint8List compressBytes(Uint8List bytes) {
    return Uint8List.fromList(gzip.encode(bytes));
  }

  static Uint8List decompressBytes(Uint8List bytes) {
    return Uint8List.fromList(gzip.decode(bytes));
  }

  /// 将gzip压缩文件解压到目标路径
  /// [compressedFilePath] 压缩文件路径
  /// [targetFilePath] 目标文件路径（解压后的文件路径）
  /// 如果压缩文件不存在，将抛出异常
  /// 如果目标文件的父目录不存在，将自动创建
  static Future<void> decompressFile(
    String compressedFilePath,
    String targetFilePath,
  ) async {
    // 检查压缩文件是否存在
    final compressedFile = File(compressedFilePath);
    if (!await compressedFile.exists()) {
      throw FileSystemException('压缩文件不存在', compressedFilePath);
    }

    // 读取压缩文件内容
    final compressedBytes = await compressedFile.readAsBytes();

    // 如果文件为空，直接创建空的目标文件
    if (compressedBytes.isEmpty) {
      final targetFile = File(targetFilePath);
      final targetDir = targetFile.parent;
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      await targetFile.writeAsBytes([]);
      return;
    }

    // 使用gzip解压数据
    final decompressedBytes = gzip.decode(compressedBytes);

    // 确保目标文件的父目录存在
    final targetFile = File(targetFilePath);
    final targetDir = targetFile.parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 写入解压后的数据到目标文件
    await targetFile.writeAsBytes(decompressedBytes);
  }
}
