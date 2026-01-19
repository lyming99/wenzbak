import 'dart:async';
import 'dart:io';
import 'dart:convert';

/// 文件行读取工具类
/// 提供流式读取文件行的功能，通过回调方法处理行数据
/// 适用于处理大文件，不会一次性将整个文件加载到内存中
class FileLineReaderUtil {
  FileLineReaderUtil._();

  /// 流式读取文件行
  /// [filePath] 文件路径
  /// [onLine] 处理每一行的回调函数，参数为行内容和行号（从1开始）
  /// [onError] 错误处理回调函数（可选）
  /// [encoding] 文件编码，默认为 utf8
  /// 
  /// 示例：
  /// ```dart
  /// await FileLineReaderUtil.readLines(
  ///   'path/to/file.txt',
  ///   onLine: (line, lineNumber) {
  ///     print('Line $lineNumber: $line');
  ///   },
  /// );
  /// ```
  static Future<void> readLines(
    String filePath, {
    required Future Function(String line, int lineNumber) onLine,
    void Function(dynamic error, StackTrace stackTrace)? onError,
    Encoding encoding = utf8,
  }) async {
    final file = File(filePath);
    
    if (!await file.exists()) {
      final error = FileSystemException('文件不存在', filePath);
      if (onError != null) {
        onError(error, StackTrace.current);
      } else {
        throw error;
      }
      return;
    }

    var lineNumber = 1;
    var buffer = StringBuffer();
    
    try {
      // 使用编码器的流式转换，确保正确处理多字节字符边界
      // 这对于UTF-8等变长编码非常重要
      // transform 会自动处理多字节字符的边界，即使chunk在多字节字符中间截断也能正确解码
      Stream<String> stringStream;
      if (encoding == utf8) {
        // UTF-8 使用专门的解码器，自动处理多字节字符边界
        stringStream = file.openRead().transform(utf8.decoder);
      } else {
        // 其他编码也使用流式转换
        stringStream = file.openRead().transform(encoding.decoder);
      }
      
      await for (final chunkString in stringStream) {
        buffer.write(chunkString);
        
        // 处理缓冲区中的完整行
        var content = buffer.toString();
        var lineEndIndex = 0;
        
        while (lineEndIndex < content.length) {
          var newlineIndex = content.indexOf('\n', lineEndIndex);
          
          if (newlineIndex == -1) {
            // 没有找到换行符，保留剩余内容在缓冲区
            break;
          }
          
          // 提取一行（包含换行符之前的内容）
          var line = content.substring(lineEndIndex, newlineIndex);
          
          // 移除可能的回车符（处理 \r\n）
          if (line.endsWith('\r')) {
            line = line.substring(0, line.length - 1);
          }
          
          // 调用回调处理这一行
          try {
            await onLine(line, lineNumber);
            lineNumber++;
          } catch (e, stackTrace) {
            if (onError != null) {
              onError(e, stackTrace);
            } else {
              rethrow;
            }
          }
          
          lineEndIndex = newlineIndex + 1;
        }
        
        // 保留未完成的行在缓冲区
        if (lineEndIndex < content.length) {
          buffer.clear();
          buffer.write(content.substring(lineEndIndex));
        } else {
          buffer.clear();
        }
      }
      
      // 处理最后一行（如果文件不以换行符结尾）
      var remaining = buffer.toString();
      if (remaining.isNotEmpty) {
        try {
          onLine(remaining, lineNumber);
        } catch (e, stackTrace) {
          if (onError != null) {
            onError(e, stackTrace);
          } else {
            rethrow;
          }
        }
      }
    } catch (e, stackTrace) {
      if (onError != null) {
        onError(e, stackTrace);
      } else {
        rethrow;
      }
    }
  }

  /// 流式读取文件行（简化版本）
  /// [filePath] 文件路径
  /// [onLine] 处理每一行的回调函数，参数为行内容
  /// [encoding] 文件编码，默认为 utf8
  /// 
  /// 示例：
  /// ```dart
  /// await FileLineReaderUtil.readLinesSimple(
  ///   'path/to/file.txt',
  ///   onLine: (line) {
  ///     print(line);
  ///   },
  /// );
  /// ```
  static Future<void> readLinesSimple(
    String filePath, {
    required Future Function(String line) onLine,
    Encoding encoding = utf8,
  }) async {
    await readLines(
      filePath,
      onLine: (line, _)async => await onLine(line),
      encoding: encoding,
    );
  }

