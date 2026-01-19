import 'dart:io';

import 'package:wenzbak/src/utils/sha256_util.dart';

class FileUtils {
  FileUtils._();

  static String getFileName(String path) {
    path = path.replaceAll("\\", "/");
    return path.split('/').last;
  }

  /// 获取文件扩展名（不包含点号）
  /// [path] 文件路径或文件名
  /// 返回文件扩展名，如果没有扩展名则返回空字符串
  /// 例如：'file.txt' -> 'txt', 'path/to/file.jpg' -> 'jpg', 'file' -> ''
  static String getFileExtension(String path) {
    var filename = getFileName(path);
    var lastDotIndex = filename.lastIndexOf('.');
    return lastDotIndex > 0 ? filename.substring(lastDotIndex + 1) : '';
  }

  static String encodePath(String path) {
    return Sha256Util.sha256(path);
  }

  static String getDateFilePath(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String getTimeFilePath(DateTime date, [String separator = '-']) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}$separator${date.hour.toString().padLeft(2, '0')}';
  }

  static Future createParentDir(String path) async {
    var parentDir = Directory(path).parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
  }

  static Future appendLine(String filepath, String line) async {
    await createParentDir(filepath);
    if (!await File(filepath).exists()) {
      await File(filepath).writeAsString(line);
    } else {
      await File(
        filepath,
      ).writeAsString('\n$line', mode: FileMode.append, flush: true);
    }
  }

  static Future exist(String filepath) async {
    if (filepath.isEmpty) {
      return false;
    }
    return await File(filepath).exists();
  }

  static Future getFileLength(String tempPath) async {
    return await File(tempPath).length();
  }

  static Future<List<String>> readLines(String filepath) async {
    if (!await exist(filepath)) {
      return [];
    }
    return await File(filepath).readAsLines();
  }

  static Future<void> writeLines(
    String filepath,
    Iterable<String> lines,
  ) async {
    await createParentDir(filepath);
    await File(filepath).writeAsString(lines.join('\n'));
  }

  /// 追加字符串到文件
  /// [filepath] 文件路径
  /// [content] 要追加的字符串内容
  /// 如果文件不存在，会先创建文件
  static Future<void> appendString(String filepath, String content) async {
    await createParentDir(filepath);
    if (!await File(filepath).exists()) {
      await File(filepath).writeAsString(content);
    } else {
      await File(filepath).writeAsString(content, mode: FileMode.append);
    }
  }

  /// 追加文件内容到目标文件
  /// [targetFilepath] 目标文件路径
  /// [sourceFilepath] 源文件路径
  /// 如果目标文件不存在，会先创建文件
  /// 如果源文件不存在，将抛出异常
  static Future<void> appendFile(
    String targetFilepath,
    String sourceFilepath,
  ) async {
    await createParentDir(targetFilepath);

    final sourceFile = File(sourceFilepath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('源文件不存在', sourceFilepath);
    }

    final targetFile = File(targetFilepath);
    final targetRaf = await targetFile.open(mode: FileMode.append);

    try {
      // 使用流方式复制文件内容，避免一次性加载到内存
      await for (final chunk in sourceFile.openRead()) {
        await targetRaf.writeFrom(chunk);
      }
    } finally {
      await targetRaf.close();
    }
  }

  static Future deleteFile(String filepath) async {
    if (filepath.isEmpty) {
      return;
    }
    try {
      if(await File(filepath).exists()) {
        await File(filepath).delete();
      }
    } catch (e) {
      print(e);
    }
  }
}