  /// 流式读取文件行并返回所有行（不推荐用于大文件）
  /// [filePath] 文件路径
  /// [encoding] 文件编码，默认为 utf8
  /// 返回所有行的列表
  /// 
  /// 注意：此方法会将所有行加载到内存中，不适用于非常大的文件
  /// 对于大文件，请使用 readLines 方法
  static Future<List<String>> readAllLines(
    String filePath, {
    Encoding encoding = utf8,
  }) async {
    final lines = <String>[];
    await readLines(
      filePath,
      onLine: (line, _) async => lines.add(line),
      encoding: encoding,
    );
    return lines;
  }

  /// 流式读取文件行并统计行数
  /// [filePath] 文件路径
  /// [encoding] 文件编码，默认为 utf8
  /// 返回文件的总行数
  static Future<int> countLines(
    String filePath, {
    Encoding encoding = utf8,
  }) async {
    var count = 0;
    await readLines(
      filePath,
      onLine: (_, __)async => count++,
      encoding: encoding,
    );
    return count;
  }

  /// 流式读取文件行，支持提前停止
  /// [filePath] 文件路径
  /// [onLine] 处理每一行的回调函数，返回 true 继续读取，返回 false 停止读取
  /// [encoding] 文件编码，默认为 utf8
  /// 
  /// 示例：
  /// ```dart
  /// await FileLineReaderUtil.readLinesWithStop(
  ///   'path/to/file.txt',
  ///   onLine: (line, lineNumber) {
  ///     print('Line $lineNumber: $line');
  ///     // 读取前10行后停止
  ///     return lineNumber < 10;
  ///   },
  /// );
  /// ```
  static Future<void> readLinesWithStop(
    String filePath, {
    required bool Function(String line, int lineNumber) onLine,
    Encoding encoding = utf8,
  }) async {
    final file = File(filePath);
    
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', filePath);
    }

    var lineNumber = 1;
    var buffer = StringBuffer();
    StreamSubscription<String>? subscription;
    var shouldContinue = true;
    
    try {
      // 使用编码器的流式转换，确保正确处理多字节字符边界
      Stream<String> stringStream;
      if (encoding == utf8) {
        stringStream = file.openRead().transform(utf8.decoder);
      } else {
        stringStream = file.openRead().transform(encoding.decoder);
      }
      
      subscription = stringStream.listen(
        (chunkString) {
          if (!shouldContinue) {
            subscription?.cancel();
            return;
          }
          
          buffer.write(chunkString);
          
          // 处理缓冲区中的完整行
          var content = buffer.toString();
          var lineEndIndex = 0;
          
          while (lineEndIndex < content.length && shouldContinue) {
            var newlineIndex = content.indexOf('\n', lineEndIndex);
            
            if (newlineIndex == -1) {
              // 没有找到换行符，保留剩余内容在缓冲区
              break;
            }
            
            // 提取一行（包含换行符之前的内容）
            var line = content.substring(lineEndIndex, newlineIndex);
            
            // 移除可能的回车符（处理 \r\n）
            if (line.endsWith('\r')) {
              line = line.substring(0, line.length - 1);
            }
            
            // 调用回调处理这一行
            shouldContinue = onLine(line, lineNumber);
            lineNumber++;
            
            if (!shouldContinue) {
              subscription?.cancel();
              break;
            }
            
            lineEndIndex = newlineIndex + 1;
          }
          
          // 保留未完成的行在缓冲区
          if (lineEndIndex < content.length) {
            buffer.clear();
            buffer.write(content.substring(lineEndIndex));
          } else {
            buffer.clear();
          }
        },
        onError: (error, stackTrace) {
          throw error;
        },
        onDone: () {
          // 处理最后一行（如果文件不以换行符结尾且应该继续）
          if (shouldContinue) {
            var remaining = buffer.toString();
            if (remaining.isNotEmpty) {
              onLine(remaining, lineNumber);
            }
          }
        },
        cancelOnError: false,
      );

      // 等待流完成或被取消
      await subscription.asFuture();
    } catch (e) {
      if (e is! StateError || !e.message.contains('Future already completed')) {
        rethrow;
      }
    } finally {
      await subscription?.cancel();
    }
  }
}
